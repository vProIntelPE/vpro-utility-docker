#!/bin/bash
# Capture the argument(s) in a variable and default to an empty string if there are no args
action=${1:-}
# Export all the variables that the entry point script captured for us
#      NOTE: This is unusual but must be done due to the multiple layers
#            of nested shells.  Enabling auto-exporting for the session.
#            Auto-export can be disabled again by removing the comment
#            that preceeds the second set command.
set -a
source /envars 2> /dev/null     # silence errors when running installs on host
set +a
#
# Set a default password if none specified
#
if [[ -z "$AMTPASSWORD" ]]; then
    AMTPASSWORD="NotAG00dP@ssw0rd"
fi
#
#
# Function section
vfs_activation() {
    echo -e "\nPurging cache and any old logs..." > /dev/console
    rm -fR /agent/.data/*
    rm -fR /agent/logs/*
    echo -e "\nCopying pairing token to /agent directory and renaming to /shared/.UsedToken..." > /dev/console
    cp /shared/PairingToken /agent/
    sleep .250
    mv /shared/PairingToken /shared/.UsedToken
    sleep 2
    echo -e "\nIntel(R) vPro Fleet Services agent is activating this device." > /dev/console
    echo -e "\n\n\n***** Please leave the device powered on. *****\n\n\n" > /dev/console
    sleep 5 && tail -f /agent/logs/log* | jq . > /dev/console &
    cd /agent && ./IntelvProFleetServicesAgent run --log-level=debug
    echo -e "\n\n\n\n\n" > /dev/console
    if grep -q -m 1 -o "Activation result: Finished successfully" /agent/logs/*; then
        echo -e "Success! This device can now be managed in Intel(R) vPro Fleet Services!\n\n\n" > /dev/console
    else
        echo -e "     **** This device was NOT able to be activated. ****\
          \n**** Please review the logs and resolve activation-blocking issues. ****" > /dev/console
        echo -e "\n\n" > /dev/console
        echo "The most common causes of a failed activation are:" > /dev/console
        echo " - Non-Intel network connection.  This includes:" > /dev/console
        echo "   - Connected to a non-AMT compatible dock" > /dev/console
        echo "   - Active VPN connection" > /dev/console
        echo " - Outbound traffic restrictions.  Such as:" > /dev/console
        echo "   - Proxy configuration required" > /dev/console
        echo "   - Port 4433 or 8443 blocked" > /dev/console
        echo -e "Review the guides in the vPro Fleet Services web portal for additional \
           troubleshooting information.\n\n\n" > /dev/console
    fi
}

install_host() {
    echo -e "Installing a service for the container and a GETTY login process..."
    install_host_svc
    configure_getty
    if [[ -z "$(ls -la | grep -o -w '.rebootRequired')" ]]; then
        echo -e "Done with install...starting things up in 5 seconds..."
        sleep 5
        systemctl start vProHostSvc.service
        echo -e "Done!"
        rm -f ./.rebootRequired
    else
        echo -e "Done installing services..."
    fi
}

configure_getty() {
    # install the basic config for GETTY on the first virtual TTY
    systemctl enable getty@ttyV0
    # SOCAT virtual lines need addtional configuration
    if [[ -z "$(ls -l /etc/systemd/system/getty@ttyV0.service.d/ 2> /dev/null)" ]]; then
         mkdir /etc/systemd/system/getty@ttyV0.service.d
    fi
cat << 'EOF' > /etc/systemd/system/getty@ttyV0.service.d/override.conf
[Unit]
StartLimitBurst=30
StartLimitIntervalSec=90
After=vProHostSvc.service

[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' -L 115200 %I ansi
RestartSec=2
EOF
    systemctl daemon-reload
}

install_host_svc() {
cat << 'EOF' > /etc/systemd/system/vProHostSvc.service
[Unit]
Description=Intel(R) vPro utility service for Linux
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
WorkingDirectory=/opt/vproutil
ExecStartPre=/bin/bash -c "/opt/vproutil/src/vProUtil.sh vconsole &"
ExecStart=/usr/bin/docker compose up
# ExecStop=/bin/bash -c "cp storage/data.qcow2 storage/.data.qcow2"
ExecStop=/usr/bin/docker compose down -v

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable vProHostSvc.service
}

find_addr() {
    # Use lspci to attempt to locate Intel(R) ME devices in the same IOMMU group - if none
    #   are found, revert to default values.
    #
    #   NOTE: falling back to default values is highly unlikely to succeed and is usually
    #   indicative of an underlying compatibility issue.
    #
    export mePCIrt=$(\
      lspci -nnk 2> /dev/null | \
      grep -w -E 'Communication controller \[[0-9]{4}\]\: Intel Corporation' | \
      grep -o -E '^([0-9]{2}\:[1-9]{2}\.[0-9])'\
      )
    export solPCIrt=$(\
      lspci -nnk 2> /dev/null | \
      grep -w -E 'Serial controller \[[0-9]{4}\]\: Intel Corporation' | \
      grep -o -E '^([0-9]{2}\:[1-9]{2}\.[0-9])'\
      )
    lnME=$(wc -l <<< $mePCIrt)
    lnSoL=$(wc -l <<< $solPCIrt)
    if [[ -z "$mePCIrt" || -z "$solPCIrt" ]]; then
        export mePCIrt="00:16.0"
        export solPCIrt="00:16.3"
        echo -e "PCI addresses NOT found...using default values:\nME:  $mePCIrt\nSoL: $solPCIrt\n"
    else
        if [[ $lnME -eq 1 && $lnSoL -eq 1 ]]; then
            echo -e "PCI addresses identified...using discovered values:\nME:  $mePCIrt\nSoL: $solPCIrt\n"
        else
            echo -e "PCI addresses NOT identified...using default values:\nME:  $mePCIrt\nSoL: $solPCIrt\n"
            export mePCIrt="00:16.0"
            export solPCIrt="00:16.3"
        fi
    fi
    mePCI="0000:$mePCIrt"
    solPCI="0000:$solPCIrt"
}

start_driver() {
    # Set driver overrides before appliance start
    # Either host or container may have tried to start a process on the
    #    SoL line - stop GETTY on ttyS4 if it is active
    if [[ "$(systemctl is-active getty@ttyS4)" == "active" ]]; then
        systemctl stop getty@ttyS4
    fi
    # Attempt to find PCI addresses automatically
    find_addr
    sleep 1
    if [[ -z "$(driverctl list-overrides 2> /dev/null)" ]]; then
        driverctl set-override $mePCI  vfio-pci
        driverctl set-override $solPCI vfio-pci
    fi
    echo "Driver overrides set"
}

stop_driver() {
    # Remove driver overrides gracefully
    # Attempt to find addresses automatically
    find_addr
    sleep 1
    driverctl unset-override $mePCI
    driverctl unset-override $solPCI
    echo -e "Driver overrides removed"
    /bin/kill -9 $2
    echo -e "Virtual serial lines removed"
}

start_ema() {
    # Disable the NGINx service because it will be launched via a script
    systemctl disable nginx
    # refresh systemctl to load the unit files copied in via volume mounts
    systemctl daemon-reload
    sleep 1
    # start socat virtual console processes
    systemctl enable --now vProConsole.service
    sleep 1
    # start the QEMU VM appliance
    systemctl enable --now QEMU.service
}

stop_ema() {
    sleep 1
    systemctl stop --force --quiet QEMU.service
    sleep 1
    stop_driver
}

start() {
    # Default (non-Intel EMA) start function 
    echo "Waiting for a few seconds to start LMS..." > /dev/console
    sleep 5
    systemctl enable --now lms
    echo -e "Waiting for a few more seconds and then looking for additional actions to perform..." > /dev/console
    sleep 2
    configure_amt
}

configure_amt() {
    # Enable/disable automatically going any further with the "readyToken" condition below
    #  - /shared/PairingToken hidden/removed: enables a minimal container
    #  - /shared/PairingToken available: normal operations
    #
    # Begin conditional eval and automation
    # Check current provisioning status as our first step
    #  - pre-provisiong state -> send to vfs_activation
    #  - provisioned in ... -> try to adopt if we have or can create an ID (beta)
    preState=$(rpc amtinfo | grep -o -w "pre-provisioning state")
    postState=$(rpc amtinfo | grep -o -w "activated in") 
    readyToken=$(ls -l /shared 2> /dev/null | grep -o -w "PairingToken")
    if [[ -n "$readyToken" && -n "$preState" ]]; then
        # If there is a token and un-provisioned state, send to normal activation
        vfs_activation
    elif [[ -n "$readyToken" && -n "$postState" ]]; then

        vfsConfigured=$(rpc amtinfo 2> /dev/null | grep -o "endpointcloudservices.intel.com")
        if [[ -n "$vfsConfigured" ]]; then
            echo -e "Looks like we are already configured for VFS." > /dev/console
            return
        fi

        # Assume VFS adoption if we've made it to this point...
        cp /shared/PairingToken /agent 2> /dev/null
        sleep 0.250
        mv /shared/PairingToken /shared/.UsedToken 2> /dev/null
        sleep 0.250
        echo "PairingToken found...launching the vPro Fleet Agent..." > /dev/console
        sleep 2

	cd /agent
        endpointID="$(./IntelvProFleetServicesAgent endpoint-info | \
          grep -o -E '(\b[a-zA-Z0-9]{8}\b\.\b[a-zA-Z0-9]{8}\b\.\b[a-zA-Z0-9]{16}\b)')"
        sleep 0.500

        if [[ -z "$endpointID" ]]; then
            # Blank endpoint ID means we need to try to create one
            echo -e "No endpoint ID found...attempting to create one..." > /dev/console
            sleep 5 && tail -f /agent/logs/log* | jq . > /dev/console &
              cd /agent && ./IntelvProFleetServicesAgent run --log-level=debug
            echo -e "Waiting 5 seconds before attempting to determine endpoint ID..." > /dev/console
            sleep 5

            endpointID="$(./IntelvProFleetServicesAgent endpoint-info | \
              grep -o -E '(\b[a-zA-Z0-9]{8}\b\.\b[a-zA-Z0-9]{8}\b\.\b[a-zA-Z0-9]{16}\b)')"
            if [[ -z "$endpointID" ]]; then
                echo -e "Too many failed attempts at determining endpoint ID...exiting!" > /dev/console
                return
            fi
        fi

        profileAttempt=1
        tenantID="$(echo $endpointID | grep -o -E '(\b[a-zA-Z0-9]{8}\b\.\b[a-zA-Z0-9]{8}\b)')"
        profileID="${tenantID}-${profileAttempt}"
        echo -e "Attempting to adopt this endpoint by re-configuring with VFS parameters..." > /dev/console
        sleep 1

        # Just in case anything is blank, abort
        if [[ -z "$endpointID" || -z "$tenantID" || -z "$profileID" || -z "$AMTPASSWORD" ]]; then
            echo -e "Something went wrong and we didn't get all the info we need...exiting." > /dev/console
            return
        fi
        # Start RPC logging...
       	stampDate=$(date +"%Y-%m-%dUTC%H:%M:%S")
        rpcLog="/agent/logs/rpc-action-${stampDate}.log"
        touch $rpcLog
        sleep .5 && tail -F $rpcLog > /dev/console &
        # Call RPC function with the parameters to adopt the endpoint...
        execute_rpc
        sleep 1
        # Check the RPC log to see if the profile ID was correct and run again if it was not
        # Profile determination via looping try -> pass/fail will be replaced in the future
        until [[ $profileAttempt -gt 3 || -z "$(cat ${rpcLog} | grep -o 'Profile not found')" ]]; do
            echo -e "It looks like we might need to try a different profile name..." > /dev/console
            profileID="${tenantID}-${profileAttempt}"
            ((profileAttempt++))
            sleep 1
            execute_rpc
            sleep 1
        done
        return
    fi
    if [[ -z "$readyToken" ]]; then
        echo "No PairingToken found so we'll assume that we are done!" > /dev/console
        return
    fi
    echo -e "Uh, not sure how we got here..." > /dev/console
    return
}

execute_rpc() {
    mpsWSS="wss://amt.endpointcloudservices.intel.com/activate"
    rpcCmd="rpc activate -u $mpsWSS -profile $profileID -tenant $tenantID -h $endpointID -n -v -skipamtcertcheck -json -password $AMTPASSWORD"
    echo -e "Profile ID: $profileID\n RPC execution string: $rpcCmd\n" > /dev/console
    trap '$rpcCmd' EXIT 2>&1 | jq . | tee $rpcLog
    echo -e "Waiting 5 seconds before checking status...\n" > /dev/console
    sleep 5
    rpcInfo="rpc amtinfo"
    trap '$rpcInfo' EXIT 2>&1 | jq . | tee -a $rpcLog
    sleep 2
    if [[ -n "$(cat $rpcLog | grep -o 'does not match list of available AMT profiles')" \
      || -n "$(cat ${rpcLog} | grep -o 'interrupted system call')" ]]; then
        echo -e "Profile not found" > $rpcLog
        echo -e "Trying again..." > /dev/console
    fi
}

stop() {
    sleep 1
    echo "Nothing to see here...move along!"
}

vconsole() {
    # Check symlink compose file to see if we're needed
    if [[ -n "$(ls -l docker-compose.yaml 2> /dev/null | grep -o -w 'default')" ]]; then
        return
    fi
    echo -e "GETTY on ttyV0 will restart as soon as the vAgent is online..."
    sleep 10
    while true; do 
        containerType=$(docker ps --format '{{.Names}}' 2> /dev/null | grep -o -w "ema")
        if [[ "$containerType" == "ema" ]]; then
            echo -e "Looks like the vAgent is online...waiting a few more seconds before vConsole init..."
            sleep 10
            systemctl restart getty@ttyV0
            echo -e "vConsole init, done!"
            sleep 1
            break
        else
            sleep 5
        fi
    done
}

vconsole_hdd() {
    # Check symlink compose file to see if we're needed
    if [[ -n "$(ls -l docker-compose.yaml 2> /dev/null | grep -o -w 'default')" ]]; then
        return
    fi
    # Watch container logs to trigger restoration of previous state
    while true; do
        cReady=$(docker logs -n 10 vproutil-ema 2> /dev/null | grep -o "growable disk image in qcow2 format...")
        if [[ -n "$cReady" ]]; then
            echo -e "Restoring last saved state of vHDD"
            cp storage/.data.qcow2 storage/data.qcow2
            echo -e "Holding until VM reaches ready state before restarting GETTY process"
            sleep 15
            systemctl restart getty@ttyV0
            echo -e "Login daemon on vConsole restarted" 
            break
        else
            # Just in case QEMU used the vHDD as-is, skip to restarting the vConsole login daemon
            pastReady=$(docker logs -n 10 vproutil-ema 2> /dev/null | grep -o "Booting Windows")
            if [[ -n "$pastReady" ]]; then
                echo -e "Holding until VM reaches ready state before restarting GETTY process"
                sleep 15
                systemctl restart getty@ttyV0
                echo -e "Login daemon on vConsole restarted"
                break
            else
                sleep 0.250
            fi
        fi
    done
}

# SOCAT virtual TTY lines
#     ttyV0: host line passed back from container for GETTY binding
#     ttyV1: mirrored to ttyV0, opened and  mirrored to ttyV2
#     ttyV2: presented to VM appliance as COM2
run_serial(){
    socat PTY,raw,echo=0,link=/dev/ttyV0 PTY,raw,echo=0,link=/dev/ttyV1 &
    sleep 1
    # The socat commands below enable the use of TCP vs. serial (default) connection
    socat OPEN:/dev/ttyV1,raw,nonblock PTY,raw,echo=0,link=/dev/ttyV2
    # socat OPEN:/dev/ttyV1,raw,nonblock TCP-LISTEN:4000,reuseaddr
}

# Run the argument that was passed
"$@"
