#!/bin/bash
# This scripts runs the process of re-registeration from AWS to customer's RMT
# Hints
# git config --global http.sslverify false

clear

# Variables
rmt_server="PUT_RMT_FQDN_HERE"

# Install regionsrv package if not present
rpm -q cloud-regionsrv-client

if [ $? -eq 1 ];
   then
     zypper install -y cloud-regionsrv-client
fi

# Cleanup
registercloudguest --clean
SUSEConnect --cleanup

# Generate /etc/regionserverclnt.cfg
cat <<EOF > /etc/regionserverclnt.cfg
[server]

[instance]
EOF

# Deploy customizes susecloud plugin
cp /usr/lib/zypp/plugins/urlresolver/susecloud /usr/lib/zypp/plugins/urlresolver/susecloud_orig

cat <<EOF > /usr/lib/zypp/plugins/urlresolver/susecloud
#!/usr/bin/python3

# Copyright (c) 2019, SUSE LLC, All rights reserved.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 3.0 of the License, or (at your option) any later version.
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
# You should have received a copy of the GNU Lesser General Public
# License along with this library.

"""URL Resolver zypper plugin. This plugin resolves the url to the proper
   update server and sends along the necessary instance data."""


import base64
import logging

import cloudregister.registerutils as utils

from zypp_plugin import Plugin

utils.start_logging()
utils.set_proxy()


class SUSECloudPlugin(Plugin):
    def RESOLVEURL(self, headers, body):
        """Convert the URL for the repo"""
        repo_url = ''
        inst_data_bin_str = b''
        verify_credentials = False
        zypper_pid = utils.get_zypper_pid()
        prev_zypper_pid = utils.get_zypper_pid_cache()
        repo_credentials = headers.get('credentials')
        if zypper_pid != prev_zypper_pid:
            verify_credentials = True
        # Note this logic breaks when FATE#320882/PM-1251 gets implemented
        if (
                verify_credentials and not
                utils.credentials_files_are_equal(repo_credentials)
        ):
            self.error(
                {'CREDENTIAL_ERROR': 'INCONSISTENT'},
                'Not all credentials files are eqivalent: %s' % repo_credentials
            )
            return
        server_name = '$rmt_server'
#        if utils.is_new_registration():
#            server_name = utils.get_update_server_name_from_hosts(False)
#        else:
#            update_server = utils.get_smt()
#            if not update_server:
                # Something went seriously wrong, however try the name from
                # the hosts file
#                server_name = utils.get_update_server_name_from_hosts()
#            else:
#                server_name = update_server.get_FQDN()
        if server_name:
            srv_url = 'https://%s' % server_name
            repo_url = srv_url + headers.get('path')
            if repo_credentials:
                repo_url += '?credentials=' + repo_credentials
                if verify_credentials:
                    credentials_file_path = (
                        '/etc/zypp/credentials.d/%s' % repo_credentials
                    )
                    user, password = utils.get_credentials(
                        credentials_file_path
                    )
                    if not user or not password:
                        self.error(
                            {'CREDENTIAL_ERROR': 'NOCREDENTIALS'},
                            ('Credentials required for "%s" but not found '
                             'in "%s"' % (repo_url, credentials_file_path))
                        )
                        return
                    # Verify access to the server with the credentials
                    if not utils.has_smt_access(server_name, user, password):
                        self.error(
                            {'CREDENTIAL_ERROR': 'INVALID'},
                            ('Credentials are invalid. For details see '
                             '"/var/log/cloudregister". Re-register the '
                             'system with '
                             '"registercloudguest --force-new"')
                        )
                        return
                    utils.refresh_zypper_pid_cache()
            instance_data = b''
            try:
                instance_data = bytes(
                    utils.get_instance_data(utils.get_config()),
                    'utf-8'
                )
            except TypeError:
                logging.warning(
                    '[URL-Resolver] Unable to retrieve instance data'
                )
            # zypper wants a string or bad things happen on the other side
            inst_data_bin_str = base64.b64encode(
                instance_data).decode('utf-8')
        else:
            self.error(
                {'NO_TARGET_ERROR': 'NOTFOUND'},
                'Could not determine the FQDN of the update server'
            )
            return

        self.answer(
            'RESOLVEDURL',
            {'X-Instance-Data': inst_data_bin_str},
            repo_url
        )


plugin = SUSECloudPlugin()
plugin.main()
EOF

# Registration
curl --insecure https://$rmt_server/tools/rmt-client-setup --output rmt-client-setup

sh rmt-client-setup https://$rmt_server

# Test it
zypper ref

# Add zypper lock for customized config
zypper al cloud-regionsrv-client

# Cleanup
rm -f rmt-client-setup

# End
