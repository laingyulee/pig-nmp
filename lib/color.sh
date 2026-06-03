#!/usr/bin/env bash
#
# Pig-NMP - Color Definitions
#

if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    C_RED=$(tput setaf 1)
    C_GREEN=$(tput setaf 2)
    C_YELLOW=$(tput setaf 3)
    C_BLUE=$(tput setaf 4)
    C_MAGENTA=$(tput setaf 5)
    C_CYAN=$(tput setaf 6)
    C_WHITE=$(tput setaf 7)
    C_BOLD=$(tput bold)
    C_RESET=$(tput sgr0)

    BG_RED=$(tput setab 1)
    BG_GREEN=$(tput setab 2)
    BG_YELLOW=$(tput setab 3)
    BG_BLUE=$(tput setab 4)
else
    C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
    C_MAGENTA="" C_CYAN="" C_WHITE="" C_BOLD="" C_RESET=""
    BG_RED="" BG_GREEN="" BG_YELLOW="" BG_BLUE=""
fi

LOGO_COLOR="${C_CYAN}${C_BOLD}"
TITLE_COLOR="${C_GREEN}${C_BOLD}"
ERROR_COLOR="${C_RED}${C_BOLD}"
WARN_COLOR="${C_YELLOW}"
INFO_COLOR="${C_CYAN}"
SUCCESS_COLOR="${C_GREEN}"
HIGHLIGHT_COLOR="${C_MAGENTA}${C_BOLD}"
MENU_NUM_COLOR="${C_GREEN}${C_BOLD}"
MENU_ITEM_COLOR="${C_WHITE}"
HEADER_COLOR="${C_YELLOW}${C_BOLD}"
