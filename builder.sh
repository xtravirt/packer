#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="sanlan"
default_puppetmaster="puppetmaster.sanlan"
default_puppet="n"
tmp="/root/"
username="$(logname)"
authorized_keyfile="http://fileserver.sanlan:80/my-machines.pub"

clear

# check for root privilege
if [ "$(id -u)" != "0" ]; then
   echo " this script must be run as root" 1>&2
   echo
   exit 1
fi

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# determine ubuntu version
ubuntu_version=$(lsb_release -cs)

# check for interactive shell
if ! grep -q "noninteractive" /proc/cmdline ; then
    stty sane

    # ask questions
    read -ep " please enter your preferred hostname: " -i "$default_hostname" hostname
    read -ep " please enter your preferred domain: " -i "$default_domain" domain
fi

# print status message
echo " Preparing server. This may take a few minutes"

# set fqdn
fqdn="$hostname.$domain"

# update hostname
echo "$hostname" > /etc/hostname
sed -i "s@ubuntu.ubuntu@$fqdn@g" /etc/hosts
sed -i "s@ubuntu@$hostname@g" /etc/hosts
hostname "$hostname"

# update repos
apt-get -y update
apt-get -y -o Dpkg::Options::="--force-confold" upgrade 

# Installation of Jenkins
echo "Download jenkins.io.key file"
wget - https://pkg.jenkins.io/debian/jenkins.io.key
echo "Import jenkins.io.key"
apt-key add jenkins.io.key
echo "Write into /etc/apt/sources.list.d/jenkins.list file"
sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
echo "Apt Update"
apt-get update
echo "Install Multiple Packages"
apt-get install unzip ccze slurm ncdu nano nmon mingetty screen open-vm-tools apt-transport-https openjdk-8-jdk -y
echo "Apt Update"
apt-get update
echo "Install Jenkins"
apt-get install jenkins -y

# Installation of Packer
echo "Create Packer Directory & Configure Permissions"
mkdir /packer
chmod 777 /packer
cd /tmp
echo "Download packer_1.2.5_linux_amd64"
wget https://releases.hashicorp.com/packer/1.2.5/packer_1.2.5_linux_amd64.zip
echo "Extract and place packer"
unzip packer_1.2.5_linux_amd64.zip -d /packer

# Download Packer scripts from Sonar Github Account
echo "Download custom packer scripts and locate"
wget https://github.com/xtravirt/packer/archive/master.zip
unzip master.zip -d /tmp
mv /tmp/packer-master/* /packer

# Configure variables
export NMON=mndc
export PATH="$PATH:/usr/local/packer"
echo "Update Environment"
source /etc/environment

# Clean up files that are no longer needed
echo "Perform file system cleanup activity"
rm -f /tmp/master.zip
rm -f /tmp/packer_1.2.5_linux_amd64.zip
rm -d -f /tmp/packer-master
rm -f /tmp/jenkins.io.key

apt-get -y autoremove
apt-get -y purge

# remove myself to prevent any unintended changes at a later stage
rm $0

# finish
echo " DONE; rebooting ... "

# reboot
reboot
