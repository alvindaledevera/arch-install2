#!/bin/bash

# Fetch disk list
DISKS=$(lsblk -d -n -o NAME,SIZE | awk '{print $1 " " $2}')
TARGET_DISK=$(whiptail --title "Select Disk" --menu "Select target disk for Arch installation:" 15 60 4 $(echo $DISKS) 3>&1 1>&2 2>&3)

if [ -z "$TARGET_DISK" ]; then
    return
fi

# LUKS Encryption Prompt
if (whiptail --title "LUKS Encryption" --yesno "Do you want to encrypt the disk using LUKS?" 10 50); then
    ENCRYPT="yes"
    LUKS_PASS=$(whiptail --passwordbox "Enter encryption passphrase:" 10 60 3>&1 1>&2 2>&3)
else
    ENCRYPT="no"
fi

whiptail --title "Disk Setup" --msgbox "Selected /dev/$TARGET_DISK (Encryption: $ENCRYPT)" 10 50