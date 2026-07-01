#!/usr/bin/env bash
#
# Pig-NMP - Memcached Module
#

source "${CONF_DIR}/versions.conf"

memcached_is_installed() {
    [[ -x "${MEMCACHED_DIR}/bin/memcached" ]] || is_installed memcached
}

memcached_get_version() {
    if [[ -x "${MEMCACHED_DIR}/bin/memcached" ]]; then
        "${MEMCACHED_DIR}/bin/memcached" --version 2>&1 | grep -oP '[\d.]+'
    elif is_installed memcached; then
        memcached --version 2>&1 | grep -oP '[\d.]+'
    fi
}

memcached_install() {
    if memcached_is_installed; then
        log_warn "Memcached is already installed: $(memcached_get_version)"
        if ! confirm "Reinstall Memcached?"; then
            return 0
        fi
    fi

    require_os
    # Memcached only needs a minimal set of build tools, not the full PHP/Nginx
    # build dependency set pulled in by install_build_deps.
    install_deps build-essential autoconf libevent-dev

    local version="${1:-$MEMCACHED_VERSION}"
    local url="https://memcached.org/files/memcached-${version}.tar.gz"
    local src_dir="${TMP_DIR}/memcached-${version}"

    log_info "Installing Memcached ${version} from source..."
    ensure_dirs "$TMP_DIR"

    if ! download_and_extract "$url" "$src_dir" 1; then
        log_error "Failed to download Memcached ${version}"
        return 1
    fi

    cd "$src_dir" || return 1

    log_info "Compiling Memcached ${version}..."
    ./configure --prefix="${MEMCACHED_DIR}" &>/dev/null || {
        log_error "Memcached configure failed"
        cd - || return 1
        return 1
    }

    make -j"$(nproc)" &>/dev/null || {
        log_error "Memcached compile failed"
        cd - || return 1
        return 1
    }

    make install &>/dev/null || {
        log_error "Memcached install failed"
        cd - || return 1
        return 1
    }

    cd - || return 1
    rm -rf "$src_dir"

    memcached_setup_config
    memcached_setup_systemd

    id memcached &>/dev/null || useradd -r -s /sbin/nologin memcached

    systemctl start memcached &>/dev/null
    if is_service_active memcached; then
        log_success "Memcached ${version} installed and running"
    else
        log_warn "Memcached installed but service failed to start"
    fi
}

memcached_setup_config() {
    ensure_dirs "${MEMCACHED_ETC_DIR}" "${LOG_DIR}/memcached"

    local conf="${MEMCACHED_ETC_DIR}/memcached.conf"
    if [[ ! -f "$conf" ]]; then
        local maxmem=$((SYSCTL_MEM * 10 / 100 / 1024))
        [[ -z "$SYSCTL_MEM" || "$SYSCTL_MEM" -eq 0 ]] && maxmem=64
        cat > "$conf" << EOF
-l 127.0.0.1
-p 11211
-U 11211
-m ${maxmem}
-c 1024
-u memcached
-P ${RUN_DIR}/memcached.pid
-vv
EOF
    fi
}

memcached_setup_systemd() {
    local service_file="/etc/systemd/system/memcached.service"
    if [[ ! -f "$service_file" ]]; then
        render_template "${TEMPLATES_DIR}/systemd/memcached.service.tpl" "$service_file" \
            MEMCACHED_BIN="${MEMCACHED_DIR}/bin/memcached" \
            MEMCACHED_CONF="${MEMCACHED_ETC_DIR}/memcached.conf" \
            MEMCACHED_PID="${RUN_DIR}/memcached.pid"
        systemctl daemon-reload
        systemctl enable memcached &>/dev/null
    fi
}

memcached_uninstall() {
    if ! memcached_is_installed; then
        log_warn "Memcached is not installed"
        return 0
    fi

    if ! confirm "Uninstall Memcached?"; then return 0; fi

    systemctl stop memcached &>/dev/null
    systemctl disable memcached &>/dev/null

    rm -rf "${MEMCACHED_DIR}"
    rm -rf "${MEMCACHED_ETC_DIR}"
    rm -f /etc/systemd/system/memcached.service
    systemctl daemon-reload

    log_success "Memcached uninstalled"
}

memcached_status() {
    echo -e "\n${HEADER_COLOR}=== Memcached Status ===${C_RESET}"
    print_status "Memcached" "$(memcached_is_installed && echo 'installed' || echo 'not_installed')"
    if memcached_is_installed; then
        print_status "Version" "$(memcached_get_version)"
        print_status "Service" "$(is_service_active memcached && echo 'running' || echo 'stopped')"
        print_status "Port 11211" "$(port_in_use 11211 && echo 'in_use' || echo 'free')"
    fi
}

memcached_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== Memcached Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install Memcached"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall Memcached"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Start/Stop/Restart"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) memcached_install ;;
            2) memcached_uninstall ;;
            3)
                local action
                action=$(prompt_select "Service action:" "Start" "Stop" "Restart")
                case "$action" in
                    Start)   systemctl start memcached ;;
                    Stop)    systemctl stop memcached ;;
                    Restart) systemctl restart memcached ;;
                esac
                ;;
            4) memcached_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
