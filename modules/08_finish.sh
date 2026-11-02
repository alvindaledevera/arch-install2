#!/bin/bash
if (whiptail --title "Reboot" --yesno "Installation complete. Do you want to reboot the system now?" 10 50); then
    umount -R /mnt
    reboot
fi