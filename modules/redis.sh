#!/usr/bin/env bash
#
# Pig-NMP - Redis Module
#

source "${CONF_DIR}/versions.conf"

redis_is_installed() {
    [[ -x "${REDIS_DIR}/bin/redis-server" ]] || is_installed redis-server
}

redis_get_version() {
    if [[ -x "${REDIS_DIR}/bin/redis-server" ]]; then
        "${REDIS_DIR}/bin/redis-server" --version 2>&1 | grep -oP 'v=\K[\d.]+'
    elif is_installed redis-server; then
        redis-server --version 2>&1 | grep -oP 'v=\K[\d.]+'
    fi
}

redis_install_method() {
    if [[ -x "${REDIS_DIR}/bin/redis-server" ]] && [[ ! -L "${REDIS_DIR}/bin/redis-server" ]]; then
        echo "source"
    elif is_installed redis-server; then
        echo "apt"
    else
        echo "none"
    fi
}

redis_install() {
    if redis_is_installed; then
        log_warn "Redis is already installed: $(redis_get_version)"
        if ! confirm "Reinstall Redis?"; then
            return 0
        fi
    fi

    require_os

    echo -e "\n${HEADER_COLOR}Select Redis installation method:${C_RESET}" >&2
    echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} APT - Official repository (fast, binary)" >&2
    echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Source compilation (latest version)" >&2
    local install_choice
    read -rp "$(echo -e "${C_CYAN}Enter number [1-2]:${C_RESET} ")" install_choice

    case "$install_choice" in
        1) redis_install_apt ;;
        2) redis_install_source ;;
        *) log_error "Invalid choice"; return 1 ;;
    esac
}

redis_install_apt() {
    require_os

    log_info "Installing Redis from official APT repository..."

    local keyring="/usr/share/keyrings/redis-archive-keyring.gpg"
    rm -f "$keyring"

    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o "$keyring" 2>/dev/null
    chmod 644 "$keyring"

    echo "deb [signed-by=${keyring}] https://packages.redis.io/deb ${OS_CODENAME} main" \
        > /etc/apt/sources.list.d/redis.list

    log_info "Running apt-get update..."
    apt-get update -qq 2>&1 | tail -5 || {
        log_warn "apt-get update had warnings, continuing..."
    }

    log_info "Installing redis-server..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server 2>&1 | tail -10

    if ! is_installed redis-server; then
        log_error "Failed to install Redis via APT"
        log_error "You can try source compilation instead"
        return 1
    fi

    local apt_redis_bin
    apt_redis_bin=$(which redis-server 2>/dev/null || echo "/usr/bin/redis-server")
    local apt_redis_cli
    apt_redis_cli=$(which redis-cli 2>/dev/null || echo "/usr/bin/redis-cli")

    ensure_dirs "${REDIS_DIR}/bin"
    ln -sf "$apt_redis_bin" "${REDIS_DIR}/bin/redis-server"
    ln -sf "$apt_redis_cli" "${REDIS_DIR}/bin/redis-cli"

    redis_setup_config
    redis_patch_apt_systemd

    id redis &>/dev/null || useradd -r -s /sbin/nologin redis
    ensure_dirs "${REDIS_DATA_DIR}"
    chown -R redis:redis "${REDIS_DATA_DIR}"

    systemctl enable redis-server &>/dev/null
    systemctl restart redis-server &>/dev/null

    if is_service_active redis-server; then
        log_success "Redis installed via APT and running"
    else
        log_warn "Redis installed but service failed to start"
        log_warn "Check: journalctl -u redis-server -n 20"
    fi
}

redis_patch_apt_systemd() {
    local service_file="/etc/systemd/system/redis.service"
    local apt_conf="${REDIS_ETC_DIR}/redis.conf"

    if [[ -f "$apt_conf" ]] && [[ -f /etc/redis/redis.conf ]]; then
        sed_inplace /etc/redis/redis.conf "s|^supervised .*|supervised systemd|"
    fi

    if [[ ! -f "$service_file" ]]; then
        render_template "${TEMPLATES_DIR}/systemd/redis.service.tpl" "$service_file" \
            REDIS_BIN="${REDIS_DIR}/bin/redis-server" \
            REDIS_CLI="${REDIS_DIR}/bin/redis-cli" \
            REDIS_CONF="${REDIS_ETC_DIR}/redis.conf" \
            REDIS_PID="${RUN_DIR}/redis.pid" \
            RUN_DIR="${RUN_DIR}"
        systemctl daemon-reload
    fi

    if systemctl list-unit-files redis-server.service &>/dev/null; then
        systemctl stop redis-server &>/dev/null
        systemctl disable redis-server &>/dev/null
    fi
}

redis_install_source() {
    require_os
    install_build_deps
    install_deps tcl

    echo -e "\n${HEADER_COLOR}Select Redis version:${C_RESET}" >&2
    echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Redis ${REDIS_LATEST_VERSION} (latest)" >&2
    echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Redis ${REDIS_STABLE_VERSION} (stable)" >&2
    local ver_choice
    read -rp "$(echo -e "${C_CYAN}Enter number [1-2]:${C_RESET} ")" ver_choice
    local version="${REDIS_STABLE_VERSION}"
    case "$ver_choice" in
        1) version="${REDIS_LATEST_VERSION}" ;;
        2) version="${REDIS_STABLE_VERSION}" ;;
    esac

    local url
    local src_dir="${TMP_DIR}/redis-${version}"

    local -a mirrors=(
        "https://download.redis.io/releases/redis-${version}.tar.gz"
        "https://mirrors.huaweicloud.com/redis/redis-${version}.tar.gz"
    )

    log_info "Installing Redis ${version} from source..."
    ensure_dirs "$TMP_DIR"

    local downloaded=false
    for url in "${mirrors[@]}"; do
        log_info "Trying: ${url}"
        if download_and_extract "$url" "$src_dir" 1; then
            downloaded=true
            break
        fi
        log_warn "Mirror failed, trying next..."
    done

    if [[ "$downloaded" != "true" ]]; then
        log_error "Failed to download Redis ${version} from all mirrors"
        return 1
    fi

    cd "$src_dir" || return 1

    local make_log="${LOG_DIR}/redis-${version}-make.log"
    ensure_dirs "${LOG_DIR}"

    log_info "Compiling Redis ${version}..."
    make -j"$(nproc)" 2>&1 | tee "$make_log"
    local make_ret=${PIPESTATUS[0]}

    if [[ $make_ret -ne 0 ]]; then
        log_error "Redis compile failed (exit code: ${make_ret}). Full log: ${make_log}"
        cd - || return 1
        return 1
    fi

    log_info "Installing Redis ${version}..."
    make PREFIX="${REDIS_DIR}" install 2>&1 | tail -10
    local install_ret=${PIPESTATUS[0]}

    if [[ $install_ret -ne 0 ]]; then
        log_error "Redis install failed (exit code: ${install_ret})"
        cd - || return 1
        return 1
    fi

    cd - || return 1
    rm -rf "$src_dir"

    redis_setup_config
    redis_setup_systemd

    id redis &>/dev/null || useradd -r -s /sbin/nologin redis
    ensure_dirs "${REDIS_DATA_DIR}"
    chown -R redis:redis "${REDIS_DATA_DIR}"

    systemctl start redis &>/dev/null
    if is_service_active redis; then
        log_success "Redis ${version} installed and running"
    else
        log_warn "Redis installed but service failed to start"
    fi
}

redis_setup_config() {
    ensure_dirs "${REDIS_ETC_DIR}" "${REDIS_DATA_DIR}" "${LOG_DIR}/redis"

    local conf="${REDIS_ETC_DIR}/redis.conf"
    if [[ ! -f "$conf" ]]; then
        local maxmem=$((SYSCTL_MEM * 20 / 100 / 1024))
        [[ -z "$SYSCTL_MEM" || "$SYSCTL_MEM" -eq 0 ]] && maxmem=128
        cat > "$conf" << EOF
bind 127.0.0.1
port 6379
daemonize no
pidfile ${RUN_DIR}/redis.pid
logfile ${LOG_DIR}/redis/redis.log
dir ${REDIS_DATA_DIR}
dbfilename dump.rdb
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
maxmemory ${maxmem}mb
maxmemory-policy allkeys-lru
tcp-backlog 511
timeout 300
tcp-keepalive 60
loglevel notice
databases 16
protected-mode yes
EOF
        chown redis:redis "$conf" 2>/dev/null
    fi
}

redis_setup_systemd() {
    local service_file="/etc/systemd/system/redis.service"
    if [[ ! -f "$service_file" ]]; then
        render_template "${TEMPLATES_DIR}/systemd/redis.service.tpl" "$service_file" \
            REDIS_BIN="${REDIS_DIR}/bin/redis-server" \
            REDIS_CLI="${REDIS_DIR}/bin/redis-cli" \
            REDIS_CONF="${REDIS_ETC_DIR}/redis.conf" \
            REDIS_PID="${RUN_DIR}/redis.pid" \
            RUN_DIR="${RUN_DIR}"
        systemctl daemon-reload
        systemctl enable redis &>/dev/null
    fi
}

redis_set_password() {
    local password
    prompt_password "Set Redis password (leave empty to disable)" password
    local conf="${REDIS_ETC_DIR}/redis.conf"
    if [[ -z "$password" ]]; then
        sed_inplace "$conf" "/^requirepass/d"
        log_success "Redis password removed"
    else
        sed_inplace "$conf" "/^requirepass/d"
        echo "requirepass ${password}" >> "$conf"
        log_success "Redis password set"
    fi
    systemctl restart redis redis-server &>/dev/null
}

redis_uninstall() {
    if ! redis_is_installed; then
        log_warn "Redis is not installed"
        return 0
    fi

    if ! confirm "Uninstall Redis?"; then return 0; fi

    systemctl stop redis redis-server &>/dev/null
    systemctl disable redis redis-server &>/dev/null

    local method
    method=$(redis_install_method)
    if [[ "$method" == "apt" ]]; then
        apt_remove redis-server 2>/dev/null
    fi

    rm -rf "${REDIS_DIR}"
    rm -rf "${REDIS_ETC_DIR}"
    rm -f /etc/systemd/system/redis.service
    rm -f /etc/apt/sources.list.d/redis.list
    systemctl daemon-reload

    if confirm "Remove Redis data?"; then
        rm -rf "${REDIS_DATA_DIR}"
    fi

    log_success "Redis uninstalled"
}

redis_status() {
    echo -e "\n${HEADER_COLOR}=== Redis Status ===${C_RESET}"
    print_status "Redis" "$(redis_is_installed && echo 'installed' || echo 'not_installed')"
    if redis_is_installed; then
        print_status "Version" "$(redis_get_version)"
        local method
        method=$(redis_install_method)
        print_status "Method" "[${method}]"
        print_status "Service" "$(is_service_active redis && echo 'running' || (is_service_active redis-server && echo 'running' || echo 'stopped'))"
        print_status "Port 6379" "$(port_in_use 6379 && echo 'in_use' || echo 'free')"
        if is_service_active redis || is_service_active redis-server; then
            "${REDIS_DIR}/bin/redis-cli" info server 2>/dev/null | grep -E "redis_version|used_memory_human|connected_clients" | while read line; do
                echo "  $line"
            done
        fi
    fi
}

redis_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== Redis Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install Redis"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall Redis"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Start/Stop/Restart"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Set password"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) redis_install ;;
            2) redis_uninstall ;;
            3)
                local action
                action=$(prompt_select "Service action:" "Start" "Stop" "Restart")
                case "$action" in
                    Start)   systemctl start redis redis-server &>/dev/null ;;
                    Stop)    systemctl stop redis redis-server &>/dev/null ;;
                    Restart) systemctl restart redis redis-server &>/dev/null ;;
                esac
                ;;
            4) redis_set_password ;;
            5) redis_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
