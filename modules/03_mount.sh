#!/bin/bash

whiptail --title "Formatting & Mounting" --msgbox "Formatting partitions (mkfs.ext4/fat32) and mounting them to /mnt will happen here..." 10 60
# Example command:
# mount /dev/mapper/vg_arch-lv_root /mnt