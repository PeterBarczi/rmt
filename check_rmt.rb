#!/usr/bin/ruby
#
#

# Default states
rmt = 1
mysql = 1
nginx = 1
error = 0

# Check if the processes are running
rmt = 0 if (`ps -ax | pgrep -u _rmt` == "")
mysql = 0 if (`ps -ax | pgrep mysql` == "")
nginx = 0 if (`ps -ax | pgrep nginx` == "")
error = 1 if (rmt==0 or mysql==0 or nginx==0)


# Generate Output
output = "[
 {
   \"Source\": \"rmtapp\",
   \"DetailType\": \"rmt_app_health_status\",
   \"Detail\": \"{ \\\"error\\\": #{error}, \\\"mysql\\\": #{mysql}, \\\"rmt\\\": #{rmt}, \\\"nginx\\\": #{nginx} }\"
 }
]
"

# Save output to a file
open('/tmp/rmt_app.json', 'w') { |f|
  f.puts output
}

# Send the AWS event and remove output file
command = "aws events put-events --region eu-central-1 --entries file:///tmp/rmt_app.json && rm -f /tmp/rmt_app.json"
exec command
