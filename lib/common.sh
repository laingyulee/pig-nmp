#!/usr/bin/env bash
#
# Pig-NMP - Common Utility Functions
#

_log() {
    local level="$1"; shift
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        error)   echo -e "[${ts}] ${C_RED}[ERROR]${C_RESET} $*" ;;
        warn)    echo -e "[${ts}] ${C_YELLOW}[WARN]${C_RESET} $*" ;;
        info)    echo -e "[${ts}] ${C_CYAN}[INFO]${C_RESET} $*" ;;
        success) echo -e "[${ts}] ${C_GREEN}[OK]${C_RESET} $*" ;;
        debug)   [[ "${DEBUG:-0}" == "1" ]] && echo -e "[${ts}] ${C_MAGENTA}[DEBUG]${C_RESET} $*" ;;
    esac
    [[ "$level" == "error" ]] && echo "[$ts] [ERROR] $*" >> "${LOG_DIR}/error.log" 2>/dev/null
}

log_error()   { _log error   "$@"; }
log_warn()    { _log warn    "$@"; }
log_info()    { _log info    "$@"; }
log_success() { _log success "$@"; }
log_debug()   { _log debug   "$@"; }

die() { log_error "$@"; exit 1; }

confirm() {
    local prompt="${1:-Are you sure?}" default="${2:-n}" yesno
    [[ "$default" == "y" ]] && prompt="${prompt} [Y/n]" || prompt="${prompt} [y/N]"
    read -rp "$(echo -e "${C_YELLOW}${prompt}${C_RESET} ")" yesno
    yesno="${yesno:-$default}"
    [[ "$yesno" =~ ^[Yy] ]]
}

prompt_input() {
    local prompt="$1" default="${2:-}" var_name="$3" result
    [[ -n "$default" ]] && prompt="${prompt} [${default}]"
    read -rp "$(echo -e "${C_CYAN}${prompt}:${C_RESET} ")" result
    result="${result:-$default}"
    [[ -n "$var_name" ]] && printf -v "$var_name" '%s' "$result" || echo "$result"
}

prompt_password() {
    local prompt="$1" var_name="$2" result
    read -rsp "$(echo -e "${C_CYAN}${prompt}:${C_RESET} ")" result
    echo ""
    [[ -n "$var_name" ]] && printf -v "$var_name" '%s' "$result" || echo "$result"
}

prompt_select() {
    local prompt="$1"; shift
    local -a options=("$@")
    echo -e "${HEADER_COLOR}${prompt}${C_RESET}" >&2
    local i
    for i in "${!options[@]}"; do
        echo -e "  ${MENU_NUM_COLOR}$((i+1)))${C_RESET} ${MENU_ITEM_COLOR}${options[$i]}${C_RESET}" >&2
    done
    local choice
    read -rp "$(echo -e "${C_CYAN}Enter number [1-${#options[@]}]:${C_RESET} ")" choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        echo "${options[$((choice-1))]}"
    fi
}

print_banner() {
    clear
    echo -e "${LOGO_COLOR}"
    cat << 'BANNER'
  ___ ___ ___     _       _                  _   _
 | _ \_ _/ __|   /_\ _  _| |_ ___ _ __  __ _| |_(_)___ _ _
 |  _/| | (_ |  / _ \ || |  _/ _ \ '  \/ _` |  _| / _ \ ' \
 |_| |___\___| /_/ \_\_,_|\__\___/_|_|_\__,_|\__|_\___/_||_|
BANNER
    echo -e "${C_RESET}"
    echo -e "  ${C_BOLD}Nginx + MySQL/MariaDB + PHP Environment Manager${C_RESET}"
    echo -e "  ${C_YELLOW}Version ${PIG_NMP_VERSION}${C_RESET}"
    echo ""
}

print_separator() {
    echo -e "${C_CYAN}$(printf '%*s' "$(tput cols 2>/dev/null || echo 60)" '' | tr ' ' '=')${C_RESET}"
}

print_status() {
    local service="$1" status="$2" color msg
    case "$status" in
        running|active|installed)  color="$C_GREEN"; msg="● $status" ;;
        stopped|inactive)          color="$C_RED";   msg="● $status" ;;
        not_installed|missing)     color="$C_YELLOW"; msg="○ $status" ;;
        *)                         color="$C_WHITE";  msg="  $status" ;;
    esac
    printf "  %-20s %b%s%b\n" "$service" "$color" "$msg" "$C_RESET"
}

check_root() { [[ $EUID -ne 0 ]] && die "This script must be run as root. Try: sudo bash $0"; }
check_os()   { [[ ! -f /etc/debian_version ]] && [[ ! -f /etc/lsb-release ]] && die "This script only supports Debian/Ubuntu systems."; }

is_installed()      { command -v "$1" &>/dev/null; }
is_service_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

get_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -n "$ip" ]] && { echo "$ip"; return; }
    ip=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    [[ -n "$ip" ]] && { echo "$ip"; return; }
    ip=$(curl -s4 --max-time 3 https://ifconfig.me 2>/dev/null) || \
    ip=$(curl -s4 --max-time 3 https://api.ipify.org 2>/dev/null) || \
    ip="127.0.0.1"
    echo "$ip"
}

gen_password() {
    local len="${1:-16}" chars='A-Za-z0-9_@%-.,:+' pass="" i
    for ((i=0; i<len; i++)); do
        pass+=$(tr -dc "$chars" < /dev/urandom 2>/dev/null | head -c1)
    done
    if [[ ${#pass} -lt "$len" ]]; then
        pass=$(openssl rand -base64 48 2>/dev/null | tr -dc "$chars" | head -c "$len")
    fi
    [[ -z "$pass" ]] && pass="PigNMP_$(date +%s)"
    echo "${pass:0:len}"
}

validate_domain() {
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]
}

port_in_use() { ss -tlnp 2>/dev/null | grep -q ":${1} " || netstat -tlnp 2>/dev/null | grep -q ":${1} "; }

ensure_dirs() {
    local dir
    for dir in "$@"; do
        [[ ! -d "$dir" ]] && mkdir -p "$dir"
    done
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "$file" "$backup"
        echo "$backup"
    fi
}

sed_inplace() {
    local file="$1"; shift
    if sed --version 2>/dev/null | grep -q GNU; then
        sed -i "$@" "$file"
    else
        sed -i '' "$@" "$file"
    fi
}

render_template() {
    local template="$1" output="$2"; shift 2
    [[ ! -f "$template" ]] && { log_error "Template not found: $template"; return 1; }
    cp "$template" "$output"
    while [[ $# -gt 0 ]]; do
        local key="${1%%=*}" val="${1#*=}"
        local escaped_val
        escaped_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
        sed_inplace "$output" "s|{{${key}}}|${escaped_val}|g"
        shift
    done
}

vhost_patch_php_block() {
    local vhost_file="$1" fpm_pass="$2" is_ssl="${3:-no}"
    [[ -z "$fpm_pass" ]] && { sed_inplace "$vhost_file" '/PHP_LOCATION_BLOCK/d'; return; }

    local https_param=""
    [[ "$is_ssl" == "yes" ]] && https_param=$'\n        fastcgi_param HTTPS on;'

    local tmp_php_block
    tmp_php_block=$(mktemp)
    cat > "$tmp_php_block" << BLOCKEOF
    location ~ [^/]\.php(/|\$) {
        fastcgi_pass ${fpm_pass};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;${https_param}
        include fastcgi_params;

        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_read_timeout 300;
        fastcgi_intercept_errors on;
    }
BLOCKEOF

    local tmp_out
    tmp_out=$(mktemp)
    local block_content
    block_content=$(cat "$tmp_php_block")
    awk -v block="$block_content" '/PHP_LOCATION_BLOCK/{print block; next}1' "$vhost_file" > "$tmp_out"
    mv "$tmp_out" "$vhost_file"
    rm -f "$tmp_php_block"
}

spinner() {
    local pid=$1 msg="${2:-Processing...}" spin='|/-\' i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r  ${C_CYAN}[${spin:$i:1}]${C_RESET} ${msg}"
        sleep 0.1
    done
    printf "\r%*s\r" "$(( ${#msg} + 10 ))" ""
}
