#!/bin/bash

# We need to move files around when we use systemd inside the container
if [[ -z "$(ls -l /run/entry.sh 2> /dev/null)" ]]; then
    echo "Copying files to the run directory..."
    cp -fR /var/dockur/run/. /run/
    echo "Done!"
fi

# We need to export all variable when we nest a shell within a shell
printenv > /envars

# Driver overrides handled in the container rather than requiring additional host modifications
sleep 1
/usr/local/bin/vProUtil.sh start_driver

# Execute the argument passed to the script, intact
exec "$@"
