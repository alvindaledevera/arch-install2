#!/usr/bin/env bash
# chroot-setup.sh - Arch Linux Chroot Configuration Script
set -euo pipefail

# Read environment variables passed from install.sh
TARGET_DISK="${TARGET_DISK:-}"
TIMEZONE="${TIMEZONE:-UTC}"
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"
HOSTNAME="${HOSTNAME:-archlinux}"
USERNAME="${USERNAME:-archuser}"
USER_PASSWORD="${USER_PASSWORD:-archuser}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
BOOTLOADER="${BOOTLOADER:-systemd-boot}"
ENABLE_LUKS="${ENABLE_LUKS:-true}"
LUKS_PART_UUID="${LUKS_PART_UUID:-}"
FILESYSTEM="${FILESYSTEM:-ext4}"
DISPLAY_MANAGER="${DISPLAY_MANAGER:-none}"
SWAP_TYPE="${SWAP_TYPE:-zram}"
CPU_VENDOR="${CPU_VENDOR:-generic}"

echo "==> Configuring Timezone ($TIMEZONE)..."
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

echo "==> Configuring Localization ($LOCALE)..."
sed -i "s/^#\(${LOCALE}\)/\1/" /etc/locale.gen
if ! grep -q "^${LOCALE}" /etc/locale.gen; then
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

echo "==> Setting Hostname ($HOSTNAME)..."
echo "${HOSTNAME}" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

echo "==> Setting Root Password..."
echo "root:${ROOT_PASSWORD}" | chpasswd

echo "==> Creating User (${USERNAME}) with Sudoers Access..."
if ! id "${USERNAME}" &>/dev/null; then
    useradd -m -G wheel -s /bin/bash "${USERNAME}"
fi
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Enable wheel in sudoers
mkdir -p /etc/sudoers.d
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-installer
chmod 440 /etc/sudoers.d/10-installer

echo "==> Configuring Swap (${SWAP_TYPE})..."
if [[ "${SWAP_TYPE}" == "zram" ]]; then
    cat <<EOF > /etc/systemd/zram-generator.conf
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOF
elif [[ "${SWAP_TYPE}" == "swapfile" ]]; then
    if [[ "${FILESYSTEM}" == "btrfs" ]]; then
        btrfs filesystem mkswapfile --size 4G /swapfile || {
            truncate -s 0 /swapfile
            chattr +C /swapfile
            fallocate -l 4G /swapfile
            chmod 600 /swapfile
            mkswap /swapfile
        }
    else
        fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none
        chmod 600 /swapfile
        mkswap /swapfile
    fi
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab
fi

echo "==> Configuring Initramfs Hooks (/etc/mkinitcpio.conf)..."
# Replace default hooks to include encrypt and lvm2 before filesystems
if [[ "${ENABLE_LUKS}" == "true" ]]; then
    NEW_HOOKS="HOOKS=(base udev autodetect microcode modprobedb block encrypt lvm2 filesystems keyboard fsck)"
else
    NEW_HOOKS="HOOKS=(base udev autodetect microcode modprobedb block lvm2 filesystems keyboard fsck)"
fi

if grep -q "^HOOKS=" /etc/mkinitcpio.conf; then
    sed -i "s/^HOOKS=.*/${NEW_HOOKS}/" /etc/mkinitcpio.conf
else
    echo "${NEW_HOOKS}" >> /etc/mkinitcpio.conf
fi

echo "==> Regenerating Initramfs..."
mkinitcpio -P

echo "==> Enabling System Services..."
systemctl enable NetworkManager.service

if [[ "${DISPLAY_MANAGER}" == "ly" ]]; then
    systemctl enable ly.service || true
elif [[ "${DISPLAY_MANAGER}" == "sddm" ]]; then
    systemctl enable sddm.service || true
elif [[ "${DISPLAY_MANAGER}" == "gdm" ]]; then
    systemctl enable gdm.service || true
fi

echo "==> Configuring Bootloader (${BOOTLOADER})..."

# Detect microcode initrd image name
UCODE_INITRD=""
if [[ "${CPU_VENDOR}" == "intel" ]] && [[ -f /boot/intel-ucode.img ]]; then
    UCODE_INITRD="/intel-ucode.img"
elif [[ "${CPU_VENDOR}" == "amd" ]] && [[ -f /boot/amd-ucode.img ]]; then
    UCODE_INITRD="/amd-ucode.img"
fi

ROOT_FLAGS=""
if [[ "${FILESYSTEM}" == "btrfs" ]]; then
    ROOT_FLAGS="rootflags=subvol=@"
fi

CMDLINE_OPTS="rw ${ROOT_FLAGS}"
if [[ "${ENABLE_LUKS}" == "true" ]] && [[ -n "${LUKS_PART_UUID}" ]]; then
    CMDLINE_OPTS="cryptdevice=UUID=${LUKS_PART_UUID}:cryptlvm root=/dev/vg0/root ${CMDLINE_OPTS}"
else
    CMDLINE_OPTS="root=/dev/vg0/root ${CMDLINE_OPTS}"
fi

if [[ "${BOOTLOADER}" == "systemd-boot" ]]; then
    bootctl install --path=/boot

    cat <<EOF > /boot/loader/loader.conf
default arch.conf
timeout 3
console-mode max
editor no
EOF

    cat <<EOF > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
EOF

    if [[ -n "${UCODE_INITRD}" ]]; then
        echo "initrd  ${UCODE_INITRD}" >> /boot/loader/entries/arch.conf
    fi

    cat <<EOF >> /boot/loader/entries/arch.conf
initrd  /initramfs-linux.img
options ${CMDLINE_OPTS}
EOF

elif [[ "${BOOTLOADER}" == "grub" ]]; then
    pacman -S --noconfirm grub efibootmgr

    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

    # Inject CMDLINE into /etc/default/grub
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet ${CMDLINE_OPTS}\"|" /etc/default/grub

    if [[ "${ENABLE_LUKS}" == "true" ]]; then
        sed -i 's/^#\(GRUB_ENABLE_CRYPTODISK=y\)/\1/' /etc/default/grub || echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
    fi

    grub-mkconfig -o /boot/grub/grub.cfg
fi

echo "==> Chroot Setup Complete!"
