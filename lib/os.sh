#!/usr/bin/env bash
#
# Pig-NMP - OS Detection & System Management
#

OS_ID=""
OS_VERSION_ID=""
OS_CODENAME=""
OS_FAMILY=""

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="${ID:-}"
        OS_VERSION_ID="${VERSION_ID:-}"
        OS_CODENAME="${VERSION_CODENAME:-}"
    elif [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release
        OS_ID="${DISTRIB_ID,,}"
        OS_VERSION_ID="$DISTRIB_RELEASE"
        OS_CODENAME="${DISTRIB_CODENAME,,}"
    fi

    case "$OS_ID" in
        ubuntu|debian|linuxmint) OS_FAMILY="debian" ;;
        centos|rhel|rocky|almalinux|fedora) OS_FAMILY="rhel" ;;
        *) OS_FAMILY="unknown" ;;
    esac

    log_debug "OS: ${OS_ID} ${OS_VERSION_ID} (${OS_CODENAME}) [${OS_FAMILY}]"
}

require_os() {
    detect_os
    [[ "$OS_FAMILY" != "debian" ]] && die "This component requires Debian/Ubuntu. Detected: ${OS_ID}"
}

_pkg_is_installed() {
    local pkg="$1"
    local status
    status=$(dpkg -s "$pkg" 2>/dev/null | grep '^Status:')
    [[ "$status" == *"install ok installed"* ]]
}

install_deps() {
    local pkg
    for pkg in "$@"; do
        if ! _pkg_is_installed "$pkg"; then
            log_info "Installing ${pkg}..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" 2>/dev/null || {
                log_warn "Failed to install ${pkg}"
                return 1
            }
        fi
    done
}

install_build_deps() {
    local -a deps=(
        build-essential autoconf automake libtool cmake pkg-config
        bison re2c zlib1g-dev libxml2-dev libssl-dev libcurl4-openssl-dev
        libpng-dev libjpeg-dev libwebp-dev libfreetype6-dev
        libonig-dev libzip-dev libbz2-dev libsqlite3-dev libgmp-dev
        libreadline-dev libffi-dev libicu-dev libxslt1-dev
        libldap2-dev libsodium-dev
    )
    install_deps "${deps[@]}"
}

apt_remove() {
    local pkg
    for pkg in "$@"; do
        if _pkg_is_installed "$pkg"; then
            DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "$pkg" 2>/dev/null
        fi
    done
}

setup_swap() {
    local swap_total
    swap_total=$(awk '/SwapTotal/{print $2}' /proc/meminfo 2>/dev/null)
    swap_total=${swap_total:-0}

    if (( swap_total > 0 )); then
        log_info "Swap already configured ($(( swap_total / 1024 ))MB)"
        return 0
    fi

    if (( SYSCTL_MEM < 2097152 )); then
        log_info "Low memory detected, creating 2GB swap..."
        local swapfile="/swapfile"
        fallocate -l 2G "$swapfile" 2>/dev/null || dd if=/dev/zero of="$swapfile" bs=1M count=2048 2>/dev/null
        chmod 600 "$swapfile"
        mkswap "$swapfile" &>/dev/null
        swapon "$swapfile" &>/dev/null
        grep -q "$swapfile" /etc/fstab || echo "$swapfile none swap sw 0 0" >> /etc/fstab
        log_success "Swap created: 2GB"
    fi
}

optimize_system() {
    log_info "Optimizing system settings..."

    local sysctl_file="/etc/sysctl.d/99-pig-nmp.conf"
    cat > "$sysctl_file" << 'SYSCTL'
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.netdev_max_backlog = 65535
vm.swappiness = 10
fs.file-max = 655350
fs.inotify.max_user_watches = 524288
SYSCTL
    sysctl -p "$sysctl_file" &>/dev/null

    local limits_file="/etc/security/limits.d/99-pig-nmp.conf"
    cat > "$limits_file" << 'LIMITS'
* soft nofile 655350
* hard nofile 655350
* soft nproc 655350
* hard nproc 655350
www-data soft nofile 655350
www-data hard nofile 655350
LIMITS

    setup_swap
    setup_logrotate
    log_success "System optimized"
}

setup_logrotate() {
    local logrotate_file="/etc/logrotate.d/pig-nmp"
    cat > "$logrotate_file" << 'LOGROTATE'
/var/log/pig-nmp/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 www-data www-data
}
LOGROTATE
}
