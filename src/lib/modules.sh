#!/usr/bin/env bash

## function(s)
disk_partition () {
    # variable(s)
    local l_disk="$1"

    # warn user and confirm
    error_print "The following operation is destructive and irreversible, proceed with caution."
    input_print "All data on disk $l_disk will be erased and a new partition table will be made. Continue? [y/n]: "
    read -r disk_response
    if ! [[ "${disk_response,,}" =~ ^(yes|y)$ ]]; then
        error_print "Quitting..."
        exit
    fi
    
    # erase disk
    info_print "Wiping MBR and GPT tables from $l_disk... "
    wipefs -af "$l_disk" &>/dev/null
    sgdisk -Zo "$l_disk" &>/dev/null
    
    # new partition scheme
    info_print "Creating a new GPT table and partitions on $l_disk... "
    parted -s "$l_disk" \
        mklabel gpt \
        mkpart ESP fat32 1MiB 1025MiB \
        set 1 esp on \
        mkpart CRYPTROOT 1025MiB 100% \

    l_esp="/dev/disk/by-partlabel/ESP"
    l_cryptroot="/dev/disk/by-partlabel/CRYPTROOT"
    
    # inform kernel
    info_print "Informing the kernel about the partition changes."
    partprobe "$l_disk"
    
    # assign l_esp to the calling function's variable
    if [[ -n "$2" ]]; then
        eval "$2='$l_esp'"
    fi
    
    # assign l_cryptroot to the calling function's variable
    if [[ -n "$3" ]]; then
        eval "$3='$l_cryptroot'"
    fi
}

disk_format () {
    # variable(s)
    local l_disk="$1"
    local l_esp="$2"
    local l_luks_pass="$3"
    local l_cryptroot="$4"
    local l_btrfs="/dev/mapper/cryptroot"
    local subvols=(snapshots var_pkgs var_log home root srv)
    
    # check disk type and set mount options accordingly
    if [[ $(lsblk "$l_disk" -Jdo NAME,ROTA | grep -oP '"rota": \K(true|false)') == "false" ]]; then
        # ssd
        local mountopts="autodefrag,discard=async,compress-force=zstd:3,noatime,space_cache,ssd"
    else
        # hdd
        local mountopts="autodefrag,compress-force=zstd:3,noatime"
    fi

    # format esp as fat32
    info_print "Formatting the EFI Partition as FAT32... "
    mkfs.fat -F 32 "$l_esp" &>/dev/null
    
    # new luks container for root
    info_print "Creating LUKS Container for the root partition... "
    echo -n "$l_luks_pass"  | cryptsetup luksFormat "$l_cryptroot" -d - &>/dev/null
    echo -n "$l_luks_pass"  | cryptsetup open "$l_cryptroot" cryptroot -d - 
    
    # format luks container as btrfs
    info_print "Formatting the LUKS container as btrfs... "
    mkfs.btrfs "$l_btrfs" &>/dev/null
    mount "$l_btrfs" /mnt

    # create btrfs subvolumes
    info_print "Creating btrfs subvolumes... "
    for subvol in '' "${subvols[@]}"; do
        btrfs subvolume create /mnt/@"$subvol" &>/dev/null
    done
    umount /mnt

    # mount new btrfs subvolumes
    info_print "Mounting the newly created subvolumes and EFI partition... "
    mount -o "$mountopts",subvol=@ "$l_btrfs" /mnt
    mkdir -p /mnt/{home,root,srv,.snapshots,var/{log,cache/pacman/pkg},boot}
    for subvol in "${subvols[@]:2}"; do
        mount -o "$mountopts",subvol=@"$subvol" "$l_btrfs" /mnt/"${subvol//_//}"
    done
    mount -o "$mountopts",subvol=@snapshots "$l_btrfs" /mnt/.snapshots
    mount -o "$mountopts",subvol=@var_pkgs "$l_btrfs" /mnt/var/cache/pacman/pkg
    mount "$l_esp" /mnt/boot/
    
    # modify permissions
    chmod 750 /mnt/root
    # disable CoW for directory
    chattr +C /mnt/var/log

    # assign l_btrfs to the calling function's variable
    if [[ -n "$5" ]]; then
        eval "$5='$l_btrfs'"
    fi
}

pacstrap_pkgs () {
    # variable(s)
    local l_kernel="$1"
    local l_microcode="$2"

    # pacstrap
    info_print "Installing the base system with pacstrap. This may take a while to complete..."
    if ! pacstrap -K /mnt base base-devel "$l_kernel" "$l_microcode" linux-firmware "$l_kernel"-headers btrfs-progs efibootmgr git grub grub-btrfs less man-db man-pages nano openssh reflector rsync snap-pac snapper sudo unzip zip zram-generator &> /dev/null; then
        error_print "Failed to install the base system. To avoid corruption, please reboot and run Arch Mage again."
        error_print "Quiting..."
        exit
    fi
}

system_configuration () {
    # variable(s)
    local l_hostname="$1"
    local l_locale="$2"
    local l_kblayout="$3"

    # Setting up the hostname.
    echo "$l_hostname" > /mnt/etc/hostname

    # Generating /etc/fstab.
    info_print "Generating a new fstab... "
    genfstab -U /mnt >> /mnt/etc/fstab

    # Configure selected locale and console keymap
    sed -i "/^#$l_locale/s/^#//" /mnt/etc/locale.gen
    echo "LANG=$l_locale" > /mnt/etc/locale.conf
    echo "KEYMAP=$l_kblayout" > /mnt/etc/vconsole.conf

    # Setting hosts file.
    info_print "Setting hosts file... "
    cat > /mnt/etc/hosts <<EOF
    127.0.0.1   localhost
    ::1         localhost
    127.0.1.1   $l_hostname.localdomain   $l_hostname
EOF
    # chroot
    info_print "Configuring timezone, clock, and locales... "
    arch-chroot /mnt /bin/bash -e <<EOF
    # configure timezone
    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null

    # set CMOS clock
    hwclock --systohc

    # generate locales
    locale-gen &>/dev/null
EOF

    # zRAM configuration
    info_print "Configuring zRAM... "
    cat > /mnt/etc/systemd/zram-generator.conf <<EOF
    [zram0]
    zram-size = min(ram, 16384)
EOF

    # enable services
    info_print "Enabling reflector, automatic snapshots, btrfs subvolume scrubbing and systemd-oomd... "
    services=(reflector.timer snapper-timeline.timer snapper-cleanup.timer btrfs-scrub@-.timer btrfs-scrub@home.timer btrfs-scrub@var-log.timer btrfs-scrub@\\x2esnapshots.timer grub-btrfsd.service systemd-oomd)
    for service in "${services[@]}"; do
        systemctl enable "$service" --root=/mnt &>/dev/null
    done
}

boot_configuration () {
    # variable(s)
    local l_cryptroot="$1"
    local l_btrfs="$2"

    # configure /etc/mkinitcpio.conf
    info_print "Configuring hooks in /etc/mkinitcpio.conf... "
    cat > /mnt/etc/mkinitcpio.conf <<EOF
    HOOKS=(systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems)
EOF

    # setting up LUKS2 encryption in grub
    info_print "Setting up grub config... "
    UUID=$(blkid -s UUID -o value "$l_cryptroot")
    sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&rd.luks.name=$UUID=cryptroot root=$l_btrfs," /mnt/etc/default/grub

    # chroot and configure the system to boot
    info_print "Configuring snapper, GRUB, and generating initramfs..."
    arch-chroot /mnt /bin/bash -e <<EOF

    # Generating a new initramfs.
    mkinitcpio -P &>/dev/null

    # Snapper configuration.
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots &>/dev/null
    mkdir /.snapshots
    mount -a &>/dev/null
    chmod 750 /.snapshots

    # Installing GRUB.
    grub-install --target=x86_64-efi --efi-directory=/boot/ --bootloader-id=GRUB &>/dev/null

    # Creating grub config file.
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
EOF
}

pacman_configuration () {
    # pacman eye-candy and parallel downloads
    info_print "Enabling colors, animations, and parallel downloads for pacman."
    sed -Ei 's/^#(Color)$/\1\nILoveCandy/;s/^#(ParallelDownloads).*/\1 = 10/' /mnt/etc/pacman.conf

    # pacman hook to backup /boot
    info_print "Configuring pacman hook to backup /boot..."
    mkdir /mnt/etc/pacman.d/hooks
    cat > /mnt/etc/pacman.d/hooks/50-bootbackup.hook <<EOF
    [Trigger]
    Operation = Upgrade
    Operation = Install
    Operation = Remove
    Type = Path
    Target = usr/lib/modules/*/vmlinuz

    [Action]
    Depends = rsync
    Description = Backing up /boot...
    When = PostTransaction
    Exec = /usr/bin/rsync -a --delete /boot /.bootbackup
EOF

    info_print "Configuring pacman hook to check for orphaned packages... "
    cat > /mnt/etc/pacman.d/hooks/70-orphans.hook <<EOF
    [Trigger]
    Operation = Install
    Operation = Upgrade
    Operation = Remove
    Type = Package
    Target = *

    [Action]
    Description = Searching for orphaned packages...
    When = PostTransaction
    Exec=/bin/bash -c 'pkgs="$(pacman -Qdttq)"; if [[ ! -z "$pkgs" ]]; then echo -e "The following packages are installed but not required (anymore):\n$pkgs\nYou can mark them as explicitly installed with '\''pacman -D --asexplicit <pkg>'\'' or remove them all using '\''pacman -Qtdq | pacman -Rns -'\''"; fi'

EOF
}

account_configuration () {
    local l_rootpass="$1"
    local l_username="$2"
    local l_userpass="$3"

    # set root user password
    info_print "Setting root password... "
    echo "root:$l_rootpass" | arch-chroot /mnt chpasswd

    # set new user password
    if [[ -n "$l_username" ]]; then
        echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
        info_print "Adding the user $l_username to the system with root privilege... "
        arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$l_username"
        info_print "Setting user password for $l_username... "
        echo "$l_username:$l_userpass" | arch-chroot /mnt chpasswd
    fi
}