# Arch Linux Menu-Driven Interactive LUKS on LVM Installation Plan

## Overview
This document outlines the detailed design and implementation steps for a menu-driven Arch Linux installation script featuring LUKS2 full-disk encryption, Logical Volume Manager (LVM) support, configurable filesystems (Btrfs with subvolumes, Ext4, XFS), flexible Swap configurations (**zRAM**, **Swapfile**, **Dedicated LVM Swap Partition**, or **None**), CPU microcode auto-detection (**intel-ucode** / **amd-ucode**), GPU driver selection, **Display Manager choice (ly / SDDM / GDM / none)**, **Bootloader choice (systemd-boot vs GRUB)**, **Reflector mirror optimization**, **Pacman Parallel Downloads**, and complete system localization & user sudoers configuration.

## Workflow Architecture

```mermaid
graph TD
    Start[Start Installation Script] --> ConfigPacman[Enable Pacman Parallel Downloads & Run Reflector]
    ConfigPacman --> CheckMenu[Display TUI Main Menu]
    CheckMenu --> HardwareDetect[Auto-detect CPU Intel/AMD & GPU Hardware]
    CheckMenu --> ConfigDisk[Configure Disk, LUKS Passphrase, Filesystem & Swap]
    CheckMenu --> ConfigDE[Configure Desktop Profile & DM: ly, SDDM, GDM, or None]
    CheckMenu --> ConfigBoot[Configure Bootloader: systemd-boot or GRUB]
    CheckMenu --> ConfigSystem[Configure Localization, Timezone, User, Sudoers & Passwords]
    ConfigDisk --> PartDisk[Create EFI Partition & LUKS Partition]
    PartDisk --> EncryptLUKS[Format LUKS2 Volume cryptsetup luksFormat]
    EncryptLUKS --> OpenLUKS[Open LUKS Container cryptsetup open]
    OpenLUKS --> PartLVM[Create LVM Physical Volume on Decrypted Device]
    PartLVM --> SetupVG[Create Volume Group & Logical Volumes: root, optional swap, home]
    SetupVG --> Format[Format EFI FAT32 & LVM Logical Volumes Btrfs/Ext4/XFS]
    Format --> BtrfsSub[Create Btrfs Subvolumes @, @home, @snapshots if Btrfs selected]
    BtrfsSub --> Mount[Mount Volumes to /mnt]
    Mount --> SetupSwap[Configure Swap: zram-generator, swapfile, or LVM swap]
    SetupSwap --> Pacstrap[Run pacstrap: base linux lvm2 cryptsetup ucode GPU-drivers DM-packages networkmanager]
    Pacstrap --> Mkinitcpio[Configure mkinitcpio.conf encrypt and lvm2 hooks]
    Mkinitcpio --> GenFstab[Generate /mnt/etc/fstab]
    GenFstab --> Chroot[Execute Chroot Configuration Script]
    Chroot --> SetLocale[Set Timezone, Generate Locale & Keymap]
    SetLocale --> CreateUser[Create User & Enable Sudoers %wheel]
    CreateUser --> EnableServices[Enable System Services: NetworkManager, ly/sddm/gdm]
    EnableServices --> Bootloader[Install Chosen Bootloader: systemd-boot or GRUB with cryptdevice Kernel Parameters]
    Bootloader --> Complete[Unmount & Close LUKS & Finished]
```

## Proposed File Structure
- [`install.sh`](install.sh): Main entry point script presenting the TUI menu and orchestrating installation.
- [`chroot-setup.sh`](chroot-setup.sh): Configuration script executed within `arch-chroot`.

## Feature Breakdown
1. **Pacman Optimization & Mirror Ranking**:
   - Enable `ParallelDownloads = 5` in `/etc/pacman.conf`.
   - Run `reflector` to fetch top HTTPS mirrors sorted by speed: `reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist`.

2. **Menu Interface (TUI)**:
   - Target drive selection
   - LUKS Encryption passphrase prompt & toggle
   - Filesystem Selection: **Btrfs** (with automatic `@`, `@home`, `@snapshots` subvolumes), **Ext4**, or **XFS**
   - **Swap Configuration Options**: `zram`, `swapfile`, `lvm_swap`, or `none`.
   - **Hardware & Driver Detection/Selection**: CPU microcode (Intel/AMD auto-detected), GPU drivers (Nvidia/AMD/Intel/Generic).
   - **Desktop Environment & Display Manager**:
     - DE Profiles: Hyprland, KDE Plasma, GNOME, Minimal CLI.
     - Display Manager Choice: **`ly`**, **`SDDM`**, **`GDM`**, or **None**.
   - **Bootloader Choice**: **`systemd-boot`** or **`GRUB`**.
   - **System Localization & User Settings**:
     - Timezone selection (e.g., `Asia/Manila`, `UTC`, etc.)
     - Locale selection (e.g., `en_US.UTF-8`)
     - Hostname setup
     - User creation with automatic wheel group membership and sudoers privilege configuration (`/etc/sudoers.d/wheel`).

3. **LUKS2 + LVM Storage Setup**:
   - Create EFI partition (512MB).
   - Encrypt second partition with LUKS2 (`cryptsetup luksFormat --type luks2`).
   - Open LUKS volume (`cryptsetup open /dev/sdX2 cryptlvm`).
   - Create Physical Volume, Volume Group (`vg0`), and Logical Volumes (`root`, `home`, optional `swap`).

4. **Filesystem Creation & Mounting**:
   - Btrfs subvolumes (`@`, `@home`, `@snapshots`, `@var_log`) with mount options `compress=zstd,noatime`, or Ext4 / XFS mount.

5. **Initramfs Hooks, Bootloader & System Chroot Setup**:
   - Install packages via `pacstrap`.
   - Configure `/etc/mkinitcpio.conf` HOOKS line for `encrypt` and `lvm2`.
   - Set timezone symlink `/etc/localtime` and sync hardware clock (`hwclock --systohc`).
   - Generate locale (`locale-gen`).
   - Setup user account, set root and user passwords, enable `%wheel ALL=(ALL:ALL) ALL` in `/etc/sudoers.d/10-installer`.
   - Enable display manager service (`ly.service`, `sddm.service`, or `gdm.service`).
   - Install and configure chosen bootloader (**systemd-boot** or **GRUB**) with LUKS kernel parameters (`cryptdevice=UUID=<partition_uuid>:cryptlvm root=/dev/vg0/root`) and microcode `initrd`.
