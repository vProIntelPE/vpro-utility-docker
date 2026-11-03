#########################################################################################
#                                                                                       #
# Intel(R) vPro Utility for Linux                                                       #
#                                                                                       #
# Use this Dockerfile to create a systemd-based container:                              #
#   - Intel(R) vPro Fleet Service vAgent for Linux                                      #
#   - Intel(R) Endpoint Management Assistant vAgent for Linux                           #
#                                                                                       #
# Additional components:                                                                #
#   - Intel(R) vPro Local Manageability Service (LMS)                                   #
#   - Remote Provisioning Client (Device Management Toolkit, RPC-GO)                    #
#     * Supports all RPC activation methods for Intel(R) AMT                            #
#                                                                                       #
#                                                                                       #
# The foundation of this container is a fork of the awesome work in the dockur/windows  #
#   project.  If you've come here as a result of looking for a "Windows in a container" #
#   solution, https://github.com/dockur/windows is probably what you need!              #
#                                                                                       #
# syntax=docker/dockerfile:1.19                                                         #
#                                                                                       #
#########################################################################################

ARG VERSION_ARG="latest"
FROM debian:trixie-slim AS build-amd64

COPY --from=qemux/qemu:7.50 --exclude=usr/bin/qemu-system-x86_64 / /

ARG TARGETARCH

ARG VERSION_WSDD="1.27"
ARG VERSION_VIRTIO="1.9.61"
ARG VERSION_BLINTER="1.0.112"

ARG DEBIAN_FRONTEND="noninteractive"
# Dependencies fail to install without version definition
ARG VERSION_SYSTEMD="257.13-1~deb13u1"

RUN <<EOF
  set -eu

  apt-get update
  apt-get --no-install-recommends --allow-downgrades -y install \
    jq \
    vim \
    gcab \
    wget \
    curl \
    dbus \
    kmod \
    udev=${VERSION_SYSTEMD} \
    libudev1=${VERSION_SYSTEMD} \
    samba \
    socat \
    mtools \
    libsystemd0=${VERSION_SYSTEMD} \
    libsystemd-shared=${VERSION_SYSTEMD} \
    systemd=${VERSION_SYSTEMD} \
    iproute2 \
    pciutils \
    wimtools \
    dos2unix \
    net-tools \
    driverctl \
    cabextract \
    xmlstarlet \
    libace-8.0.2 \
    icu-devtools \
    iputils-ping \
    systemd-sysv=${VERSION_SYSTEMD} \
    libxml2-utils \
    libxerces-c3.2 \
    ca-certificates \
    libarchive-tools \
    libxerces-c3.2t64
  #
  # Install Intel(R) Local Manageability Service (LMS)
  #
  wget -O /tmp/lms.deb \
    https://github.com/rgl/lms-binaries/releases/download/v0.0.20260715/lms-2625.0.0-debian-13.deb && \
    apt-get install -y /tmp/lms.deb
  #
  # Download and extract the Intel(R) vPro Fleet Services agent
  #
  # Install is executed via the vProUtil.sh script when the container starts when using the VFS agent
  #
  wget -O /tmp/agent.tar.gz \
    https://downloadmirror.intel.com/923996/IntelvProFleetServicesAgent-1.2.5-linux-x64.tar.gz && \
    mkdir /agent && tar -zxvf /tmp/agent.tar.gz -C /agent && chmod 755 /agent/IntelvProFleetServicesAgent
  #
  # Download and extract the remote provisioning client (RPC) from Device Management ToolKit repository
  #
  wget -O /tmp/rpc.tar.gz \
    https://github.com/device-management-toolkit/rpc-go/releases/download/v2.52.7/rpc_linux_x64.tar.gz && \
    tar -zxvf /tmp/rpc.tar.gz -C /usr/local/bin && chmod 755 /usr/local/bin/rpc_linux_x64 && \
    ln -s /usr/local/bin/rpc_linux_x64 /usr/local/bin/rpc
  #
  # Remove temp and unnecessary systemd target items that conflict with containers
  #
  rm -f /lib/systemd/system/multi-user.target.wants/* \
    /etc/systemd/system/*.wants/* \
    /lib/systemd/system/local-fs.target.wants/* \
    /lib/systemd/system/sockets.target.wants/*udev* \
    /lib/systemd/system/sockets.target.wants/*initctl* \
    /lib/systemd/system/basic.target.wants/* \
    /lib/systemd/system/anaconda.target.wants/* \
    /usr/lib/systemd/system/systemd-backlight\@.service \
    /tmp/*
  #
  # Blinter and WSDDN are requirements from the original Dockur Windows project
  #
  # Install Blinter
  #
  python3 -m pip install --break-system-packages --root-user-action=ignore --no-cache-dir "Blinter==${VERSION_BLINTER}"
  #
  # Install wsddn package
  #
  wget -O /tmp/wsddn.deb -q --timeout=10 \
    "https://github.com/gershnik/wsdd-native/releases/download/v${VERSION_WSDD}/wsddn_${VERSION_WSDD}_${TARGETARCH}.deb"
  dpkg -i /tmp/wsddn.deb
  #
  # Final cleanup after the last packages installed
  #
  apt-get clean
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
  mkdir /var/dockur
  #
  # Most service hosting requirements moved from the host OS
  #   to the container but the host must continue to serve a
  #   getty instance to enable the virtual console.
  #
  # Create virtual console ports with socat
  #
  cat << 'EOS' > /etc/systemd/system/vProConsole.service
  [Unit]
  Description=Virtual serial console for the Intel(R) vPro utility for Linux
  After=network.target
  StartLimitBurst=10
  StartLimitIntervalSec=15

  [Service]
  Type=simple
  User=root
  ExecStart=/bin/bash /usr/local/bin/vProUtil.sh run_serial &
  ExecStop=/bin/bash /usr/local/bin/vProUtil.sh stop_driver $MAINPID
  Restart=always
  RestartSec=1

  [Install]
  WantedBy=multi-user.target
EOS
EOF
#
# Copy and change permissions on numerous files
#
# Pull scripts and unattended install definitions directly from source
COPY --from=dockurr/windows:6.05 --chmod=755 /run /var/dockur/run
COPY --chmod=755 ./src/vProUtil.sh /usr/local/bin/
COPY --chmod=755 ./src/DefaultEntryPoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=644 ./src/DefaultInit.service /etc/systemd/system/MainInit.service
COPY --chmod=644 ./src/QEMU.service /etc/systemd/system/
COPY --from=qemux/udfread:1.2.0 /udfread /usr/bin/
COPY --from=qemux/qemu-helios:1.0.0 /usr/bin/qemu-system-x86_64 /usr/bin/
#
# Add Virtio drivers for install in the virtual appliance 
#
ADD --chmod=664 \
  https://github.com/qemus/virtiso-whql/releases/download/v${VERSION_VIRTIO}-0/virtio-win-${VERSION_VIRTIO}.tar.xz \
  /var/drivers.txz
#
# Declare versions for container and virtual appliance
#
FROM build-${TARGETARCH}
ARG VERSION_ARG="6.05"
RUN echo "$VERSION_ARG" > /etc/version
#
# ENV parameters must be set here for reliable image building and container operation.
#
# A note of recognition:
#    There are numerous scripts that the original project uses to launch an elegantly configured
#    QEMU VM. These environment variables set the parameter values used throughout those scripts,
#    numerous times.  The absolute minimum parameter customization has been made and it is intended
#    to enable the support of a smaller vHDD.
#
#    The "Windows in a Container" project is truly impressive and even more so when you "look under
#    the covers".  This intends to expand capabilities by adjusting to a SYSTEMD based container.
#    This approach preserves the host OS by moving the invasive changes/processes such as driver 
#    overrides, to the container.
#   
#
#    Check out the source project at: https://github.com/dockur/windows
#
EXPOSE 8006
EXPOSE 16990-16995
VOLUME /storage
ENV VERSION="core11"
ENV RAM_SIZE="4G"
ENV CPU_CORES="2"
ENV DISK_SIZE="16G"
#
# Configure services:
#  - enable primary initialization process
#  - disable NGINx as alternative methods are used to launch it
#
RUN systemctl enable MainInit.service
RUN systemctl disable nginx
#
# Final step, declare entrypoint and initialization command
#
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/lib/systemd/systemd"]

