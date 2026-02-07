#!/usr/bin/env bash

## source(s)
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck disable=SC1091
{
source "$SCRIPT_DIR/lib/automated-checks.sh"
source "$SCRIPT_DIR/lib/bash-outputs.sh"
source "$SCRIPT_DIR/lib/user-selectors.sh"
source "$SCRIPT_DIR/lib/modules.sh"
}

## variable(s)
DISK=""
ESP=""
BTRFS=""
CRYPT_ROOT=""
KBLAYOUT=""
LUKS_PASS=""
ROOT_PASS=""
USER_PASS=""
USER_NAME=""
HOSTNAME=""
KERNEL=""
MICROCODE=""

## function(s)
prerequisites () {
    if ! network_check; then exit 1; fi
    if ! uefi_check; then exit 1; fi
}

main () {
    # clear tty
    clear

    welcome
    info_print "Welcome to Arch Mage! "

    # disk setup
    until kblayout_selector "KBLAYOUT"; do : ; done
    until locale_selector "LOCALE"; do : ; done
    until disk_selector "DISK"; do : ; done
    until lukspass_input "LUKS_PASS"; do : ; done
    until disk_partition "$DISK" "ESP" "CRYPT_ROOT"; do : ; done
    until disk_format "$DISK" "$ESP" "$LUKS_PASS" "$CRYPT_ROOT" "BTRFS"; do : ; done

    # pre-install checks
    until reflector_check; do : ; done
    
    # base system install
    until microcode_check "MICROCODE"; do : ; done
    until kernel_selector "KERNEL"; do : ; done
    until pacstrap_pkgs "$KERNEL" "$MICROCODE"; do : ; done
    until network_selector; do : ; done

    # post-install checks
    until virt_check; do : ; done

    # user inputs
    until rootpass_input "ROOT_PASS"; do : ; done
    until userpass_input "USER_NAME" "USER_PASS"; do : ; done
    until hostname_input "HOSTNAME"; do : ; done

    # system configuration
    until system_configuration "$HOSTNAME" "$LOCALE" "$KBLAYOUT"; do : ; done
    until boot_configuration "$CRYPT_ROOT" "$BTRFS"; do : ; done
    until pacman_configuration; do : ; done
    until account_configuration "$ROOT_PASS" "$USER_NAME" "$USER_PASS"; do : ; done
}

## init main
if ! prerequisites; then
    error_print "Oops, the system as configured doesn't meet the requirements to run this script. See above output for details. "
    exit 1
else
    main
fi