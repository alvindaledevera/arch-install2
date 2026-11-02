#!/bin/bash

HOSTNAME=$(whiptail --title "Hostname" --inputbox "Enter system hostname:" 10 60 "archlinux" 3>&1 1>&2 2>&3)
USERNAME=$(whiptail --title "User Setup" --inputbox "Enter regular username:" 10 60 "archuser" 3>&1 1>&2 2>&3)

whiptail --title "Configuration" --msgbox "Saved hostname ($HOSTNAME) and user ($USERNAME)." 10 50