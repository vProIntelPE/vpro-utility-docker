#!/bin/bash
action=${1:-}
runParam=${2:-}

default() {
    echo -e "Shutting down current container/service if it is running..."
    if [[ -n "$(systemctl status vProHostSvc | grep -o 'Active: active')" ]]; then
        systemctl stop vProHostSvc
        sleep 0.250
    else
        docker compose down -v
        sleep 0.250
    fi
    echo -e "\nService/container stopped...changing symlink to docker-compose.yaml..."
    ln -sf composers/default.yaml docker-compose.yaml
    echo -e "\nService/container stopped...cleaning previous state cache (if it exists)..."
    rm -fR shared/data/*
    rm -fR shared/logs/*
    echo -e "\nDisabling service to enable container config control of restart behavior..."
    systemctl disable vProHostSvc.service 2> /dev/null
    sleep 0.5
    if [[ "$runParam" == "--reset" ]]; then
        if [[ "$(ls -la shared/.UsedToken)" ]]; then
            mv shared/.UsedToken shared/PairingToken
        fi
    fi
    echo -e "\nSleeping for 5 seconds before starting up again..."
    sleep 5
    echo -e "Started the Intel(R) vPro Utility for Linux container!" && docker compose up
}

ema() {
    echo -e "Shutting down current container/service if it is running..."
    if [[ -n "$(systemctl status vProHostSvc | grep -o 'Active: active')" ]]; then
        systemctl stop vProHostSvc
        sleep 0.250
    else
        docker compose down -v
        sleep 0.250
    fi
    echo -e "\nService/container stopped...changing symlink to docker-compose.yaml..."
    ln -sf composers/ema.yaml docker-compose.yaml
    echo -e "\nSleeping for 5 seconds before starting up again..."
    sleep 5
    systemctl restart getty@ttyV0
    systemctl enable --now vProHostSvc
    echo -e "Started the Intel(R) Endpoint Management Assistant vAgent for Linux container!"
    sleep 1 && docker logs -f -n 10 vproutil-ema
}
# Just in case we did something manually before toggling it over
systemctl daemon-reload
# Make sure we are in the correct directory...
cd /opt/vproutil

if [[ "$action" == "--ema" ]]; then
    tput clear
    echo -e "\nLinking the Intel(R) EMA compose file and restarting the container!"
    ema
elif [[ "$action" == "--default" ]]; then
    tput clear
    echo -e "\nLinking the Intel(R) vPro Fleet Services/vPro Utility for Linux compose file and restarting the container!"
    default
else
    tput clear
    echo -e "\n\nYou must specify \"--ema\" -or- \"--default\" as the instance you'd like to toggle to!"
fi
