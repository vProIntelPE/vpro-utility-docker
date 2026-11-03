#!/bin/bash

# Capture the argument(s) in a variable and default to an empty string if there are no args
action=${1:-}
# Set colors
rst='\e[0m'         # Resets to default font color
blu='\e[6;34m'      # Light blue

# Clear the screen so we can see the damage we're doing :)
tput clear

# Stop and disable services
echo -e "${blu}Stopping services..................."
systemctl stop vProHostSvc 2> /dev/null
systemctl stop getty@ttyV0 2> /dev/null
echo "Disabling services.................."
systemctl disable vProHostSvc 2> /dev/null
systemctl disable getty@ttyV0 2> /dev/null

# Cleanup the services
echo "Deleting services..................."
rm -fR /etc/systemd/system/vProHostSvc.service 2> /dev/null
rm -fR /etc/systemd/system/getty@ttyV0.service.d 2> /dev/null

# Reload systemd daemon
systemctl daemon-reload 2> /dev/null

# Cleanup the container and Docker cache
echo "Cleaning up Docker.................."
docker rmi vproutil:1.15.1 -f 2> /dev/null

# Cleanup the storage if argument exists
if [[ "$action" == "--purge" ]]; then
  echo "Deleting data......................."
  docker builder prune -a -f &> /dev/null
  rm -fR /opt/vproutil/storage 2> /dev/null
  echo -e "\nReset including data wipe, complete!${rst}"
else
  echo -e "\nReset complete.....................!${rst}"
fi
