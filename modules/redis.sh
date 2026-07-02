#!/usr/bin/env bash
#
# Pig-NMP - Redis Module
#

redis_is_installed() {
    [[ -x "${REDIS_DIR}/bin/redis-server" ]] || command -v redis-server &>/dev/null
}

redis_get_version() {
    local bin="${REDIS_DIR}/bin/redis-server"
    [[ -x "$bin" ]] || bin=$(which redis-server 2>/dev/null)
    [[ -x "$bin" ]] && "$bin" --version 2>&1 | grep -oP 'v=\K[\d.]+' | head -1 || echo "unknown"
}

redis_install_method() {
    [[ -x "${REDIS_DIR}/bin/redis-server" ]] && echo "source" || echo "apt"
}

redis_install() {
    if redis_is_installed; then
        log_warn "Redis is already installed: $(redis_get_version)"
        confirm "Reinstall?" || return 0
        redis_uninstall
    fi

    local method
    method=$(prompt_select "Select Redis installation method:" "APT - Official repository" "Source compilation")
    case "$method" in
        *APT*)    redis_install_apt ;;
        *Source*) redis_install_source ;;
    esac
}

redis_install_apt() {
    require_os
    log_info "Installing Redis from official APT repository..."

    install_deps curl gpg

    local keyring="/usr/share/keyrings/redis-archive-keyring.gpg"
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o "$keyring" 2>/dev/null || {
        log_error "Failed to import Redis GPG key"; return 1
    }
    chmod 644 "$keyring"

    echo "deb [signed-by=${keyring}] https://packages.redis.io/deb $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/redis.list

    apt-get update -qq 2>&1 | tail -3
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq redis-server 2>&1 | tail -5

    # Set up symlink structure
    ensure_dirs "${REDIS_DIR}/bin"
    ln -sf "$(which redis-server)" "${REDIS_DIR}/bin/redis-server"
    ln -sf "$(which redis-cli)" "${REDIS_DIR}/bin/redis-cli"

    redis_setup_config
    systemctl enable redis-server &>/dev/null
    systemctl start redis-server &>/dev/null

    is_service_active redis-server && log_success "Redis $(redis_get_version) installed via APT" || log_warn "Redis installed but failed to start"
}

redis_install_source() {
    local ver="${1:-}"
    require_os
    install_build_deps

    if [[ -z "$ver" ]]; then
        ver=$(prompt_input "Redis version" "${REDIS_STABLE_VERSION}")
    fi

    local src_dir="${TMP_DIR}/redis-${ver}"
    ensure_dirs "$TMP_DIR"

    log_info "Downloading Redis ${ver}..."
    download_and_extract "https://download.redis.io/releases/redis-${ver}.tar.gz" "$src_dir" 1 || {
        log_error "Failed to download Redis ${ver}"; return 1
    }

    cd "$src_dir" || return 1

    log_info "Compiling Redis ${ver}..."
    make -j"$(nproc)" 2>&1 | tee "${LOG_DIR}/redis-make.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Redis compile failed"; cd -; return 1
    fi

    make install PREFIX="${REDIS_DIR}" 2>&1 | tee "${LOG_DIR}/redis-install.log"
    cd - || return 1
    rm -rf "$src_dir"

    redis_setup_config
    redis_setup_systemd

    systemctl start redis &>/dev/null
    is_service_active redis && log_success "Redis ${ver} installed and running" || log_warn "Redis installed but failed to start"
}

redis_setup_config() {
    local conf_dir="${REDIS_ETC_DIR}"
    ensure_dirs "$conf_dir"

    local conf_file="${conf_dir}/redis.conf"
    local maxmem_bytes=${SYSCTL_MEM:-1048576}
    local maxmem=$(( maxmem_bytes / 5 ))  # 20% of RAM
    local maxmem_human="$(( maxmem / 1024 ))mb"

    local requirepass=""
    if [[ -f "${conf_dir}/.redis_password" ]]; then
        requirepass=$(cat "${conf_dir}/.redis_password")
    fi

    cat > "$conf_file" << EOF
bind 127.0.0.1
port 6379
daemonize no
supervised systemd

dir ${REDIS_DATA_DIR:-/var/lib/redis}
dbfilename dump.rdb
save 900 1
save 300 10
save 60 10000

maxmemory ${maxmem_human}
maxmemory-policy allkeys-lru

appendonly yes
appendfilename "appendonly.aof"

loglevel notice
logfile ${LOG_DIR}/redis/redis.log
EOF

    [[ -n "$requirepass" ]] && echo "requirepass ${requirepass}" >> "$conf_file"

    ensure_dirs "${REDIS_DATA_DIR:-/var/lib/redis}"
}

redis_setup_systemd() {
    local service_file="/etc/systemd/system/redis.service"
    [[ -f "$service_file" ]] && return

    render_template "${TEMPLATES_DIR}/systemd/redis.service.tpl" "$service_file" \
        REDIS_DIR="${REDIS_DIR}" REDIS_ETC_DIR="${REDIS_ETC_DIR}" LOG_DIR="${LOG_DIR}"
    systemctl daemon-reload
    systemctl enable redis &>/dev/null
}

redis_set_password() {
    local conf_file="${REDIS_ETC_DIR}/redis.conf"
    [[ ! -f "$conf_file" ]] && { log_error "Redis config not found"; return 1; }

    local new_pass
    prompt_password "New Redis password (empty to remove)" new_pass

    if [[ -z "$new_pass" ]]; then
        sed_inplace "$conf_file" "/^requirepass /d"
        rm -f "${REDIS_ETC_DIR}/.redis_password"
        log_success "Redis password removed"
    else
        if grep -q "^requirepass" "$conf_file"; then
            sed_inplace "$conf_file" "s/^requirepass .*/requirepass ${new_pass}/"
        else
            echo "requirepass ${new_pass}" >> "$conf_file"
        fi
        echo "$new_pass" > "${REDIS_ETC_DIR}/.redis_password"
        chmod 600 "${REDIS_ETC_DIR}/.redis_password"
        log_success "Redis password updated"
    fi

    systemctl restart redis 2>/dev/null || systemctl restart redis-server 2>/dev/null
}

redis_uninstall() {
    redis_is_installed || { log_warn "Redis is not installed"; return 0; }
    confirm "Uninstall Redis?" || return 0

    systemctl stop redis redis-server 2>/dev/null || true
    systemctl disable redis redis-server 2>/dev/null || true

    DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq redis-server redis-tools 2>/dev/null
    apt-get autoremove -y -qq 2>/dev/null

    rm -rf "${REDIS_DIR}" "${REDIS_ETC_DIR}" "${REDIS_DATA_DIR}"
    rm -f /etc/systemd/system/redis.service /etc/apt/sources.list.d/redis.list
    systemctl daemon-reload

    log_success "Redis uninstalled"
}

redis_status() {
    echo -e "\n${HEADER_COLOR}=== Redis Status ===${C_RESET}"
    if redis_is_installed; then
        print_status "Redis" "installed"
        echo -e "  Version: $(redis_get_version)"
        echo -e "  Method:  $(redis_install_method)"
        (is_service_active redis || is_service_active redis-server) && print_status "Service" "running" || print_status "Service" "stopped"
    else
        print_status "Redis" "not_installed"
    fi
}

redis_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== Redis Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install Redis"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall Redis"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Set/Remove password"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice
        case "$choice" in
            1) redis_install ;;
            2) redis_uninstall ;;
            3) redis_set_password ;;
            4) redis_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
