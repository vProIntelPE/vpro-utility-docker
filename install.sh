#!/bin/bash

# Capture the argument(s) in a variable and default to an empty string if there are no args
action=${1:-}
installType=${2:-}

# version
softVer="1.15.1"

# Set the font color shortcuts
rst='\e[0m'    # Clear color (reset to default)
blk='\e[30m'   # Black
red='\e[31m'   # Red
grn='\e[32m'   # Green
yel='\e[33m'   # Yellow
blu='\e[1;34m' # Light Blue
dbl='\e[34m'   # Blue
mag='\e[35m'   # Magenta
cya='\e[36m'   # Cyan
gry='\e[37m'   # Light Gray
wht='\e[97m'   # white

# Set the install type default value if not specified
if [[ -z "$installType" ]]; then
    installType="--default"
fi

# Create a banner at the top of the screen
draw_header() {
    tput civis
    trap "tput cnorm; echo" EXIT
    tput sc
    tput cup 0 0
    echo -e "\e[44m\e[97m=====================================================================================================\e[0m"
    echo -e "\e[44m\e[97m$sysMessOne\e[0m"
    echo -e "\e[44m\e[97m$sysMessTwo\e[0m"
    echo -e "\e[44m\e[97m=====================================================================================================\e[0m"
}

# Installation functions
#
install() {
    # Display a notification about system changes before calling the functions
    #
    clear
    if [[ "$installType" == "--ema" ]]; then
        echo -e "${grn}Welcome to the Intel(R) vPro utility for Linux - Intel(R) Endpoint Management Assistant version!\n"
        echo -e "${wht}The system may need configuration changes in order to support the Intel(R) EMA vAgent\nand some of these changes may require a reboot.\n"
    else
        echo -e "${grn}Welcome to the Intel(R) vPro utility for Linux!\n"
        echo -e "${wht}\n\nNOTE: Execute this script with \"--ema\" if Intel(R) Endpoint Management Assistant support is required now or in the future.\nPress CTRL-C to halt here and start again...(resuming in 3 seconds)"
        sleep 3
        check_boot
    fi
    # echo -e "${wht}The system may need configuration changes in order to support the Intel(R) EMA vAgent\nand some of these changes may require a reboot.\n"
    sleep 3
    check_lms
    sleep 3
    # check_boot
    # sleep 3
    check_wdir
    sleep 3
    check_env
    sleep 3
    build_container
    if [[ "$installType" == "--ema" ]]; then
        conType="vproutil-ema"
        if [[ -n "$(ls -l | grep -o -w 'docker-compose.yaml')" ]]; then
            mv docker-compose.yaml unknown-dock-comp.yaml
        fi
        ln -sf composers/ema.yaml docker-compose.yaml 
        sleep 3
        download_core11
        sleep 3
        clear
        install_services
        mkdir storage 2> /dev/null
        truncate -s 16G storage/data.img 2> /dev/null
        if [[ "$rebootRequired" == "true" ]]; then
            echo -e "${yel}\n**** The system must be rebooted before the Intel(R) EMA vAgent can be used! ****${rst}"
            echo -e "${cya}\nAll script actions completed!  Intel(R) EMA vAgent is set to start automatically.${rst}"
            exit 0
        else
            sleep 3
            follow_start
        fi
    else
        conType="vproutil-default"
        if [[ -n "$(ls -l | grep -o -w 'docker-compose.yaml')" ]]; then
            mv docker-compose.yaml unknown-dock-comp.yaml
        fi
        ln -sf composers/default.yaml docker-compose.yaml
    fi
}

check_lms() {
    # Check to make sure the LMS service is not running on the host
    #
    sysMessOne="=     Checking to see if the current configuration of this endpoint meets the pre-requisites...     ="
    sysMessTwo="=                      Checking for Intel(R) Local Manageability Service...                         ="
    draw_header
    tput cup 4 0
    tput ed
    lmsActive=$(ps -ef | grep -c -o "^lms")
    if [ $lmsActive != 0 ]; then
        echo -e "${yel}The Intel(R) Local Manageability Service (LMS) appears to  be active!\n${mag}Please stop and disable LMS before installing the EMA vAgent for Linux.${rst}"
        exit 0
    fi
    echo -e "${grn}\nIntel(R) LMS does not appear to be running but if it is installed on this device, please remove/disable prior to using the Intel(R) EMA vAgent.\n\nProceeding with install/configuration...\n${rst}"
}

check_boot() {
    # Check kernel command line parameter - iommu must be enabled for proper functionality
    #
    sysMessOne="=     Checking to see if the current configuration of this endpoint meets the pre-requisites...     ="
    sysMessTwo="=                              Checking kernel CMDLINE parameters...                                ="
    draw_header
    tput cup 4 0
    tput ed
    if [ $(cat /etc/default/grub | grep "^GRUB_CMDLINE_LINUX" | grep -w "iommu=pt" | grep -c -w "intel_iommu=on") = 0 ]; then
        echo -e "${yel}\n\nKernel parameters must be updated: ${wht}A REBOOT WILL BE REQUIRED${rst}"
        rebootRequired="true"
        touch ./.rebootRequired
        sed -i.bak \
          -e 's/\(^GRUB_CMDLINE_LINUX_DEFAULT=".*\)"/\1 iommu=pt intel_iommu=on"/' \
          -e 's/\(^GRUB_CMDLINE_LINUX=".*\)"/\1 iommu=pt intel_iommu=on"/' \
          /etc/default/grub
        echo -e "\nThe GRUB configuration file at /etc/default/grub has been updated...executing update-grub now..."
        sleep 1
        update-grub
        echo -e "${grn}\nCompleted GRUB changes.\n"
    else
        echo -e "${grn}No modifications needed...nice!"
    fi
}

check_wdir() {
    # Some paths had to remain absolute...for now.
    #
    sysMessTwo="=                              Checking container working directory...                              ="
    draw_header
    tput cup 4 0
    tput ed
    if [[ "$(pwd)" != "/opt/vproutil" ]]; then
        echo -e "${yel}We are not executing from the correct path...we'll need to create the directory and move everything to that location."
        if [[ -z "$(ls -la /opt/vproutil 2> /dev/null)" ]]; then
            echo -e "${cya} Creating /opt/vproutil"
        else
            echo -e "${yel}It looks like there is a directory there...we'll create a backup and make a new directory..."
            mv /opt/vproutil /opt/vproutil-bak
        fi
        mkdir -p /opt/vproutil
        sleep 0.5
        cp -a $(pwd)/. /opt/vproutil/
    else
        echo -e "${grn}Nice...looks like we are executing from the correct location.\n"
    fi
}

check_env() {
    # Check and update the environment file
    #
    sysMessTwo="=                              Checking container environment file...                               ="
    draw_header
    tput cup 8 0
    tput ed
    # Check the .env file and update if the min required values are missing
    if [[ -z "$(cat .env 2> /dev/null | grep -w "^HOSTNAME" 2> /dev/null)" ]]; then
        echo -e "${cya}Performing some discovery and updating environment file...${rst}"
        envTemp=$(<default-env)
        source src/vProUtil.sh find_addr
        echo "HOSTNAME=\"$(hostname)\"" > .env
        if [[ -n "$(hostname -d)" ]]; then
            echo "DNS_SUFFIX=\"$(hostname -d)\"" >> .env
        else
            suffixValue="$(awk '{print $3}' <<< "$(resolvectl status 2> /dev/null | grep -w "DNS Domain" 2> /dev/null)")"
            if [[ -n "$suffixValue" ]]; then
                echo "DNS_SUFFIX=\"$suffixValue\"" >> .env
            else
                suffixValue=$(awk '{print $2}' <<< "$(cat /etc/resolv.conf 2> /dev/null | grep -w "^search" 2> /dev/null)")
                if [[ -n "$suffixValue" ]]; then
                    echo "DNS_SUFFIX=\"$suffixValue\"" >> .env
                else
                    echo -e "${yel}No DNS suffix found.  The default value will need to edited in the .env file.${rst}"
                    suffixValue="notarealdnssuffix.nowhere"
                    echo "DNS_SUFFIX=\"$suffixValue\"" >> .env
                fi
            fi
        fi
        if [[ -z "$mePCIrt" || -z "$solPCIrt" ]]; then
            echo -e "${yel}No ME or SoL PCI addresses found.  The default values will need to edited in the .env file.${rst}"
            echo "MEADDR=\"00:16.0\"" >> .env
            echo "SOLADDR=\"00:16.3\"" >> .env
        else
            echo "MEADDR=\"$mePCIrt\"" >> .env
            echo "SOLADDR=\"$solPCIrt\"" >> .env
        fi
        echo "$envTemp" >> .env
    else
        echo -e "${grn}Looks like the environment file has been already been updated!${rst}"
    fi
}

license_warn() {
   # Notify user that there is not license nor assumption of licensing responsibility
   #
   echo -e "${yel}********  NOTE: YOU MUST ENSURE WINDOWS LICENSING COMPLIANCE  ********"  
   echo -e "${cya}Press CTRL + C within 3 seconds if you wish to abort this installation...\n\n${rst}"
   sleep 3
}

download_core11() {
    # Check for existence of the OS install media and download if necessary
    #
    sysMessTwo="=                          Checking Windows 11 Tiny Core OS install...                              ="
    draw_header
    tput cup 4 0
    tput ed
    if [[ -z "$(ls -l iso/ | grep core11.iso)" ]]; then
        echo -e "${blu}Downloading the Tiny Core 11 modified version of Windows 11 25H2..."
        license_warn
        wget -O ./iso/core11.iso \
          https://archive.org/download/tiny11_25H2/tiny11core_25H2_Nov25.iso
        echo -e "${grn}Core 11 modified version of Windows 11 25H2 has been saved locally..."
    else
        echo -e "${grn}Looks like Tiny Core 11 modified version of Windows 11 25H2 has already been downloaded..."
        license_warn
    fi
}

build_container() {
    # Build the utility container
    #
    sysMessTwo="=                                      Building the container...                                    ="
    draw_header
    tput cup 4 0
    tput ed
    docker build -t vproutil:${softVer} .
    echo -e "${grn}Done!\n"
}

install_services() {
    # Install a service for getty binding to the virtual serial console and container control
    #
    sysMessTwo="=            Installing services for a getty process and to launch the container...                 ="
    draw_header
    tput cup 4 0
    tput ed
    src/vProUtil.sh install_host &> /dev/null
    echo -e "${grn}Done!\n"
}

follow_start() {
    # Follow the service log because the first launch of the service completes some setup tasks
    sysMessOne="=           Following the container to ensure the remaining setup completes successfully            ="
    sysMessTwo="=            Press CTRL+C and use \"systemctl restart vProHostSvc\" to restart the utility            ="
    draw_header
    tput cup 4 0
    tput ed
    SCREENS=1
    COUNT=4
    BREAKCOUNT=1
    outScreenPrevious="Nothing to see here..."
    while true; do
        if [[ $COUNT == 32 ]]; then
            COUNT=4
            ((SCREENS++))
        fi
        outScreen=$(docker container logs -n 1 ${conType})
        # outScreen=$(journalctl -n 1 --no-pager -u vProHostSvc)
        if [[ "$outScreen" != "$outScreenPrevious" ]]; then
            tput cup ${COUNT} 0; tput ed; echo "$outScreen"
            ((COUNT++))
            BREAKCOUNT=1
        fi
        outScreenPrevious="$outScreen"
        ((BREAKCOUNT++))
        sleep 0.1
        if (( BREAKCOUNT >= 1200 || SCREENS >= 6 )); then
            ((COUNT+5))
            tput cup ${COUNT} 0; tput ed; tput sc; tput rc
            echo -e "${wht}Enjoy!${rst}"
            tput cnorm
            break
        fi
    done
    tput cup ${COUNT} 0; tput ed; tput sc; tput rc
    echo -e "${wht}Enjoy!${rst}"
    tput cnorm
}
         
# Main execution function
#
# Evaluate arguments passed to the script at launch
if [[ "$action" == "--ema" || "$action" == "--default" ]]; then
    installType="$action"
    action="install"
    install
    exit 0
elif [[ -z "$action" ]]; then
    install
    exit 0
else
    echo -e "${yel}Not sure how we got here but try again using one of these formats:\n  ${cya}./install.sh --ema (For the Intel(R) EMA vAgent\n  ${cya}./install.sh (standard install for VFS, Toolkit, utility functions, etc.)\n  ** --default can be used with the above **${rst}"
    # "$@"
fi
exit 0

