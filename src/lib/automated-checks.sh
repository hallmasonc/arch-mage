#!/usr/bin/env bash

## function(s)
network_check () {
    info_print "Checking system for network connectivity..."
    if ! ping -c 1 ping.archlinux.org &> /dev/null; then
        error_print "Unable to reach archlinux.org. Check network connection before continuing."
        return 1
    else
        info_print "Able to reach archlinux.org."
        return 0
    fi
}

uefi_check () {
    info_print "Checking system for UEFI/BIOS modes..."
    case $(cat /sys/firmware/efi/fw_platform_size) in
        '64')
            info_print "System is booted in 64-bit UEFI mode."
            return 0
            ;;
        '32')
            info_print "System is booted in 32-bit UEFI mode, bootloader options maybe limited."
            return 0
            ;;
        *)
            error_print "System is booted in BIOS mode. Check firmware settings or run this script on a UEFI system."
            return 1
    esac
}

reflector_check () {
    info_print "Running reflector to optimize the mirror list... "

    # backup mirror list incase of a failure with reflector
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    if ! reflector --protocol https --sort rate --age 12 --latest 12 --save /etc/pacman.d/mirrorlist &> /dev/null; then
        error_print "Reflector failed to set the mirrorlist. Restoring the original mirrorlist... "
        cp /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
    else
        info_print "Pacman mirrorlist has been optimized."
    fi
}

virt_check () {
    # variable(s)
    hypervisor=$(systemd-detect-virt)

    # guest tools setup
    case $hypervisor in
        kvm )
            info_print "KVM has been detected, setting up guest tools. "
            pacstrap /mnt qemu-guest-agent &>/dev/null
            systemctl enable qemu-guest-agent --root=/mnt &>/dev/null
            ;;
        vmware )
            info_print "VMWare Workstation/ESXi has been detected, setting up guest tools. "
            pacstrap /mnt open-vm-tools >/dev/null
            systemctl enable vmtoolsd --root=/mnt &>/dev/null
            systemctl enable vmware-vmblock-fuse --root=/mnt &>/dev/null
            ;;
        oracle )
            info_print "VirtualBox has been detected, setting up guest tools. "
            pacstrap /mnt virtualbox-guest-utils &>/dev/null
            systemctl enable vboxservice --root=/mnt &>/dev/null
            ;;
        microsoft )
            info_print "Hyper-V has been detected, setting up guest tools. "
            pacstrap /mnt hyperv &>/dev/null
            systemctl enable hv_fcopy_daemon --root=/mnt &>/dev/null
            systemctl enable hv_kvp_daemon --root=/mnt &>/dev/null
            systemctl enable hv_vss_daemon --root=/mnt &>/dev/null
            ;;
    esac
}

microcode_check () {
    # variable(s)
    local l_microcode=""
    local l_cpu=""
    l_cpu=$(grep vendor_id /proc/cpuinfo)

    # microcode check
    if [[ "$l_cpu" == *"AuthenticAMD"* ]]; then
        info_print "An AMD CPU has been detected, the AMD microcode will be installed."
        l_microcode="amd-ucode"
    else
        info_print "An Intel CPU has been detected, the Intel microcode will be installed."
        l_microcode="intel-ucode"
    fi

    # assign l_microcode to the calling function's variable
    if [[ -n "$1" ]]; then
        eval "$1='$l_microcode'"
    fi
}