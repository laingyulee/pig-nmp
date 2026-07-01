#!/usr/bin/env bash
#
# Pig-NMP - Common Utility Functions
#

source "${LIB_DIR}/color.sh"

_log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        error)   echo -e "[${ts}] ${C_RED}[ERROR]${C_RESET} ${msg}" ;;
        warn)    echo -e "[${ts}] ${C_YELLOW}[WARN]${C_RESET} ${msg}" ;;
        info)    echo -e "[${ts}] ${C_CYAN}[INFO]${C_RESET} ${msg}" ;;
        success) echo -e "[${ts}] ${C_GREEN}[OK]${C_RESET} ${msg}" ;;
        debug)   [[ "${DEBUG:-0}" == "1" ]] && echo -e "[${ts}] ${C_MAGENTA}[DEBUG]${C_RESET} ${msg}" ;;
    esac
    if [[ "$level" == "error" ]]; then
        echo "[$ts] [ERROR] $msg" >> "${LOG_DIR}/error.log" 2>/dev/null
    fi
}

log_error()   { _log error   "$@"; }
log_warn()    { _log warn    "$@"; }
log_info()    { _log info    "$@"; }
log_success() { _log success "$@"; }
log_debug()   { _log debug   "$@"; }

die() {
    log_error "$@"
    exit 1
}

confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"
    local yesno
    if [[ "$default" == "y" ]]; then
        prompt="${prompt} [Y/n]"
    else
        prompt="${prompt} [y/N]"
    fi
    read -rp "$(echo -e "${C_YELLOW}${prompt}${C_RESET} ")" yesno
    yesno="${yesno:-$default}"
    [[ "$yesno" =~ ^[Yy] ]]
}

prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local var_name="$3"
    local result
    if [[ -n "$default" ]]; then
        prompt="${prompt} [${default}]"
    fi
    read -rp "$(echo -e "${C_CYAN}${prompt}:${C_RESET} ")" result
    result="${result:-$default}"
    if [[ -n "$var_name" ]]; then
        printf -v "$var_name" '%s' "$result"
    else
        echo "$result"
    fi
}

prompt_password() {
    local prompt="$1"
    local var_name="$2"
    local result
    read -rsp "$(echo -e "${C_CYAN}${prompt}:${C_RESET} ")" result
    echo ""
    if [[ -n "$var_name" ]]; then
        printf -v "$var_name" '%s' "$result"
    else
        echo "$result"
    fi
}

prompt_select() {
    local prompt="$1"
    shift
    local -a options=("$@")
    local i choice
    echo -e "${HEADER_COLOR}${prompt}${C_RESET}" >&2
    for i in "${!options[@]}"; do
        echo -e "  ${MENU_NUM_COLOR}$((i+1)))${C_RESET} ${MENU_ITEM_COLOR}${options[$i]}${C_RESET}" >&2
    done
    read -rp "$(echo -e "${C_CYAN}Enter number [1-${#options[@]}]:${C_RESET} ")" choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#options[@]}" ]]; then
        echo "${options[$((choice-1))]}"
    else
        echo ""
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
    local service="$1"
    local status="$2"
    local color msg
    case "$status" in
        running|active|installed)  color="$C_GREEN"; msg="● $status" ;;
        stopped|inactive)          color="$C_RED";   msg="● $status" ;;
        not_installed|missing)     color="$C_YELLOW"; msg="○ $status" ;;
        *)                         color="$C_WHITE";  msg="  $status" ;;
    esac
    printf "  %-20s %b%s%b\n" "$service" "$color" "$msg" "$C_RESET"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Try: sudo bash $0"
    fi
}

check_os() {
    if [[ ! -f /etc/debian_version ]] && [[ ! -f /etc/lsb-release ]]; then
        die "This script only supports Debian/Ubuntu systems."
    fi
}

is_installed() {
    command -v "$1" &>/dev/null
}

is_service_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

service_ctl() {
    local action="$1"
    local service="$2"
    case "$action" in
        start|stop|restart|reload|enable|disable)
            systemctl "$action" "$service" 2>/dev/null
            ;;
        status)
            systemctl status "$service" 2>/dev/null --no-pager
            ;;
    esac
}

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

wait_enter() {
    read -n 1 -s -r -p "$(echo -e "${C_CYAN}Press any key to continue...${C_RESET}")"
    echo ""
}

gen_password() {
    local len="${1:-16}"
    local chars='A-Za-z0-9_@%-.,:+'
    local pass=""
    local i
    for ((i=0; i<len; i++)); do
        pass+=$(tr -dc "$chars" < /dev/urandom 2>/dev/null | head -c1)
    done
    if [[ ${#pass} -lt "$len" ]]; then
        pass=$(openssl rand -base64 48 2>/dev/null | tr -dc "$chars" | head -c "$len")
    fi
    if [[ ${#pass} -lt "$len" ]]; then
        pass=$(date +%s%N | sha256sum | head -c "$len")
    fi
    [[ -z "$pass" ]] && pass="PigNMP_$(date +%s)"
    echo "${pass:0:len}"
}

version_compare() {
    if [[ "$1" == "$2" ]]; then return 0; fi
    local IFS=.
    local -a v1=($1) v2=($2)
    local i p1 p2
    for ((i=0; i<${#v1[@]} || i<${#v2[@]}; i++)); do
        p1="${v1[i]:-0}"
        p2="${v2[i]:-0}"
        p1=$((10#${p1}))
        p2=$((10#${p2}))
        if ((p1 > p2)); then return 1; fi
        if ((p1 < p2)); then return 2; fi
    done
    return 0
}

validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]; then
        return 0
    fi
    return 1
}

port_in_use() {
    ss -tlnp 2>/dev/null | grep -q ":${1} " || \
    netstat -tlnp 2>/dev/null | grep -q ":${1} "
}

ensure_dirs() {
    local dir
    for dir in "$@"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_debug "Created directory: $dir"
        fi
    done
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "$file" "$backup"
        log_debug "Backed up: $file -> $backup"
        echo "$backup"
    fi
}

sed_inplace() {
    local file="$1"
    shift
    if sed --version 2>/dev/null | grep -q GNU; then
        sed -i "$@" "$file"
    else
        sed -i '' "$@" "$file"
    fi
}

render_template() {
    local template="$1"
    local output="$2"
    shift 2
    if [[ ! -f "$template" ]]; then
        log_error "Template not found: $template"
        return 1
    fi
    local content
    content=$(cat "$template")
    while [[ $# -gt 0 ]]; do
        local key="${1%%=*}"
        local val="${1#*=}"
        local escaped_val
        escaped_val="${val//\\/\\\\}"
        escaped_val="${escaped_val//\$/\\$}"
        escaped_val="${escaped_val//\`/\\\`}"
        escaped_val="${escaped_val//\}/\\\}}"
        content="${content//\{\{${key}\}\}/${escaped_val}}"
        shift
    done
    echo "$content" > "$output"
    log_debug "Rendered template: $template -> $output"
}

vhost_patch_php_block() {
    local vhost_file="$1"
    local fpm_pass="$2"
    local is_ssl="${3:-no}"

    if [[ -z "$fpm_pass" ]]; then
        sed_inplace "$vhost_file" '/PHP_LOCATION_BLOCK/d'
    else
        local php_block=""
        local https_param=""
        [[ "$is_ssl" == "yes" ]] && https_param=$'\n        fastcgi_param HTTPS on;'

        if [[ "$fpm_pass" == unix:* ]]; then
            local sock="${fpm_pass#unix:}"
            php_block="    location ~ [^/]\\.php(/|$) {
        fastcgi_pass unix:${sock};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;${https_param}
        include fastcgi_params;

        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_read_timeout 300;
        fastcgi_intercept_errors on;
    }"
        elif [[ "$fpm_pass" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
            php_block="    location ~ [^/]\\.php(/|$) {
        fastcgi_pass ${fpm_pass};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;${https_param}
        include fastcgi_params;

        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_read_timeout 300;
        fastcgi_intercept_errors on;
    }"
        else
            php_block="    location ~ [^/]\\.php(/|$) {
        fastcgi_pass unix:${fpm_pass};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;${https_param}
        include fastcgi_params;

        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_read_timeout 300;
        fastcgi_intercept_errors on;
    }"
        fi
        local tmp_php_block
        tmp_php_block=$(mktemp)
        printf '%s\n' "$php_block" > "$tmp_php_block"
        sed -i "/PHP_LOCATION_BLOCK/{r $tmp_php_block
d}" "$vhost_file"
        rm -f "$tmp_php_block"
    fi
}

get_php_versions_installed() {
    local -a versions=()
    local dir ver
    for dir in "${PHP_BASE_DIR}"/php*/; do
        if [[ -d "$dir" ]] && [[ -x "${dir}bin/php" ]]; then
            ver=$("${dir}bin/php" -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
            if [[ -n "$ver" ]]; then
                versions+=("$ver")
            fi
        fi
    done
    printf '%s\n' "${versions[@]}" | sort -V
}

get_php_fpm_port() {
    local ver="$1"
    local major minor
    IFS='.' read -r major minor _ <<< "$ver"
    echo "$((PHP_FPM_PORTS_START + major * 10 + minor - 81))"
}

get_php_fpm_sock() {
    local ver="$1"
    echo "${RUN_DIR}/php-fpm/php${ver}.sock"
}

spinner() {
    local pid=$1
    local msg="${2:-Processing...}"
    local spin='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r  ${C_CYAN}[${spin:$i:1}]${C_RESET} ${msg}"
        sleep 0.1
    done
    printf "\r%*s\r" "$(( ${#msg} + 10 ))" ""
}

run_with_spinner() {
    local msg="$1"; shift
    "$@" &>/dev/null &
    local pid=$!
    spinner "$pid" "$msg"
    wait "$pid"
    return $?
}
