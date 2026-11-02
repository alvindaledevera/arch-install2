#!/bin/bash

KERNEL=$(whiptail --title "Kernel Selection" --menu "Select Linux Kernel:" 15 60 3 \
"linux" "Standard Linux Kernel" ON \
"linux-zen" "Zen Kernel (Performance/Desktop)" OFF \
"linux-lts" "Long Term Support Kernel" OFF 3>&1 1>&2 2>&3)

if [ ! -z "$KERNEL" ]; then
    whiptail --title "Pacstrap" --msgbox "Installing base system using kernel: $KERNEL..." 10 60
    # Commands:
    # pacstrap /mnt base base-devel $KERNEL linux-firmware
    # genfstab -U /mnt >> /mnt/etc/fstab
fi