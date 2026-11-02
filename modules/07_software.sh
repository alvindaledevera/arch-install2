#!/bin/bash
DE=$(whiptail --title "Desktop Environment" --menu "Select Desktop Environment:" 15 60 3 \
"KDE" "KDE Plasma" ON \
"GNOME" "GNOME" OFF \
"XFCE" "XFCE" OFF 3>&1 1>&2 2>&3)

whiptail --title "Software" --msgbox "Selected Environment: $DE" 10 50