# Intel(R) vPro All-Purpose Utility Container for Linux
A comprehensive Intel(R) vPro utility for Linux OS that can be used for activation, configuration, etc. as a standalone utility and/or activation against current infrastructure solutions:
 - Intel(R) vPro Fleet Services (VFS)
 - Intel(R) Endpoint Management Assistant (EMA)
 - Device Management ToolKit

CREDITS:

_Intel(R) EMA support capabilities come from a fork of the phenomenal work done in the dockur/windows project:_

https://github.com/dockur/windows


_The following packages/projects provide the foundational elements crucial to all use cases:_

https://github.com/rgl/lms-binaries

https://github.com/device-management-toolkit/rpc-go

NOTE: The process of generating this container will download, install and/or use applications/services from multiple sources.  By using this container, you agree to all licenses, agreements, etc., without limitation, for any of the associated items.

# Not just "quick" but "lightspeed" start..

I'll assume that others share my affinity for "Can I just get this going and then come back to read your dissertation later???"  :)

The answer is...yes, there is a "[Just run this](#hyperdrive-just-run-this)" flow for you.

The links just below this break things out into a "step-by-step" a bit more but the ["Not-so-quick, quick start"](#pre-requisite-docker-install) provides far more information that answer most of the questions that might arise.


### Intel(R) vPro Fleet Services (default config):

### Automatic:

Step 1: [Just run this: clone the repo](#just-run-this-clone-pre-requisite)

Step 2: [Just run this: install Docker](#just-run-this-docker-pre-requisite)

Step 3: [Just run this: Default (auto)](#just-run-this-default-automated)

### Manual:

Step 1: [Just run this: clone the repo](#just-run-this-clone-pre-requisite)

Step 2: [Just run this: install Docker](#just-run-this-docker-pre-requisite)

Step 3: [Just run this: Default (manual)](#just-run-this-default-manual)


### Intel(R) Endpoint Management Assistant (EMA config):

Step 1: [Just run this: clone the repo](#just-run-this-clone-pre-requisite)

Step 2: [Just run this: install Docker](#just-run-this-docker-pre-requisite)

Step 3: [Just run this: EMA](#just-run-this-ema)


### Optional stuff:

[Just run this: pre-built image](#just-download-this-pre-built-image)



## Pre-requisite: Docker install...

Official Docker packages are required and the installDocker.sh script is intended to provide a convenient way to install them.  Minimal testing was done with distro Docker packages but results showed insufficient reliability.

https://docs.docker.com/engine/

_NOTE:  Before you can install the official Docker Engine packages, you need to uninstall any conflicting packages.  The installDocker.sh script mentioned above does NOT remove anything._

## GETTING STARTED
This project represents a convergence of numerous efforts by myself and many others, aligned to a primary objective: simplify maintenance/management/use of Intel(R) AMT (Active Management Technologies, part of Intel(R) vPro) on devices running Linux.  To that end, only one configuration decision must be finalized prior to initial use.

However, the choice is NOT irreversible!

There are two configuration paths:
  - Default: Intel(R) VFS, Device Management ToolKit, standalone 
  - EMA: Intel(R) EMA

The only reason why this choice exists is because Intel(R) EMA support requires things like PCIe pass-through that would otherwise be extraneous.  That said, opting for the "EMA" config for the inaugural execution prepares the endpoint for that type of execution should the need ever arise and, it can be toggled to the default config immediately.

Toggling between the two options as a fundamental capability has been a required objective of this project from its inception.  The ability to flip from one config to another is necessary for activities such as migration.  Here is a hypothetical example of how that might work:

EMA config ---> Managed by Intel(R) EMA ---> Intel(R) VFS is new requirement ---> Intel(R) VFS adopted/configured ---> (hypothetical from here on) PairingToken deployed ---> Toggle to Default config ---> Endpoint migrates  

Click on the appropriate link below:

[Jump to Quick Start: Intel(R) VFS (default)](#quick-start-intelr-vfs)

[Jump to Quick Start: Intel(R) EMA](#quick-start-intelr-ema)

## QUICK START: Intel(R) VFS

The Intel(R) vPro Fleet Services agent is used to provision Intel(R) AMT for use with the vPro Fleet Services cloud service.

Create an account at https://vprofleet.intel.com and use this container on your vPro Linux devices today!

### Step 1: Create the local directory...
_NOTE: This is not an absolute requirement to support the VFS use case however, this is absolute for other use cases.  It should be considered a "best practice" to utilize the default directory shown below._

```bash
mkdir /opt/vproutil
```
### Step 2: Clone the repo...
Cloning this GitHub repo into the folder created in step 1 will provide the folder structure and default config files needed to execute the container.

```bash
cd /opt/vproutil && git clone --filter=blob:none https://github.com/vProIntelPE/vpro-utility-docker .
# OPTIONAL: use the Docker install script to install the official packages if needed
# ./installDocker.sh
```
### Step 3: Add the PairingToken file...

Log into Intel(R) VFS, navigate to endpoint groups, select the radio button of the desired endpoint group and download the PairingToken with the second "Download" button on the right side of the page.  Copy the downloaded PairingToken file to the /opt/vproutil/shared directory.

NOTE: The PairingToken file will be renamed to .UsedToken after the first activation attempt.  If activation fails, you must rollback the name change, returning it to the original value of PairingToken -OR- insert a replacement PairingToken file.

_NOTE: PairingToken files are unique to VFS tenants and endpoint groups BUT not to a single device.  The same PairingToken file may be used on ALL vPro devices that you wish to activate against and become members of the associated endpoint group!_

## Manual or Automated

There are two ways that the install and execution can proceed from this point: via script or via manual execution.  Steps with "Option A)" will indicate the automated process whereas the manual option steps will carry "Option B)" in the label.  Please note that with either option, "docker compose" is used to launch the container.

### Option A), Step 4:
Setting environment variables, building and launching the container is done in a single step with the following command:

```bash
cd /opt/vproutil && ./install.sh
```
The script will attempt to harvest the hostname and DNS suffix (required for ACM activation), and populate those values into the .env file. If it is unable to do so, adjusting to the manual path may be necessary.

The script will create a symbolic link from composers/default.yaml composition file to docker-compose.yaml, build the container and launch it, interactively.  The container restart directive is configured for "unless-stopped" by default.

### Option A), Step 5:
## Done!


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
## Done!



## QUICK START: Intel(R) EMA

There are multiple ways to enable functionality of Linux-based endpoints in Intel(R) Endpoint Management Assistant but regular maintenance can be a bit cumbersome with any of those options.  Simplification as well as reliability are two of the driving factors behind this project and the framework/architecture of this approach seems to meet those objectives.  The Intel(R) EMA option of this utility will create a container that hosts a QEMU VM with a minimized Windows 11 OS.  The Intel(R) Management Engine (ME) hardware is passed to the VM OS which enables the EMA agent access to provision/un-provision/maintain Intel(R) AMT directly from your Intel(R) EMA server(s).

### Things to consider before you proceed:
- _Windows licensing: there is NO Windows license provided with this utility and you MUST maintain licensing compliance per your licensing agreement, whatever that may be_
- _Resource consumption: Running a VM has inherent, host resource consumption considerations that are difficult, if not impossible to predict_
- _Invasive: PCIe passthrough requires changes to the host OS that are usually not experienced with the use of containers_

In general terms, the 2nd and 3rd point above will often require testing to quantify impact/overhead in order to make a suitability determination.  If you are purchasing devices with a Windows license, it is quite possible that the 1st point is moot but that should be verified against any/all agreements you may be subject to. 

_NOTE: The use of "sudo su" is assmumed with each of the steps below but you are welcome to prepend privileged commands with "sudo" in an attempt to achieve the same objective._

### Step 1: Create the local directory...
_NOTE: The path specified below is a hard requirement for Intel(R) EMA support.  This should change in the future as I update the project but at this time, there are a few remaining absolute path instances in a few of the scripts._

```bash
mkdir /opt/vproutil
```
### Step 2: Clone the repo...
Cloning this GitHub repo into the folder created in step 1 will provide the folder structure and default config files needed to execute the container.

```bash
cd /opt/vproutil && git clone --filter=blob:none https://github.com/vProIntelPE/vpro-utility-docker .
# OPTIONAL: use the Docker install script to install the official packages if needed
# ./installDocker.sh
```
### Step 3: Add the EmaAgent files and Windows license...

Log into your Intel(R) EMA web portal, navigate to endpoint groups, select the dropdown of the desired endpoint group and click "Create agent files".  Download both and copy them to the /opt/vproutil/shared directory.

```bash
cp /tmp/EmaAgent.* /opt/vproutil/shared/
# create Windows 11 license key text file - replace with your key
echo "11111-22222-33333-44444-55555" > /opt/vproutil/shared/key.txt
```
### Step 4:
Setting environment variables, building and launching the container is done in a single step with the following command:

```bash
cd /opt/vproutil && ./install.sh --ema
```
The script will attempt to harvest the hostname and DNS suffix (required for ACM activation), and populate those values into the .env file. If it is unable to do so, adjusting to the manual path may be necessary.

The script will create a symbolic link from composers/ema.yaml composition file to docker-compose.yaml, build the container, and create a systemd service named "vProHostSvc"as well as start the service (if a reboot is not required).  The reboot is NOT optional if the script flags it as necessary.

### Step 5:
## Done!



# Hyperdrive: "Just run this..."

## Just run this AIOS: Default (vPro Fleet, ToolKit, standalone, etc.)
```bash
sudo su
mkdir /opt/vproutil
cd /opt/vproutil
git clone --filter=blob:none https://github.com/vProIntelPE/vpro-utility-docker .
cp /tmp/PairingToken /opt/vproutil/shared/
./installDocker.sh
./install.sh --default
```

## Just run this AIOS: EMA
```bash
sudo su
mkdir /opt/vproutil
cd /opt/vproutil
git clone --filter=blob:none https://github.com/vProIntelPE/vpro-utility-docker .
# copy EmaAgent files to install folder
cp /tmp/EmaAgent.* /opt/vproutil/shared/
# create Windows 11 license key text file - replace with your key
echo "11111-22222-33333-44444-55555" > /opt/vproutil/shared/key.txt
./installDocker.sh
./install.sh --ema
```


# Hyperdrive: "Just run this..." (individual steps)

## Just run this: Clone pre-requisite...

```bash
sudo su
mkdir /opt/vproutil
cd /opt/vproutil
git clone --filter=blob:none https://github.com/vProIntelPE/vpro-utility-docker .
# PairingToken/EmaAgent cp/mv command should be added here if developing a deployment script/flow
# Example:
#  cp /tmp/PairingToken /opt/vproutil/shared/ # VFS
#  cp /tmp/EmaAgent.* /opt/vproutil/shared/   # EMA
```

_NOTE: You must copy the PairingToken file to the correct directory at this point in the flow if you intend to provision the endpoint against Intel(R) VFS_

_NOTE: You must copy the EmaAgent.exe and EmaAgent.msh files to the correct directory at this point in the flow if you intend to provision the endpoint against Intel(R) EMA_

## Just run this: Docker pre-requisite...

```bash
./installDocker.sh
```

## Just run this: Default (automated)...

```bash
./install.sh --default
```

## Just run this: Default (manual)...

```bash
mv default-env .env
vi .env
docker build -t vproutil:1.15.1 .
ln -sf composers/default.yaml docker-compose.yaml
docker compose up
```

## Just run this: EMA...

```bash
./install.sh --ema
```

## Just download this: Pre-built image...
```bash
wget -O ./vproutil-1.15.1.tar.gz \
  https://github.com/vProIntelPE/vpro-utility-docker/raw/57013f5585880d5b6fd3316544b8d2ee80da6dda/vproutil-1.15.1.tar.gz
docker load -i vproutil-1.15.1.tar.gz
```

_NOTE: This is a privately developed asset and there is no assumption of liability, implied or explicit, with the use of this as a whole or with the use of any of the components.  Neither author, nor any 3rd party assumes any liability for it's use, distribution, etc._

