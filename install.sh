#!/bin/bash

# Ensure script is run as root (Arch ISO environment)
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

while true; do
    CHOICE=$(whiptail --title "Arch Linux Custom Installer" \
    --menu "Main Menu - Select an action:" 20 70 8 \
    "1" "Pre-Installation & System Optimization" \
    "2" "Disk Setup, Security & Partitioning" \
    "3" "Formatting & Mounting Partitions" \
    "4" "Base System Installation (Pacstrap)" \
    "5" "System Configuration (User & Locale)" \
    "6" "Initramfs & Bootloader Setup" \
    "7" "Software & Environment (Drivers & DE)" \
    "8" "Finish & Reboot" \
    3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        if (whiptail --title "Exit" --yesno "Do you want to exit the installer?" 10 50); then
            clear
            exit 0
        else
            continue
        fi
    fi

    case $CHOICE in
        1) source ./modules/01_preinstall.sh ;;
        2) source ./modules/02_disk.sh ;;
        3) source ./modules/03_mount.sh ;;
        4) source ./modules/04_base.sh ;;
        5) source ./modules/05_config.sh ;;
        6) source ./modules/06_bootloader.sh ;;
        7) source ./modules/07_software.sh ;;
        8) source ./modules/08_finish.sh ;;
    esac
done