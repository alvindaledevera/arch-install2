#!/bin/bash

whiptail --title "Step 1: Pre-installation" --msgbox "Initializing network check and mirror optimization..." 10 60

# Check Internet Connection
if ping -c 1 archlinux.org &> /dev/null; then
    echo "Internet connection verified."
else
    whiptail --title "Network Error" --msgbox "No internet connection. Please check your network setup." 10 50
    return
fi

# Enable NTP
timedatectl set-ntp true

# Enable Pacman Parallel Downloads
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

whiptail --title "Step 1" --msgbox "Pre-installation checks completed successfully!" 10 50