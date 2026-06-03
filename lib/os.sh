#!/usr/bin/env bash
#
# Pig-NMP - OS Detection & Dependency Management
#

source "${LIB_DIR}/common.sh"

OS_ID=""
OS_VERSION=""
OS_CODENAME=""
OS_ARCH=""

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo unknown)}"
    elif [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release
        OS_ID="${DISTRIB_ID,,:-unknown}"
        OS_VERSION="${DISTRIB_RELEASE:-unknown}"
        OS_CODENAME="${DISTRIB_CODENAME:-unknown}"
    elif [[ -f /etc/debian_version ]]; then
        OS_ID="debian"
        OS_VERSION=$(cat /etc/debian_version | cut -d. -f1)
        OS_CODENAME=$(lsb_release -cs 2>/dev/null || echo unknown)
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_CODENAME="unknown"
    fi

    OS_ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)

    export OS_ID OS_VERSION OS_CODENAME OS_ARCH

    log_debug "Detected OS: ${OS_ID} ${OS_VERSION} (${OS_CODENAME}) arch=${OS_ARCH}"
}

require_os() {
    if [[ -z "$OS_ID" ]]; then
        detect_os
    fi
    case "$OS_ID" in
        debian|ubuntu|linuxmint|pop)
            return 0
            ;;
        *)
            die "Unsupported OS: ${OS_ID}. This script requires Debian/Ubuntu."
            ;;
    esac
}

_pkg_is_installed() {
    dpkg -s "$1" &>/dev/null
}

install_deps() {
    local -a pkgs=("$@")
    local -a missing=()

    for pkg in "${pkgs[@]}"; do
        if ! _pkg_is_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_debug "All packages already installed"
        return 0
    fi

    log_info "Installing dependencies: ${missing[*]}"
    apt-get update -qq 2>/dev/null

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" 2>/dev/null || true

    local -a still_missing=()
    for pkg in "${missing[@]}"; do
        if ! _pkg_is_installed "$pkg"; then
            still_missing+=("$pkg")
        fi
    done

    if [[ ${#still_missing[@]} -eq 0 ]]; then
        log_success "Dependencies installed"
    else
        log_warn "Some packages could not be installed: ${still_missing[*]}"
        log_warn "This may not be critical - continuing..."
    fi
}

install_build_deps() {
    local -a pkgs=(
        build-essential
        autoconf
        automake
        libtool
        pkg-config
        cmake
        git
        wget
        curl
        ca-certificates
        gnupg
        lsb-release
        software-properties-common
        apt-transport-https
        libssl-dev
        zlib1g-dev
        libpcre3-dev
        libargon2-dev
        libsodium-dev
        libcurl4-openssl-dev
        libxml2-dev
        libsqlite3-dev
        libonig-dev
        libzip-dev
        libbz2-dev
        libreadline-dev
        libicu-dev
        libgd-dev
        libwebp-dev
        libjpeg-dev
        libpng-dev
        libxpm-dev
        libfreetype6-dev
        libgmp-dev
        libldap2-dev
        libpq-dev
        libmagickwand-dev
        libmagickcore-dev
        imagemagick
        libmemcached-dev
        libyaml-dev
        libxslt1-dev
    )
    install_deps "${pkgs[@]}"

    local -a optional_pkgs=(
        unixodbc-dev
        libenchant-2-dev
        libpcre2-dev
    )
    for pkg in "${optional_pkgs[@]}"; do
        if ! dpkg -l "$pkg" &>/dev/null 2>&1 | grep -q '^ii'; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" 2>/dev/null || \
                log_warn "Optional package ${pkg} not available, skipping"
        fi
    done
}

add_apt_key() {
    local url="$1"
    local keyring="$2"
    rm -f "$keyring"
    curl -fsSL "$url" | gpg --dearmor -o "$keyring"
    chmod 644 "$keyring"
}

add_apt_repo() {
    local repo_line="$1"
    local keyring="$2"
    echo "$repo_line" > /etc/apt/sources.list.d/"$(echo "$repo_line" | awk '{print $3}')".list
    apt-get update -qq 2>/dev/null
}

apt_install() {
    local -a pkgs=("$@")
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}" 2>/dev/null
}

apt_remove() {
    local -a pkgs=("$@")
    DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "${pkgs[@]}" 2>/dev/null
    apt-get autoremove -y -qq 2>/dev/null
}

set_locale() {
    install_deps locales
    local locale="${1:-en_US.UTF-8}"
    if ! locale -a 2>/dev/null | grep -qi "${locale//_/}"; then
        sed_inplace /etc/locale.gen "s/# ${locale}/${locale}/"
        locale-gen "$locale" &>/dev/null
    fi
    export LC_ALL="$locale"
    export LANG="$locale"
}

setup_swap() {
    local size="${1:-2G}"
    if swapon --show | grep -q pv; then
        log_info "Swap already exists"
        return 0
    fi
    if [[ $(awk '/MemTotal/{print $2}' /proc/meminfo) -lt 2000000 ]]; then
        log_info "Creating swap file (${size})..."
        fallocate -l "$size" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile &>/dev/null
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        sysctl vm.swappiness=10 &>/dev/null
        log_success "Swap created"
    fi
}

optimize_system() {
    local -a sysctl_conf=(
        "net.core.somaxconn=65535"
        "net.ipv4.tcp_max_syn_backlog=65535"
        "net.ipv4.tcp_tw_reuse=1"
        "net.ipv4.ip_local_port_range=1024 65535"
        "fs.file-max=1048576"
        "vm.overcommit_memory=1"
        "vm.swappiness=10"
    )

    for conf in "${sysctl_conf[@]}"; do
        local key="${conf%%=*}"
        local value="${conf#*=}"
        if grep -q "^${key}" /etc/sysctl.conf 2>/dev/null; then
            local current
            current=$(grep "^${key}" /etc/sysctl.conf 2>/dev/null | head -1)
            if [[ "$current" != "$conf" ]]; then
                sed_inplace /etc/sysctl.conf "s|^${key}.*|${conf}|"
                log_debug "Updated sysctl: ${conf}"
            fi
        else
            echo "$conf" >> /etc/sysctl.conf
        fi
    done
    sysctl -p &>/dev/null

    cat > /etc/security/limits.d/pig-nmp.conf << EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
root soft nofile 1048576
root hard nofile 1048576
EOF

    setup_logrotate

    log_success "System optimized"
}

setup_logrotate() {
    local logrotate_conf="/etc/logrotate.d/pig-nmp"
    if [[ -f "$logrotate_conf" ]]; then
        return 0
    fi
    cat > "$logrotate_conf" << EOF
${LOG_DIR}/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
    sharedscripts
    postrotate
        [ -f ${RUN_DIR}/nginx.pid ] && kill -USR1 \$(cat ${RUN_DIR}/nginx.pid) 2>/dev/null || true
    endscript
}

${LOG_DIR}/php*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
    sharedscripts
    postrotate
        systemctl reload php*-fpm 2>/dev/null || true
    endscript
}

${LOG_DIR}/mysql/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 mysql adm
    sharedscripts
    postrotate
        [ -f ${RUN_DIR}/mysqld.pid ] && mysqladmin flush-logs 2>/dev/null || true
    endscript
}

${LOG_DIR}/redis/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 redis redis
}

${LOG_DIR}/memcached/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 memcache memcache
}

${LOG_DIR}/vsftpd/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 www-data www-data
}
EOF
    log_info "Logrotate configured for Pig-NMP services"
}

