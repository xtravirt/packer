#!/usr/bin/env bash

# file names & paths
tmp="/tmp"  # destination folder to store the final iso file
hostname="ubuntu"
currentuser="$( whoami)"
build_file="builder.sh"
seed_file="install.seed"

# define spinner function for slow tasks
# courtesy of http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

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

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

# print a pretty header
echo
echo " +---------------------------------------------------+"
echo " |            UNATTENDED UBUNTU ISO MAKER            |"
echo " +---------------------------------------------------+"
echo

# ask if script runs without sudo or root priveleges
if [ $currentuser != "root" ]; then
    echo " you need sudo privileges to run this script, or run it as root"
    exit 1
fi

#check that we are in ubuntu 18.04

fgrep "18.04" /etc/os-release >/dev/null 2>&1

if [ $? -eq 0 ]; then
     ub1804="yes"
fi

#get the latest versions of Ubuntu LTS

tmphtml=$tmp/tmphtml
rm $tmphtml >/dev/null 2>&1
wget -O $tmphtml 'http://mirror.lstn.net/ubuntu-releases/' >/dev/null 2>&1

bion=$(fgrep Bionic $tmphtml | head -1 | awk '{print $3}')
#prec=$(fgrep Precise $tmphtml | head -1 | awk '{print $3}')
#trus=$(fgrep Trusty $tmphtml | head -1 | awk '{print $3}')
#xenn=$(fgrep Xenial $tmphtml | head -1 | awk '{print $3}')



# ask whether to include vmware tools or not
while true; do
    echo " which ubuntu edition would you like to remaster:"
    echo
    echo "  [1] Ubuntu $bion LTS Server amd64 - Bionic Beaver"
    echo
    read -p " please enter your preference: [1]: " ubver
    case $ubver in
        [1]* )  download_file="ubuntu-18.04.1-server-amd64.iso"
                download_location="http://cdimage.ubuntu.com/ubuntu/releases/18.04/release/"
                new_iso_name="ubuntu-$bion-server-amd64-unattended.iso"
                break;;
        * ) echo " please answer [1]";;
    esac
done

if [ -f /etc/timezone ]; then
  timezone=`cat /etc/timezone`
elif [ -h /etc/localtime ]; then
  timezone=`readlink /etc/localtime | sed "s/\/usr\/share\/zoneinfo\///"`
else
  checksum=`md5sum /etc/localtime | cut -d' ' -f1`
  timezone=`find /usr/share/zoneinfo/ -type f -exec md5sum {} \; | grep "^$checksum" | sed "s/.*\/usr\/share\/zoneinfo\///" | head -n 1`
fi

# ask the user questions about his/her preferences
read -ep " please enter your preferred timezone: " -i "${timezone}" timezone
read -ep " please enter your preferred username: " -i "sonar" username
read -sp " please enter your preferred password: " password
printf "\n"
read -sp " confirm your preferred password: " password2
printf "\n"
read -ep " Make ISO bootable via USB: " -i "no" bootable

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit
fi
echo "Password Check: Pass"

# download the ubunto iso. If it already exists, do not delete in the end.
cd $tmp
if [[ ! -f $tmp/$download_file ]]; then
    echo -n " downloading $download_file: "
    download "$download_location$download_file"
fi
if [[ ! -f $tmp/$download_file ]]; then
  echo "Error: Failed to download ISO: $download_location$download_file"
  echo "This file may have moved or may no longer exist."
  echo
  echo "You can download it manually and move it to $tmp/$download_file"
  echo "Then run this script again."
  exit 1
fi
echo "Download $download_file iso: Pass"

# download seed file

if [[ ! -f $tmp/$seed_file ]]; then
    echo -n " downloading $seed_file: "
    download "https://raw.githubusercontent.com/xtravirt/UbuntuBuilder/master/$seed_file"
    echo "Download seed file: Pass"
    echo -n " downloading $build_file: "
    download "https://raw.githubusercontent.com/xtravirt/UbuntuBuilder/master/$build_file"
    echo "Download builder file: Pass"
fi


# install required packages
echo " installing required packages"
if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
    (apt-get -y update > /dev/null 2>&1) &
    spinner $!
    (apt-get -y install whois genisoimage > /dev/null 2>&1) &
    spinner $!
fi
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    if [ $(program_is_installed "isohybrid") -eq 0 ]; then
      #18.04
      if [ $ub1804 == "yes" ]; then
        (apt-get -y install syslinux syslinux-utils > /dev/null 2>&1) &
        spinner $!
      else
        (apt-get -y install syslinux > /dev/null 2>&1) &
        spinner $!
      fi
    fi
fi
echo "Install required packages: Pass"

# create working folders
echo " remastering your iso file"
mkdir -p $tmp
mkdir -p $tmp/iso_org
mkdir -p $tmp/iso_new

# mount the image
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop $tmp/$download_file $tmp/iso_org > /dev/null 2>&1)
fi
echo "Mount image: Pass"
# copy the iso contents to the working directory
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1) &
spinner $!
echo "Copy to working directory: Pass"
# set the language for the installation menu
cd $tmp/iso_new
#doesn't work for 18.04
echo en > $tmp/iso_new/isolinux/lang

#18.04
#taken from https://github.com/fries/prepare-ubuntu-unattended-install-iso/blob/master/make.sh
sed -i -r 's/timeout\s+[0-9]+/timeout 1/g' $tmp/iso_new/isolinux/isolinux.cfg
echo "Amend isolinux.cfg timeout value entry: Pass"

# set late command
#late_command="curl -L -o /tmp/builder.sh https://raw.githubusercontent.com/xtravirt/UbuntuBuilder/master/builder.sh;chmod +x /tmp/builder.sh;./tmp/builder.sh"
#echo "Generate late command & execute: Pass"

# copy the seed file to the iso
cp -rT $tmp/$seed_file $tmp/iso_new/preseed/$seed_file
echo "copy the install seed file to the iso: Pass"

# include firstrun script
#echo "
# setup firstrun script
#d-i preseed/late_command                                    string      $late_command" >> $tmp/iso_new/preseed/$seed_file
#echo "include firstrun script: Pass"

# generate the password hash
pwhash=$(echo $password | mkpasswd -s -m sha-512)
echo "generate the password hash: Pass"

# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{pwhash}}@$pwhash@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso_new/preseed/$seed_file
echo "update the seed file to reflect the users choices: Pass"

# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file)
echo "Calculate checksum for seed file: Pass"

# add the autoinstall option to the menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/install.seed preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg
echo "add the autoinstall option to the menu: Pass"

echo " creating the remastered iso"
cd $tmp/iso_new
(mkisofs -D -r -V "XV_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $tmp/$new_iso_name . > /dev/null 2>&1) &
spinner $!
echo "creating the remastered iso: Pass"

# make iso bootable (for dd'ing to  USB stick)
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    isohybrid $tmp/$new_iso_name
fi
echo "make iso bootable for usb (set value to $bootable): Pass"

# cleanup
umount $tmp/iso_org
cd $tmp
rm -rf $tmp/iso_new
rm -rf $tmp/iso_org
rm -rf $tmphtml
rm -rf $tmp/install.seed
rm -rf $tmp/download_file
echo "cleanup: Pass"

# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $tmp/$new_iso_name"
echo " your username is: $username"
echo " your password is: $password"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo

# unset vars
unset username
unset password
unset hostname
unset timezone
unset pwhash
unset download_file
unset download_location
unset new_iso_name
unset tmp
unset seed_file
