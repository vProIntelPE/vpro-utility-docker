# Intel(R) vPro All-Purpose Utility Container for Linux
A comprehensive Intel(R) vPro utility for Linux OS that can be used for activation, configuration, etc. as a standalone utility and/or activation against current infrastructure solutions:
 - Intel(R) vPro Fleet Services
 - Intel(R) Endpoint Management Assistant
 - Device Management ToolKit

CREDIT: Intel(R) EMA support capabilities fork from the phenomenal work done in the dockur/windows project:
https://github.com/dockur/windows

CREDIT: The following packages/projects provide the foundational elements crucial to all use cases:
https://github.com/rgl/lms-binaries

https://github.com/device-management-toolkit/rpc-go

NOTE: The process of generating this container will download, install and/or use applications/services from multiple sources.  By using this container, you agree to all licenses, agreements, etc., without limitation, for any of the associated items.

## QUICK START: Intel(R) vPro Fleet Service (VFS)

The Intel(R) vPro Fleet Services agent is used to provision Intel(R) AMT (Active Management Technologies, part of Intel(R) vPro) for use with the vPro Fleet Services cloud service.

Create an account at https://vprofleet.intel.com and use this container on your vPro Linux devices today!


### Step 1: Docker install...

Official Docker packages are required and the installDocker.sh script is intended to provide a convenient way to install them.  Minimal testing was done with distro Docker packages but results showed insufficient reliability.

https://docs.docker.com/engine/

NOTE:  Before you can install the official Docker Engine packages, you need to uninstall any conflicting packages.  The installDocker.sh script mentioned above does NOT remove anything.

### Step 1a: Create the local directory...
This is not an absolute requirement to support the VFS use case however, this is absolute for other use cases.  It should be considered a "best practice" to utilize the default directory shown below.

```bash
mkdir /opt/vproutil
```
### Step 2: Clone the repo...
Cloning this GitHub repo into the folder created in step 1a will provide the folder structure and default config files needed to execute the container.

```bash
cd /opt/vproutil && git clone https://github.com/vProIntelPE/vpro-utility-docker .
```
### Step 3: Add the PairingToken file...

Log into Intel(R) VFS, navigate to endpoint groups, select the radio button of the desired endpoint group and download the PairingToken with the second "Download" button on the right side of the page.  Copy the downloaded PairingToken file to the /opt/vproutil/shared directory.

NOTE: pairing tokens are unique to your VFS tenant and endpoint group BUT not to any device.  You can use the same pairing token to provision all of your vPro devices!

## Manual or Automated

There are two ways that the install and execution can proceed from here: via script or via manual execution.  Steps with "Option A)" will indicate the automated process whereas the manual option steps will carry "Option B)" in the lable.  Please note that with either option, "docker compose" is used to launch the container.

### Option A), Step 4:
Setting environment variables, building and launching the container can be accomplished in a single step with the following command:

```bash
cd /opt/vproutil && ./install.sh
```
The script will attempt to harvest the hostname and DNS suffix (required for ACM activation), and populate those values in to the .env file. If it is unable to do so, adjusting to the manual path may be necessary.

The script will create a symbolic link to the composers/default.yaml composition file, build the container and then launch it.  The container restart directive is configured for "unless stopped" by default.

### Option A), Step 5:
Done!

### Option B), Step 4:
Rename the 'rename-to-.env' file to '.env' and edit it to reflect the FQDN and primary DNS suffix that you wish the device to use (per device)

```bash
cd /opt/vproutil && mv default-env .env
vi .env
```
Setting the hostname and DNS search suffix is largely, personal preference and/or defined by deployment requirements.  The full hostname (FQDN), is often a requirement for AMT activation as well as normal use and as such, proper declaration/definition should be considered a best practice.


### Option B), Step 5:
Execute the following command to create the docker image and link the composition file:
```bash
cd /opt/vproutil && ./install.sh build_container
ln -sf composers/default.yaml docker-compose.yaml
```
NOTE: Alternatively, a pre-built image can be downloaded here:
https://github.com/vProIntelPE/vpro-utility-docker/raw/57013f5585880d5b6fd3316544b8d2ee80da6dda/vproutil-1.15.1.tar.gz

```bash
cd /opt/vproutil
wget -O ./vproutil-1.15.1.tar.gz \
  https://github.com/vProIntelPE/vpro-utility-docker/raw/57013f5585880d5b6fd3316544b8d2ee80da6dda/vproutil-1.15.1.tar.gz
docker load -i vproutil-1.15.1.tar.gz
ln -sf composers/default.yaml docker-compose.yaml
```

### Option B), Step 6:
Use the following docker compose command to execute the container:

```bash
cd /opt/vproutil && docker compose up
```
NOTE: It is recommended that the container run in "attached" (interactive) mode the first time (while in PoC).  Appending "-d" to the command above will silence output and run the container in "detached" mode.

### Option B), Step 7:
Done!

_NOTE: This is a privately developed asset and there is no assumption of liability, implied or explicit, with the use of this as a whole or with the use of any of the components.  Neither author, nor any 3rd party assumes any liability for it's use, distribution, etc._

