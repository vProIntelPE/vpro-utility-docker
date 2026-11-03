#!/bin/bash

# We need to export all variable when we nest a shell within a shell
printenv > /envars

# Execute the argument passed to the script, intact
exec "$@"
