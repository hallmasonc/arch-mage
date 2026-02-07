#!/usr/bin/env bash

## function(s)
password_prompt () {
    # variable(s)
    local password=""

    # user input
    while IFS= read -r -s -n1 char; do
        if [[ $char == $'\0' ]]; then
            break
        elif [[ $char == $'\177' ]]; then
            if [ ${#password} -gt 0 ]; then
                password="${password%?}"
                printf "\b \b"
            fi
        else
            password+="$char"
            printf "*"
        fi
    done

    # assign password to the calling function's variable
    if [[ -n "$1" ]]; then
        eval "$1='$password'"
    fi
}

password_check () {
    # check if passwords are equal
    if [[ "$1" != "$2" ]]; then
        error_print "The passwords entered do not match, please try again. "
        return 1
    fi
}

## selector(s)
kblayout_selector () {
    # variable(s)
    local l_kblayout=""

    # user input
    input_print "Enter the console keyboard layout to use, or enter \"?\" to view available layouts (No input will default to US): "
    read -r l_kblayout
    case "$l_kblayout" in
        '')
            l_kblayout="us"
            info_print "The default US keyboard layout will be used. "
            # assign l_kblayout to the calling function's variable
            if [[ -n "$1" ]]; then
                eval "$1='$l_kblayout'"
            fi
            ;;
        '?')
            localectl list-keymaps
            clear
            return 1
            ;;
        *)
            if ! localectl list-keymaps | grep -Fxq "$l_kblayout"; then
                error_print "The specified keymap doesn't exist. "
                return 1
            fi
        
        # load keys
        info_print "Changing console layout to $l_kblayout. "
        loadkeys "$l_kblayout"

        # assign l_kblayout to the calling function's variable
        if [[ -n "$1" ]]; then
            eval "$1='$l_kblayout'"
        fi
    esac
}

locale_selector () {
    local l_locale=""

    # user input
    input_print "Please enter the locale to use or enter \"?\" to search locales. (format: xx_XX. No input will default to en_US): "
    read -r l_locale
    case "$l_locale" in
        '') 
            l_locale="en_US.UTF-8"
            info_print "$l_locale will be the default locale."
            # assign l_locale to the calling function's variable
            if [[ -n "$1" ]]; then
                eval "$1='$l_locale'"
            fi
            ;;
        '?')
            sed -E '/^# +|^#$/d;s/^#| *$//g;s/ .*/ (Charset:&)/' /etc/locale.gen | less -M
            clear
            return 1
            ;;
        *)
            if ! grep -q "^#\?$(printf %s "$l_locale" | sed 's/[].*[]/\\&/g')" /etc/locale.gen; then
                error_print "The specified locale doesn't exist or isn't supported."
                return 1
            fi
            info_print "$l_locale will be the default locale."
            # assign l_locale to the calling function's variable
            if [[ -n "$1" ]]; then
                eval "$1='$l_locale'"
            fi
    esac
}

disk_selector () {
    # variable(s)
    local l_disk=""

    # list disks
    info_print "Available disks for the installation: "
    mapfile -t ARR < <(lsblk -dpno NAME,SIZE,MODEL | grep -P "/dev/sd|nvme|vd");

    # user input
    PS3="Please select the number of the corresponding disk (e.g. 1): "
    select ENTRY in "${ARR[@]}"; do
        if [[ -n "$ENTRY" ]]; then
            l_disk=${ENTRY%% *}
            break
        else
            error_print "Invalid selection. Please choose a valid disk. "
            return 1
        fi
    done

    # confirm
    input_print "Install Arch Linux on disk $l_disk? [y/n]: "
    read -r disk_response
    if ! [[ "${disk_response,,}" =~ ^(yes|y)$ ]]; then
        error_print "Quitting..."
        exit
    else
        info_print "Arch Linux will be installed on the following disk: $l_disk "
    fi

    # assign l_disk to the calling function's variable
    if [[ -n "$1" ]]; then
        eval "$1='$l_disk'"
    fi
}

kernel_selector () {
    # variable(s)
    local l_kernel=""

    # user input
    info_print "List of kernels:"
    menu_print "1) Stable: Vanilla Linux kernel with a few specific Arch Linux patches applied"
    menu_print "2) Hardened: A security-focused Linux kernel"
    menu_print "3) Longterm: Long-term support (LTS) Linux kernel"
    menu_print "4) Zen Kernel: A Linux kernel optimized for performance (results vary by system)"
    input_print "Please select the number of the corresponding kernel (e.g. 1): " 
    read -r kernel_choice

    case $kernel_choice in
        1 ) l_kernel="linux" ;;
        2 ) l_kernel="linux-hardened" ;;
        3 ) l_kernel="linux-lts" ;;
        4 ) l_kernel="linux-zen" ;;
        * ) error_print "Not a valid selection, please try again. "; return 1
    esac

    # assign l_kernel to the calling function's variable
    if [[ -n "$1" ]]; then
        eval "$1='$l_kernel'"
    fi
}

network_selector () {
    # user input
    info_print "Network utilities: "
    menu_print "1) IWD: Utility to connect to networks written by Intel (WiFi-only, built-in DHCP client) "
    menu_print "2) NetworkManager: Universal network utility (both WiFi and Ethernet, highly recommended) "
    menu_print "3) wpa_supplicant: Utility with support for WEP and WPA/WPA2 (WiFi-only, DHCPCD will be automatically installed) "
    menu_print "4) dhcpcd: Basic DHCP client (Ethernet connections or VMs) "
    menu_print "5) I will do this on my own (only advanced users) "
    input_print "Please select the number of the corresponding networking utility (e.g. 1): "
    read -r network_choice

    if ! ((1 <= network_choice <= 5)); then
        error_print "Not a valid selection, please try again. "
        return 1
    else
        case $network_choice in
            1 ) info_print "Installing and enabling IWD. "
                pacstrap /mnt iwd >/dev/null
                systemctl enable iwd --root=/mnt &>/dev/null
                ;;
            2 ) info_print "Installing and enabling NetworkManager. "
                pacstrap /mnt networkmanager >/dev/null
                systemctl enable NetworkManager --root=/mnt &>/dev/null
                ;;
            3 ) info_print "Installing and enabling wpa_supplicant and dhcpcd. "
                pacstrap /mnt wpa_supplicant dhcpcd >/dev/null
                systemctl enable wpa_supplicant --root=/mnt &>/dev/null
                systemctl enable dhcpcd --root=/mnt &>/dev/null
                ;;
            4 ) info_print "Installing dhcpcd. "
                pacstrap /mnt dhcpcd >/dev/null
                systemctl enable dhcpcd --root=/mnt &>/dev/null
        esac
    fi
}

## input(s)
lukspass_input () {
    # variable(s)
    local luks_pass=""
    local luks_pass2=""

    # user input
    input_print "Enter a password for the LUKS container: "
    password_prompt "luks_pass"
    echo ''

    # confirm user input
    input_print "Confirm password for the LUKS container: "
    password_prompt "luks_pass2"
    echo ''

    # matching passsword check
    if ! password_check "$luks_pass" "$luks_pass2"; then
        return 1
    else
        # assign luks_pass2 to the calling function's variable
        if [[ -n "$1" ]]; then
            eval "$1='$luks_pass2'"
        fi
    fi
}

userpass_input () {
    # variable(s)
    local user_pass=""
    local user_pass2=""

    # user input
    input_print "Enter a username for the new system: "
    read -r user_name

    input_print "Enter a password for the new user: "
    password_prompt "user_pass"
    echo ''

    # confirm user input
    input_print "Confirm password for the new user: "
    password_prompt "user_pass2"
    echo ''

    # matching passsword check
    if ! password_check "$user_pass" "$user_pass2"; then
        return 1
    else
        # assign user_name to the calling function's variable
        if [[ -n "$1" ]]; then
            eval "$1='$user_name'"
        fi
        # assign user_pass2 to the calling function's variable
        if [[ -n "$2" ]]; then
            eval "$2='$user_pass2'"
        fi
    fi
}

rootpass_input () {
    # variable(s)
    local root_pass=""
    local root_pass2=""

    # user input
    input_print "Enter a password for the root account: "
    password_prompt "root_pass"
    echo ''

    # confirm root input
    input_print "Confirm password for the root account: "
    password_prompt "root_pass2"
    echo ''

    # matching passsword check
    if ! password_check "$root_pass" "$root_pass2"; then
        return 1
    else
        # assign root_pass2 to the calling function's variable
        if [[ -n "$1" ]]; then
            eval "$1='$root_pass2'"
        fi
    fi
}

hostname_input () {
    # variable(s)
    local l_hostname=""
    
    # user input
    input_print "Please enter a hostname: "
    read -r l_hostname
    
    # check if user input equals zero
    if [[ -z "$l_hostname" ]]; then
        error_print "Enter a hostname to continue. "
        return 1
    else
        # assign l_hostname to the calling function's variable
        if [[ -n "$1" ]]; then
            eval "$1='$l_hostname'"
        fi
    fi
}