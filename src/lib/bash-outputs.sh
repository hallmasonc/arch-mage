#!/usr/bin/env bash

## variable(s)
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
WHITE='\e[97m'
BOLD='\e[1m'
RESET='\e[0m'

## function(s)
# pretty print
info_print () {
    echo -e "${BOLD}${GREEN}[ ${YELLOW}• ${GREEN}] $1${RESET}"
}

# pretty input
input_print () {
    echo -ne "${BOLD}${YELLOW}[ ${GREEN}? ${YELLOW}] $1${RESET}"
}

# pretty menu
menu_print () {
    echo -e "${BOLD}${GREEN}[ ${WHITE}- ${GREEN}]${WHITE} $1${RESET}"
}

# pretty error
error_print () {
    echo -e "${BOLD}${RED}[ ${YELLOW}! ${RED}] $1${RESET}"
}


welcome () {
    echo -e "${BOLD}${GREEN}
   ▄████████    ▄████████  ▄████████    ▄█    █▄           ▄▄▄▄███▄▄▄▄      ▄████████    ▄██████▄     ▄████████ 
  ███    ███   ███    ███ ███    ███   ███    ███        ▄██▀▀▀███▀▀▀██▄   ███    ███   ███    ███   ███    ███ 
  ███    ███   ███    ███ ███    █▀    ███    ███        ███   ███   ███   ███    ███   ███    █▀    ███    █▀  
  ███    ███  ▄███▄▄▄▄██▀ ███         ▄███▄▄▄▄███▄▄      ███   ███   ███   ███    ███  ▄███         ▄███▄▄▄     
▀███████████ ▀▀███▀▀▀▀▀   ███        ▀▀███▀▀▀▀███▀       ███   ███   ███ ▀███████████ ▀▀███ ████▄  ▀▀███▀▀▀     
  ███    ███ ▀███████████ ███    █▄    ███    ███        ███   ███   ███   ███    ███   ███    ███   ███    █▄  
  ███    ███   ███    ███ ███    ███   ███    ███        ███   ███   ███   ███    ███   ███    ███   ███    ███ 
  ███    █▀    ███    ███ ████████▀    ███    █▀          ▀█   ███   █▀    ███    █▀    ████████▀    ██████████ 
               ███    ███                                                                                       
${RESET}"
}