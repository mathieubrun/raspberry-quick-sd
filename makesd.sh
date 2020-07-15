#!/usr/bin/env bash

IMAGE_URL=https://downloads.raspberrypi.org/raspios_lite_armhf_latest
IMAGE_SHA=f5786604be4b41e292c5b3c711e2efa64b25a5b51869ea8313d58da0b46afc64
IMAGE=.data/2020-05-27-raspios-buster-lite-armhf.img

IMAGE_ZIP=.data/raspbian_lite.zip

if [[ $1 == "" ]]; then
    echo "usage: $0 HOSTNAME"
    exit 1
fi

PI_HOSTNAME=$1

if [[ ! -f ".env" ]]; then
    echo ".env file not found, create one containing :"
    echo "WLAN_SSID=XXXXX"
    echo "WLAN_PASS=XXXXX"
    echo "SD_DEV=/dev/mmcblk0"
    exit 1
fi

source .env

if [[ ! -f "$IMAGE_ZIP" ]]; then
    echo "Downloading image"
    curl -L --progress-bar $IMAGE_URL -o $IMAGE_ZIP
fi

echo "Checking checksum"
if ! echo "$IMAGE_SHA $IMAGE_ZIP" | sha256sum -c -; then
    echo "Checksum failed" >&2
    exit 1
fi

unzip -o $IMAGE_ZIP -d .data

OFFSETS=($(parted -s $IMAGE unit B print | awk '/^Number/{p=1;next}; p{gsub(/[^[:digit:]]/, "", $2); print $2}'))
SIZES=($(parted -s $IMAGE unit B print | awk '/^Number/{p=1;next}; p{gsub(/[^[:digit:]]/, "", $4); print $4}'))

mkdir -p .data/boot
mkdir -p .data/root

echo "Mounting with offset ${OFFSETS[0]} on .data/boot"
sudo mount -v -o offset=${OFFSETS[0]},sizelimit=${SIZES[0]} -t vfat $IMAGE .data/boot
echo "Mounting with offset ${OFFSETS[1]} on .data/boot"
sudo mount -v -o offset=${OFFSETS[1]},sizelimit=${SIZES[1]} -t ext4 $IMAGE .data/root

echo "Changing hostname"
sudo sed -i "s/raspberrypi/$PI_HOSTNAME/g" .data/root/etc/hostname
sudo sed -i "s/raspberrypi/$PI_HOSTNAME/g" .data/root/etc/hosts

echo "Adding ssh key"
sudo touch .data/boot/ssh

mkdir -p .data/root/home/pi/.ssh
touch .data/root/home/pi/.ssh/authorized_keys
chmod 700 .data/root/home/pi/.ssh
chmod 600 .data/root/home/pi/.ssh/authorized_keys
cat ~/.ssh/id_rsa.pub > .data/root/home/pi/.ssh/authorized_keys

echo "Disabling password authentication"
sudo sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/g" .data/root/etc/ssh/sshd_config

echo "Adding wpa_supplicant"
sudo bash -c "cat << DELIMITER > .data/boot/wpa_supplicant.conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
        ssid=\"$WLAN_SSID\"
        psk=\"$WLAN_PASS\"
}
DELIMITER"

echo "Done"
sudo umount .data/root
sudo umount .data/boot

echo "Copying new image to SD"
sudo umount ${SD_DEV}p1                                                
sudo umount ${SD_DEV}p2    
sudo dd bs=4M if=$IMAGE of=$SD_DEV conv=fsync
echo "Done"