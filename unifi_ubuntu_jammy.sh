#!/usr/bin bash

# Install and setup UniFi Controller Software v8.x on Ubuntu 22.04 aka Jammy
#
# * Download Ubuntu 22.04 - https://releases.ubuntu.com/jammy/
#
# * Updating and Installing Self-Hosted UniFi Network Servers (Linux) - https://help.ui.com/hc/en-us/articles/220066768
# * Self-Hosting a UniFi Network Server - https://help.ui.com/hc/en-us/articles/360012282453
# * UniFi - Repairing Database Issues on the UniFi Network Application - https://help.ui.com/hc/en-us/articles/360006634094
# * UISP Installation Guide - https://help.ui.com/hc/en-us/articles/115012196527-UNMS-Installation-Guide
# * Software Releases - https://community.ui.com/releases

# LXD
#
# lxc init -p default -p br0 images:ubuntu/22.04 unifi-controller
# lxc init -p default images:ubuntu/22.04 unifi-controller
# lxc config set unifi-controller limits.cpu=2
# lxc config set unifi-controller limits.memory.enforce=hard limits.memory=2048MB
# lxc config device override unifi-controller root size=20GB
# lxc config set unifi-controller boot.autostart=1 boot.autostart.delay=0 boot.host_shutdown_timeout=30
# lxc config show unifi-controller --expanded
# lxc start unifi-controller
# lxc exec unifi-controller /bin/bash

# Docker
#
# https://docs.linuxserver.io/images/docker-unifi-network-application/
# https://github.com/GiuseppeGalilei/Ubiquiti-Tips-and-Tricks
# https://forums.unraid.net/topic/147455-support-unifi-controller-unifi-unraid-reborn/

_DEBUG="off"
function DEBUG()
{
  [ ${_DEBUG} == "on" ] && "${@}"
};
DEBUG set -e

# Check if this script was run as a non-root user
function is_root()
{
  if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
  fi
};
is_root

# Check if this script is being run on Ubuntu
function is_ubuntu()
{
  local distro
  distro=$(awk '/^ID=/' /etc/*-release | tr -d '"' | awk -F'=' '{ print tolower($2) }')
  
  case "${distro}" in
    ubuntu) echo 'This is Ubuntu Linux' ;;
         *) echo 'This is not Ubuntu Linux.'; exit 1 ;; 
  esac
};
is_ubuntu

mkdir -p /etc/apt/{apt.conf.d,trusted.gpg.d,sources.list.d}

# Disable phased updates found in Ubuntu 21.10 and newer
cat <<'EOF' | tee /etc/apt/apt.conf.d/99custom-disable-phased-updates
// To have all your machines phase the same, set the same string in this field
// If commented out, apt will use /etc/machine-id to seed the random number generator
APT::Machine-ID "aaaabbbbccccddddeeeeffff";

// Always include phased updates.
// For example, after your initial build, you would comment this out.
// If left in place you will *always* include phased updates instead of phasing all machines together.
Update-Manager::Always-Include-Phased-Updates;
APT::Get::Always-Include-Phased-Updates: True;

EOF

# Disable apt install of recommended software
cat <<'EOF' | tee /etc/apt/apt.conf.d/99custom-no-install-recommends
// Disable the automatic install of recommended packages.
APT::Install-Recommends "false";

// Disable the install of suggested packages
//APT::Install-Suggests "false";

EOF

# Disable apt advertisements
command -v pro >/dev/null 2>&1 \
  && pro config set apt_news=false
  
# Disable motd advertisements on login
test -f /etc/default/motd-news \
  && sed -i -e 's/ENABLED=1/ENABLED=0/g' /etc/default/motd-news

# Disable needrestart found in 22.04 and newer as it 
# causes issues for scripts and automation solutions.
test -f /etc/needrestart/needrestart.conf \
  && sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf

# Enable universe repoistory
command -v apt-add-repository >/dev/null 2>&1 && apt-add-repository universe

# Enable multiverse repository
#command -v apt-add-repository >/dev/null 2>&1 && apt-add-repositor multiverse

# Enable restricted repository
#command -v apt-add-repository >/dev/null 2>&1 && apt-add-repositor restricted

# Perform a upgrade and refresh of existing installed packages
apt-get update -y \
  && apt-get -o APT::Get::Always-Include-Phased-Updates=true upgrade -y
  
command -v snap >/dev/null 2>&1 \
  && snap refresh

# Install the following packages
apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y binutils \
  coreutils \
  curl \
  wget \
  lsb-release \
  ca-certificates \
  apt-transport-https \
  software-properties-common \
  gnupg \
  tzdata

### Optional packages
#apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y haveged

apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y \
  vim-tiny \
  net-tools \
  dnsutils \
  mtr-tiny

### Optional, install openSSH Server
#apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y openssh-server

### Optional, install UFW
#apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y ufw

# If UFW installed, create applicate profile for the unifi controller service
test -d /etc/ufw/applications.d \
  && cat << 'EOF' | tee /etc/ufw/applications.d/unifi-controller
[unifi-controller]
title=UniFi Controller Software
description=UniFi Controller Software
ports=22/tcp|80/tcp|443/tcp|8080/tcp|8443/tcp|3478/udp|5514/udp|6789/tcp|10001/udp|1900/udp|5656:5699/tcp
EOF

if command -v ufw >/dev/null 2>&1; then

  test -f /etc/ufw/applications.d/unifi-controller && ufw allow unifi-controller
  
  # Allow SSH
  #ufw allow 22/tcp comment "Allow ssh, tcp port 22"
  #ufw limit 22/tcp
  
  # Configure default policy for UFW
  ufw default allow outgoing
  ufw default deny incoming
  
  # Configure UFW for minimal logging
  ufw logging on low
  
  # Enable UFW
  ufw enable
  #ufw status
  
fi;

### Set timezone for UTC
timedatectl set-timezone UTC

### OpenJDK

## UniFi Network Application 7.5.174 requires Java 17
## Alternative: https://adoptium.net/en-GB/temurin/releases/?version=17
apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y openjdk-17-jre-headless
#apt-mark hold openjdk-17-*

## OpenJDK 11
#apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y openjdk-11-jre-headless
#apt-mark hold openjdk-11-*

# Set the JAVA_HOME environment variable for the UniFi service
#mkdir -p /etc/systemd/system/unifi.service.d

#printf "[Service]\nEnvironment=\"JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64\"\n" \
#  | tee /etc/systemd/system/unifi.service.d/10-override.conf > /dev/null

#systemctl daemon-reload

# This is a workaround for OpenJDK 11 issues as the jsvc 
# expects to find libjvm.so at lib/amd64/server/libjvm.so
#ln -s /usr/lib/jvm/java-11-openjdk-amd64/lib/ /usr/lib/jvm/java-11-openjdk-amd64/lib/amd64

## OpenJDK 8
#apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y openjdk-8-jre-headless
#apt-mark hold openjdk-8-*

### UniFi Controller Software
# https://community.ui.com/releases
# https://dl.ui.com/unifi/7.5.174/unifi_sysvinit_all.deb
# https://dl.ui.com/unifi/7.5.174/UniFi.unix.zip
# https://dl.ui.com/unifi/7.5.174/unifi_sh_api

# Add the UniFi Stable repo to the host
wget -qO- https://dl.ui.com/unifi/unifi-repo.gpg \
  | tee /etc/apt/trusted.gpg.d/unifi-repo.gpg > /dev/null

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/unifi-repo.gpg] \
https://www.ui.com/downloads/unifi/debian stable ubiquiti" \
  | tee /etc/apt/sources.list.d/ubnt-unifi-stable.list > /dev/null


### MongoDB
# UniFi Network Application 7.5.174 requires MongoDB 3.6 or newer.
# UniFi 7.5.X will require 3.6.0 up to (excluding) 5.0.0, so in total: 3.6, 4.0, 4.2 and 4.4 (max).
# UniFi 7.4.X drops support for anything below 2.6.0, so requires min 2.6.0 and max 3.6.
# UniFi 6.X and 7.X up to excluding 7.4 mainly required 2.4.10 or 2.6.0 as min and anything below 3.0, 3.2, 3.4 and 3.6 (max).

# Add the MongoDB v3.6 repo to the host
wget -qO- https://www.mongodb.org/static/pgp/server-3.6.asc \
  | gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb-org-server-3.6-archive-keyring.gpg > /dev/null

echo "#deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/mongodb-org-server-3.6-archive-keyring.gpg] \
https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/3.6 multiverse" \
  | tee /etc/apt/sources.list.d/mongodb-org-3.6.list > /dev/null

# Add the MongoDB v4.4 repo to the host
wget -qO- https://www.mongodb.org/static/pgp/server-4.4.asc \
  | gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb-org-server-4.4-archive-keyring.gpg > /dev/null

echo "deb [arch=amd64,arm64 signed-by=/etc/apt/trusted.gpg.d/mongodb-org-server-4.4-archive-keyring.gpg] \
https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
  | tee /etc/apt/sources.list.d/mongodb-org-4.4.list > /dev/null

### OpenSSL (libss1.1)
# http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/
# libssl1.1_1.1.1f-1ubuntu2.21_amd64.deb
wget -c http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.21_amd64.deb \
  && dpkg -i libssl1.1_1.1.1f-1ubuntu2.21_amd64.deb

test -f ./libssl1.1_1.1.1f-1ubuntu2.21_amd64.deb \
  && rm -f ./libssl1.1_1.1.1f-1ubuntu2.21_amd64.deb
  
### Caddy Webserver

#apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y debian-keyring debian-archive-keyring

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /etc/apt/trusted.gpg.d/caddy-stable.gpg > /dev/null

cat <<EOF | tee /etc/apt/sources.list.d/caddy-stable.list
# https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/caddy-stable.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main
#deb-src [dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/caddy-stable.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main

EOF

# Install and enable the MongoDB server service
apt-get update -y \
  && apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y mongodb-org-server

systemctl enable --now mongod.service
#systemctl status --no-pager --full mongod.service

# Install and enable the UniFi controller software
apt-get -o APT::Get::Always-Include-Phased-Updates=true install -y unifi

systemctl enable --now unifi.service
#systemctl status --no-pager --full unifi.service

# Verify
#journalctl --no-pager --unit unifi.service
#dpkg -s unifi | grep -i version
#curl -k -sL https://127.0.0.1:8443/status | python3 -m json.tool
#tail -n 25 /usr/lib/unifi/logs/server.log
#tail -n 25 /usr/lib/unifi/logs/mongod.log

# Cleanup
apt-get clean \
  && apt-get autoclean
