# Intel(R) vPro All-Purpose Utility Container for Linux
THE Intel vPro utility container for Linux OS!  A docker container that can be used for activation of Intel vPro AMT against, Intel EMA, vPro Fleet Services, Device Management ToolKit or standalone for Linux operating systems.

The Intel(R) vPro Fleet Services agent is used to provision Intel(R) AMT (Active Management Technologies, part of Intel(R) vPro) for use with the vPro Fleet Services cloud service.

Create an account at https://vprofleet.intel.com and use this container on your vPro Linux devices today!

NOTE: The process of generating this container will download, install and/or use applications/services from multiple sources.  By using this container, you agree to all licenses, agreements, etc., without limitation, for any of the associated items.

https://github.com/rgl/lms-binaries

https://github.com/device-management-toolkit/rpc-go

## Getting started - Docker install:

The installDocker.sh script is intended to provide a convenient way to install the official Docker packages.

Development and testing has been performed with the official packages from Docker.  It is HIGHLY recommended to use the official packages.  Minimal testing of the non-official packages produced unpredictable results.

NOTE:  Before you can install Docker Engine, you need to uninstall any conflicting packages.

Your Linux distribution may provide unofficial Docker packages, which may conflict with the official packages provided by Docker. You must uninstall these packages before you install the official version of Docker Engine.
See tutorials available here: 

https://docs.docker.com/engine/

## Clone the repo:

```bash
git clone https://github.com/sirfixalotgk/vProFleetAgentServicesDocker
```
## Add/edit required components:

Download the pairing token for the endpoint group that you wish the device to be associated with.  Place the pairing token in the same directory that hosts the local clone of this repo.

NOTE: pairing tokens are unique to your VFS tenant and endpoint group BUT not to any device.  You can use the same pairing token to provision all of your vPro devices!

Setting the hostname and DNS search suffix is largely, personal preference and/or defined by deployment requirements.  The full hostname (FQDN), is often a requirement for AMT activation as well as normal use and as such, proper declaration/definition should be considered a best practice.

Rename the 'rename-to-.env' file to '.env' and edit it to reflect the FQDN and primary DNS suffix that you wish the device to use (per device)
```bash
mv rename-to-.env .env
vi .env
```

## Build the Docker image:

Execute the build.sh script to create the docker image.
```bash
chmod 755 build.sh
./build.sh
```
NOTE: You can use the build.sh script to clean the logs and data folders as well as update the image if you customize the Dockerfile.

## You're ready to activate!
The container can be launched via 'docker compose' or 'docker run'.  
From the local clone directory, execute the 'docker compose' command:
```bash
docker compose up -d
```
If you'd prefer to follow the log while it executes:
```bash
docker compose up
```

Docker run example:
```bash
HOSTNAME=$(grep -v '^#' .env | grep HOSTNAME_OVERRIDE | cut -d '=' -f2 | cut -d "'" -f2) && \
DNS_SUFFIX=$(grep -v '^#' .env | grep DNS_SUFFIX | cut -d '=' -f2 | cut -d "'" -f2) && \
docker run -d -it --name vfs-agent \
    -v ./init.sh:/usr/local/bin/init.sh \
    -v ./PairingToken:/agent/PairingToken \
    -v ./data:/agent/.data \
    -v ./logs:/agent/logs \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    -p 623:623 \
    -p 664:664 \
    -p 16990-16995:16990-16995 \
    --device=/dev/mei0 --privileged \
    --hostname="$HOSTNAME" \
    --dns-search="$DNS_SUFFIX" \
    --cgroupns=host \
    vfs-agent:1.2.6
```
Adjust the values in the .env and the docker-compose.yaml file if you'd prefer some other method to declare the hostname/DNS suffix and you are using "docker compose" to launch.

Adjust the "docker run" parameters to fit your requirements if you'd prefer some other method to declare the hostname/DNS suffix and you are using that method to launch.

The container self-terminates upon completion and success/failure can easily be parsed from the container logs.

_NOTE: This is a privately developed asset and there is no assumption of liability, implied or explicit, with the use of this as a whole or with the use of any of the components.  Neither author, nor any 3rd party assumes any liability for it's use, distribution, etc._
