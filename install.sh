#!/usr/bin/env bash
# install.sh - Menu-driven Interactive Arch Linux Installer with LUKS & LVM
set -euo pipefail

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

# Ensure system is booted in UEFI mode
if [[ ! -d /sys/firmware/efi ]]; then
    echo "ERROR: Arch Linux installer must be booted in UEFI mode." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}   Arch Linux Interactive Installer (LUKS + LVM TUI)  ${NC}"
echo -e "${CYAN}======================================================${NC}"

# ----------------------------------------------------
# 1. Pacman Optimization & Mirror Ranking
# ----------------------------------------------------
echo -e "\n${BLUE}==> Optimizing pacman configuration & ranking mirrors...${NC}"
sed -i 's/^#ParallelDownloads =.*/ParallelDownloads = 5/' /etc/pacman.conf
sed -i 's/^ParallelDownloads =.*/ParallelDownloads = 5/' /etc/pacman.conf

if command -v reflector &>/dev/null; then
    echo -e "${GREEN}==> Running Reflector to rank top 10 HTTPS mirrors...${NC}"
    reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || true
fi

# ----------------------------------------------------
# 2. Helper Functions for Interactive Prompts
# ----------------------------------------------------
prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    read -rp "$(echo -e "${CYAN}${prompt}${NC} [${default}]: ")" input
    eval "${var_name}=\"\${input:-${default}}\""
}

prompt_password() {
    local prompt="$1"
    local var_name="$2"
    while true; do
        read -srp "$(echo -e "${CYAN}${prompt}${NC}: ")" pass1
        echo
        read -srp "$(echo -e "${CYAN}Confirm ${prompt}${NC}: ")" pass2
        echo
        if [[ "${pass1}" == "${pass2}" ]] && [[ -n "${pass1}" ]]; then
            eval "${var_name}=\"${pass1}\""
            break
        else
            echo -e "${RED}Passwords do not match or are empty. Try again.${NC}"
        fi
    done
}

# ----------------------------------------------------
# 3. Interactive Menu Configurations
# ----------------------------------------------------
echo -e "\n${BLUE}==> Step 1: Disk Selection${NC}"
echo "Available Storage Drives:"
lsblk -dno NAME,SIZE,TYPE,MODEL | grep -E 'disk' | awk '{print "  /dev/"$1" ("$2", "$4")"}'

default_disk="/dev/sda"
if lsblk /dev/nvme0n1 &>/dev/null; then
    default_disk="/dev/nvme0n1"
fi
prompt_input "Enter target disk path" "${default_disk}" TARGET_DISK

if [[ ! -b "${TARGET_DISK}" ]]; then
    echo -e "${RED}ERROR: Invalid block device ${TARGET_DISK}${NC}" >&2
    exit 1
fi

echo -e "\n${BLUE}==> Step 2: LUKS Encryption Setup${NC}"
read -rp "$(echo -e "${CYAN}Enable LUKS2 full-disk encryption? (y/N)${NC}: ")" luks_choice
ENABLE_LUKS="false"
LUKS_PASS=""
if [[ "${luks_choice,,}" == "y" || "${luks_choice,,}" == "yes" ]]; then
    ENABLE_LUKS="true"
    prompt_password "Enter LUKS Encryption Passphrase" LUKS_PASS
fi

echo -e "\n${BLUE}==> Step 3: Filesystem Selection${NC}"
echo "1) Btrfs (Subvolumes: @, @home, @snapshots, @var_log)"
echo "2) Ext4"
echo "3) XFS"
read -rp "$(echo -e "${CYAN}Select Filesystem [1-3, default 1]${NC}: ")" fs_choice
case "${fs_choice}" in
    2) FILESYSTEM="ext4" ;;
    3) FILESYSTEM="xfs" ;;
    *) FILESYSTEM="btrfs" ;;
esac

echo -e "\n${BLUE}==> Step 4: Swap Configuration${NC}"
echo "1) zRAM (systemd-zram-generator, dynamic compression)"
echo "2) Swapfile (4GB swapfile on root volume)"
echo "3) LVM Swap Partition (4GB dedicated LVM volume)"
echo "4) None"
read -rp "$(echo -e "${CYAN}Select Swap Mode [1-4, default 1]${NC}: ")" swap_choice
case "${swap_choice}" in
    2) SWAP_TYPE="swapfile" ;;
    3) SWAP_TYPE="lvm_swap" ;;
    4) SWAP_TYPE="none" ;;
    *) SWAP_TYPE="zram" ;;
esac

echo -e "\n${BLUE}==> Step 5: CPU Microcode Auto-Detection${NC}"
CPU_VENDOR="generic"
if grep -q -i "intel" /proc/cpuinfo; then
    CPU_VENDOR="intel"
    echo -e "${GREEN}Detected Intel CPU -> intel-ucode will be installed.${NC}"
elif grep -q -i "amd" /proc/cpuinfo; then
    CPU_VENDOR="amd"
    echo -e "${GREEN}Detected AMD CPU -> amd-ucode will be installed.${NC}"
else
    echo "Generic CPU detected."
fi

echo -e "\n${BLUE}==> Step 6: GPU Driver Selection${NC}"
echo "1) Generic / VM / Mesa (Default)"
echo "2) Nvidia (Proprietary linux kernel modules)"
echo "3) Nvidia Open (Open-source kernel modules)"
echo "4) AMD (Mesa + Vulkan Radeon)"
echo "5) Intel (Mesa + Vulkan Intel)"
read -rp "$(echo -e "${CYAN}Select GPU Driver [1-5, default 1]${NC}: ")" gpu_choice
case "${gpu_choice}" in
    2) GPU_DRIVER="nvidia" ;;
    3) GPU_DRIVER="nvidia-open" ;;
    4) GPU_DRIVER="amd" ;;
    5) GPU_DRIVER="intel" ;;
    *) GPU_DRIVER="generic" ;;
esac

echo -e "\n${BLUE}==> Step 7: Desktop Environment Profile${NC}"
echo "1) Minimal CLI (No GUI)"
echo "2) Hyprland (Wayland compositor)"
echo "3) KDE Plasma"
echo "4) GNOME"
read -rp "$(echo -e "${CYAN}Select Desktop Profile [1-4, default 1]${NC}: ")" de_choice
case "${de_choice}" in
    2) DESKTOP_PROFILE="hyprland" ;;
    3) DESKTOP_PROFILE="kde" ;;
    4) DESKTOP_PROFILE="gnome" ;;
    *) DESKTOP_PROFILE="minimal" ;;
esac

echo -e "\n${BLUE}==> Step 8: Display Manager Choice${NC}"
echo "1) ly (Console TUI Display Manager)"
echo "2) SDDM"
echo "3) GDM"
echo "4) None"
read -rp "$(echo -e "${CYAN}Select Display Manager [1-4, default 1]${NC}: ")" dm_choice
case "${dm_choice}" in
    2) DISPLAY_MANAGER="sddm" ;;
    3) DISPLAY_MANAGER="gdm" ;;
    4) DISPLAY_MANAGER="none" ;;
    *) DISPLAY_MANAGER="ly" ;;
esac

echo -e "\n${BLUE}==> Step 9: Bootloader Selection${NC}"
echo "1) systemd-boot (Lightweight UEFI bootloader)"
echo "2) GRUB"
read -rp "$(echo -e "${CYAN}Select Bootloader [1-2, default 1]${NC}: ")" boot_choice
case "${boot_choice}" in
    2) BOOTLOADER="grub" ;;
    *) BOOTLOADER="systemd-boot" ;;
esac

echo -e "\n${BLUE}==> Step 10: Localization & System Credentials${NC}"
prompt_input "Timezone" "Asia/Manila" TIMEZONE
prompt_input "Locale" "en_US.UTF-8" LOCALE
prompt_input "Hostname" "archlinux" HOSTNAME
prompt_input "Username" "archuser" USERNAME
prompt_password "Enter User Password" USER_PASSWORD
prompt_password "Enter Root Password" ROOT_PASSWORD

# ----------------------------------------------------
# 4. Installation Summary & Confirmation
# ----------------------------------------------------
clear
echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}                INSTALLATION SUMMARY                  ${NC}"
echo -e "${YELLOW}======================================================${NC}"
echo -e "Target Disk:       ${GREEN}${TARGET_DISK}${NC}"
echo -e "LUKS Encryption:   ${GREEN}${ENABLE_LUKS}${NC}"
echo -e "Filesystem:        ${GREEN}${FILESYSTEM}${NC}"
echo -e "Swap Mode:         ${GREEN}${SWAP_TYPE}${NC}"
echo -e "CPU Microcode:     ${GREEN}${CPU_VENDOR}${NC}"
echo -e "GPU Driver:        ${GREEN}${GPU_DRIVER}${NC}"
echo -e "Desktop Profile:   ${GREEN}${DESKTOP_PROFILE}${NC}"
echo -e "Display Manager:   ${GREEN}${DISPLAY_MANAGER}${NC}"
echo -e "Bootloader:        ${GREEN}${BOOTLOADER}${NC}"
echo -e "Timezone:          ${GREEN}${TIMEZONE}${NC}"
echo -e "Locale:            ${GREEN}${LOCALE}${NC}"
echo -e "Hostname:          ${GREEN}${HOSTNAME}${NC}"
echo -e "Username:          ${GREEN}${USERNAME}${NC}"
echo -e "${YELLOW}======================================================${NC}"
echo -e "${RED}WARNING: ALL DATA ON ${TARGET_DISK} WILL BE PERMANENTLY ERASED!${NC}"
read -rp "$(echo -e "${RED}Type 'YES' to proceed with installation: ${NC}")" confirm

if [[ "${confirm}" != "YES" ]]; then
    echo "Installation aborted by user."
    exit 0
fi

# ----------------------------------------------------
# 5. Disk Partitioning & Formatting
# ----------------------------------------------------
echo -e "\n${BLUE}==> Unmounting existing mounts on ${TARGET_DISK}...${NC}"
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true
vgchange -an vg0 2>/dev/null || true
cryptsetup close cryptlvm 2>/dev/null || true

echo -e "${BLUE}==> Partitioning drive ${TARGET_DISK}...${NC}"
sfdisk "${TARGET_DISK}" <<EOF
label: gpt
1 : size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System Partition"
2 : type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="LUKS_LVM_Root"
EOF

# Partition naming check (nvme vs sd)
if [[ "${TARGET_DISK}" =~ nvme ]]; then
    EFI_PART="${TARGET_DISK}p1"
    ROOT_PART="${TARGET_DISK}p2"
else
    EFI_PART="${TARGET_DISK}1"
    ROOT_PART="${TARGET_DISK}2"
fi

partprobe "${TARGET_DISK}"
sleep 2

echo -e "${BLUE}==> Formatting EFI Partition (${EFI_PART})...${NC}"
mkfs.vfat -F 32 -n EFI "${EFI_PART}"

LVM_TARGET="${ROOT_PART}"
LUKS_PART_UUID=""

if [[ "${ENABLE_LUKS}" == "true" ]]; then
    echo -e "${BLUE}==> Setting up LUKS2 encryption on ${ROOT_PART}...${NC}"
    echo -n "${LUKS_PASS}" | cryptsetup luksFormat --type luks2 --pbkdf argon2id "${ROOT_PART}" -
    echo -n "${LUKS_PASS}" | cryptsetup open "${ROOT_PART}" cryptlvm -
    LVM_TARGET="/dev/mapper/cryptlvm"
    LUKS_PART_UUID=$(blkid -s UUID -o value "${ROOT_PART}")
fi

echo -e "${BLUE}==> Creating LVM Volume Group and Logical Volumes...${NC}"
pvcreate -f "${LVM_TARGET}"
vgcreate -f vg0 "${LVM_TARGET}"

if [[ "${SWAP_TYPE}" == "lvm_swap" ]]; then
    lvcreate -L 4G vg0 -n swap
    mkswap /dev/vg0/swap
    swapon /dev/vg0/swap
fi

lvcreate -l 100%FREE vg0 -n root

echo -e "${BLUE}==> Formatting Root Filesystem (${FILESYSTEM})...${NC}"
if [[ "${FILESYSTEM}" == "btrfs" ]]; then
    mkfs.btrfs -f -L archroot /dev/vg0/root
    mount /dev/vg0/root /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@var_log
    umount /mnt

    mount -o subvol=@,compress=zstd,noatime /dev/vg0/root /mnt
    mkdir -p /mnt/{home,.snapshots,var/log,boot}
    mount -o subvol=@home,compress=zstd,noatime /dev/vg0/root /mnt/home
    mount -o subvol=@snapshots,compress=zstd,noatime /dev/vg0/root /mnt/.snapshots
    mount -o subvol=@var_log,compress=zstd,noatime /dev/vg0/root /mnt/var/log
elif [[ "${FILESYSTEM}" == "ext4" ]]; then
    mkfs.ext4 -F -L archroot /dev/vg0/root
    mount /dev/vg0/root /mnt
    mkdir -p /mnt/boot
elif [[ "${FILESYSTEM}" == "xfs" ]]; then
    mkfs.xfs -f -L archroot /dev/vg0/root
    mount /dev/vg0/root /mnt
    mkdir -p /mnt/boot
fi

mount "${EFI_PART}" /mnt/boot

# ----------------------------------------------------
# 6. Pacstrap System Packages
# ----------------------------------------------------
echo -e "${BLUE}==> Building package list for pacstrap...${NC}"
PACSTRAP_PKGS=(base base-devel linux linux-firmware lvm2 cryptsetup networkmanager sudo vim nano git efibootmgr reflector)

if [[ "${FILESYSTEM}" == "btrfs" ]]; then
    PACSTRAP_PKGS+=(btrfs-progs)
fi

if [[ "${SWAP_TYPE}" == "zram" ]]; then
    PACSTRAP_PKGS+=(zram-generator)
fi

if [[ "${CPU_VENDOR}" == "intel" ]]; then
    PACSTRAP_PKGS+=(intel-ucode)
elif [[ "${CPU_VENDOR}" == "amd" ]]; then
    PACSTRAP_PKGS+=(amd-ucode)
fi

case "${GPU_DRIVER}" in
    nvidia) PACSTRAP_PKGS+=(nvidia nvidia-utils) ;;
    nvidia-open) PACSTRAP_PKGS+=(nvidia-open nvidia-utils) ;;
    amd) PACSTRAP_PKGS+=(mesa xf86-video-amdgpu vulkan-radeon) ;;
    intel) PACSTRAP_PKGS+=(mesa xf86-video-intel vulkan-intel) ;;
    *) PACSTRAP_PKGS+=(mesa) ;;
esac

case "${DESKTOP_PROFILE}" in
    hyprland)
        PACSTRAP_PKGS+=(hyprland waybar rofi-wayland kitty pipewire wireplumber polkit-gnome grim slurp)
        ;;
    kde)
        PACSTRAP_PKGS+=(plasma-desktop dolphin konsole pipewire wireplumber)
        ;;
    gnome)
        PACSTRAP_PKGS+=(gnome gnome-terminal pipewire wireplumber)
        ;;
esac

case "${DISPLAY_MANAGER}" in
    ly) PACSTRAP_PKGS+=(ly) ;;
    sddm) PACSTRAP_PKGS+=(sddm) ;;
    gdm) PACSTRAP_PKGS+=(gdm) ;;
esac

echo -e "${BLUE}==> Running pacstrap...${NC}"
pacstrap -K /mnt "${PACSTRAP_PKGS[@]}"

# ----------------------------------------------------
# 7. Generate Fstab & Execute Chroot
# ----------------------------------------------------
echo -e "${BLUE}==> Generating fstab...${NC}"
genfstab -U /mnt >> /mnt/etc/fstab

echo -e "${BLUE}==> Transferring chroot configuration script...${NC}"
cp "${SCRIPT_DIR}/chroot-setup.sh" /mnt/chroot-setup.sh
chmod +x /mnt/chroot-setup.sh

echo -e "${BLUE}==> Executing chroot setup...${NC}"
TARGET_DISK="${TARGET_DISK}" \
TIMEZONE="${TIMEZONE}" \
LOCALE="${LOCALE}" \
HOSTNAME="${HOSTNAME}" \
USERNAME="${USERNAME}" \
USER_PASSWORD="${USER_PASSWORD}" \
ROOT_PASSWORD="${ROOT_PASSWORD}" \
BOOTLOADER="${BOOTLOADER}" \
ENABLE_LUKS="${ENABLE_LUKS}" \
LUKS_PART_UUID="${LUKS_PART_UUID}" \
FILESYSTEM="${FILESYSTEM}" \
DISPLAY_MANAGER="${DISPLAY_MANAGER}" \
SWAP_TYPE="${SWAP_TYPE}" \
CPU_VENDOR="${CPU_VENDOR}" \
arch-chroot /mnt /chroot-setup.sh

rm -f /mnt/chroot-setup.sh

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}   ARCH LINUX INSTALLATION SUCCESSFULLY COMPLETED!    ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "You can now unmount and reboot into your new system:"
echo -e "  umount -R /mnt"
echo -e "  reboot"
