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
    AMTPASSWORD="P@ssw0rd"
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
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable vProHostSvc.service
}

find_addr() {
    # Use lspci to attempt to locate Intel(R) ME devices in the same IOMMU group - if none
    #   are found, revert to default values (most likely fails with defaults).
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
    # Check for and stop anything using the SoL TTY
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
    echo -e "Driver overrides set"
}

stop_driver() {
    # Remove driver overrides gracefully
    find_addr
    sleep 1
    driverctl unset-override $mePCI
    driverctl unset-override $solPCI
    echo -e "Driver overrides removed" > /dev/console
    /bin/kill -9 $2
    echo -e "Virtual serial lines removed" > /dev/console
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
    echo -e "\n\nWaiting for a few seconds to start LMS...\n\n" > /dev/console
    sleep 5
    systemctl enable --now lms
    echo -e "\n\nLooking for additional actions to perform...\n\n" > /dev/console
    sleep 5
    configure_amt
    sleep 1
    if [[ "$configResult" -eq "true" ]]; then
        echo -e "\n\n\n\n\n\n\n\n\n\n\n\nIntel(R) AMT successfully configured!\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n" > /dev/console
        exit 0
    elif [[ "$configResult" -eq "false" ]]; then
        echo -e "\n\n\n\n\n\n\n\n\n\n\n\nFailed to configure AMT!  Please review logs and correct outstanding issues.\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n" > /dev/console
        exit 1
    fi
}

configure_amt() {
    # First step in configuring AMT for the default version of the utility
    # Check state --> ready --> normal process
    # **********************(beta)*********************************
    # Check state --> already provisioned --> try to adopt into VFS
    amtState="$(rpc amtinfo)"
    preState=$(echo "$amtState" | grep -o -w "pre-provisioning state")
    postState=$(echo "$amtState" | grep -o -w "activated in") 
    readyToken=$(ls -l /shared 2> /dev/null | grep -o -w "PairingToken")
    if [[ -n "$readyToken" && -n "$preState" ]]; then
        # If there is a token and pre-provisioning state, cal standard activation
        vfs_activation
    elif [[ -n "$readyToken" && -n "$postState" ]]; then
        vfsConfigured="$(rpc amtinfo 2> /dev/null | grep -o 'endpointcloudservices.intel.com')"
        if [[ -n "$vfsConfigured" ]]; then
            echo -e "\n\n\nLooks like we are already configured for VFS.\n\n\n" > /dev/console
            return
	fi

	# Assume VFS adoption if we've made it to this point...
        cp /shared/PairingToken /agent 2> /dev/null
        sleep 0.250
        mv /shared/PairingToken /shared/.UsedToken 2> /dev/null
        sleep 0.250
        echo -e "\n\n\nPairingToken found...launching the vPro Fleet Agent...\n\n\n" > /dev/console
        sleep 0.250

	# Begin VFS processes by executing the agent to create an enrollment
	cd /agent
        echo -e "Atttempting to create an endpoint ID...\n\n\n" > /dev/console
        sleep 5 && tail -f /agent/logs/log* | jq . > /dev/console &
        ./IntelvProFleetServicesAgent run --log-level=debug
        echo -e "Waiting 5 seconds before checking endpoint ID...\n\n\n" > /dev/console
        sleep 5
        endpointInfo="$(./IntelvProFleetServicesAgent endpoint-info)"
        endpointID="$(echo "$endpointInfo" | grep -o -E '(\b[a-zA-Z0-9]{8}\b\.\b[a-zA-Z0-9]{8}\b\.\b[a-zA-Z0-9]{16}\b)')"
	sleep 0.250
        if [[ -z "$endpointID" ]]; then
          echo -e "\n\n\n\n\nUnable to create or find an endpoint ID...exiting.\n\n\n\n\n" > /dev/console
          return
        fi
        
	# Evaluate activation state to define VFS profile requirements
	if [[ -n "$(echo "$amtState" | grep -o 'client')" ]]; then
	    profileAttempt=1
	elif [[ -n "$(echo "$amtState" | grep -o 'admin')" ]]; then
            profileAttempt=2
	else
            echo -e "\n\n\n\n\nUnable to determine current activation state.  Exiting...\n\n\n\n\n" > /dev/console
	    return
	fi

	# Trim endpoint ID for tenant and profile ID base, exit if required data is missing
        tenantID="$(echo $endpointID | grep -o -E '(\b[a-zA-Z0-9]{8}\b\.\b[a-zA-Z0-9]{8}\b)')"
        profileID="${tenantID}-${profileAttempt}"
        sleep 0.250
        if [[ -z "$endpointID" || -z "$tenantID" || -z "$profileID" || -z "$AMTPASSWORD" ]]; then
            echo -e "Something went wrong and we didn't get all the info we need...exiting.\n\n" > /dev/console
            return
        fi

        # Begin RPC executions and logging
	echo -e "\n\nAttempting to adopt this endpoint by re-configuring with VFS parameters...\n\n" > /dev/console
       	stampDate=$(date +"%Y-%m-%dUTC%H:%M:%S")
        rpcLog="/agent/logs/rpc-action-${stampDate}.log"
        touch $rpcLog
        sleep 0.500 && tail -F $rpcLog > /dev/console &
        activateRun=1
        mpsWSS="wss://amt.endpointcloudservices.intel.com/activate"
        rpcBaseCmd="rpc activate -u $mpsWSS -profile $profileID -h $endpointID -n -skipamtcertcheck -json"
	while ((activateRun < 5)); do
            if ((activateRun >= 2)); then
                echo -e "\n\nWaiting 15 seconds and then checking activation status...\n\n" > /dev/console
                sleep 15
                echo -e "\n\nChecking firmware activation state...\n\n" > /dev/console
                check_cira
	        sleep 0.500
		logRot=$activateRun - 1
                logBackup="${rpcLog}-${logRot}.log"
                cp $rpcLog $logBackup 2> /dev/null
            fi
	    if [[ -n "$(echo "$ciraHost" | grep -o 'endpointcloudservices.intel.com')" ]]; then
                echo -e "\n\nIntel(R) AMT configured for vPro Fleet Services!\n\n" > /dev/console
                configResult="true"
                break
	    else
                echo -e "Checking number of attempts...\n" > /dev/console
                if ((activateRun == 1)); then
                    rpcCmd="${rpcBaseCmd} -password ${AMTPASSWORD}"
                    echo -e "Attempt: $activateRun \n" > /dev/console
                    rpc_run
                elif ((activateRun == 2)); then
                    rpcCmd="${rpcBaseCmd} -tenant ${tenantID} -password ${AMTPASSWORD}"
                    echo -e "Attempt: $activateRun \n" > /dev/console
                    rpc_run
                elif ((activateRun == 3)); then
                    rpcCmd="${rpcBaseCmd} -tls-tunnel -password ${AMTPASSWORD}"
		    echo -e "Attempt: $activateRun \n" > /dev/console
                    rpc_run
                elif ((activateRun == 4)); then
                    rpcCmd="${rpcBaseCmd} -tenant ${tenantID} -tls-tunnel -password ${AMTPASSWORD}"
		    echo -e "Attempt: $activateRun \n" > /dev/console
                    rpc_run
		elif ((activateRun >= 5)); then
                    echo -e "Attempt: $activateRun \n" > /dev/console
                    echo -e "\n\nToo many failed attempts to activate.  Exiting...\n\n" > /dev/console
                    echo -e "\n\nToo many failed attempts to activate.  Exiting...\n\n" >> $rpcLog
                    configResult="false"
                    break
                fi
            fi
	    ((activateRun++))
        done
        configResult="false"
        return
    fi
    if [[ -z "$readyToken" ]]; then
        echo -e "\n\n\n\n\nNo pending activation actions...servicing Intel(R) LMS only.\n\n\n\n" > /dev/console
        configResult="true"
        return
    fi
    echo -e "\n\n\n\n\nShould not have arrived here, no condition for it. Please confirm all requirements are met.\n\n\n\n" > /dev/console
    configResult="false"
    return
}

rpc_run() {
    echo -e "\n\n\nProfile ID: $profileID\n RPC execution string: $rpcCmd \n\n\n" > /dev/console
    trap '$rpcCmd' EXIT 2>&1 | jq . | tee $rpcLog
}

check_cira() {
    ciraHost="$(rpc amtinfo | grep '^RAS MPS Hostname' | grep -o -E '([a-zA-Z0-9\-]*)\.([a-zA-Z]*)\.([a-zA-Z]*).*')"
    sleep 2
    if [[ -z "$ciraHost" ]]; then
        if [[ -n "$(cat $rpcLog | grep -o 'CIRA Connection:  Configured')" ]]; then
            ciraHost="endpointcloudservices.intel.com"
	    return
	fi
        echo -e "\n\n\nFirmware might still be busy...waiting 15 seconds and checking again...\n\n\n" > /dev/console
        sleep 15
	ciraHost="$(rpc amtinfo | grep '^RAS MPS Hostname' | grep -o -E '([a-zA-Z0-9\-]*)\.([a-zA-Z]*)\.([a-zA-Z]*).*')"
	if [[ -z "$ciraHost" ]]; then
            echo -e "\n\n\n\n\nUnable to get CIRA host from FW; usually indicates some other issue.\n\n\n\n\n" > /dev/console
	    activateRun=5
	fi
    else
        echo -e "\n\n\nCIRA host: $ciraHost\n\n\n" > /dev/console
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
    echo -e "\n\n\n\nGETTY on ttyV0 will restart as soon as the vAgent is online...\n\n\n\n" > /dev/console
    sleep 10
    containerType=$(docker ps --format '{{.Names}}' 2> /dev/null | grep -o "ema")
    while true; do 
        if [[ -z "$containerType" ]]; then
            sleep 1
            containerType=$(docker ps --format '{{.Names}}' 2> /dev/null | grep -o "ema")
        else
            echo -e "\n\n\nLooks like the vAgent is online...waiting a few more seconds before vConsole init...\n\n\n" > /dev/console
            sleep 15
            systemctl restart getty@ttyV0
            break
        fi
    done
}

# SOCAT virtual TTY lines for EMA version:
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
