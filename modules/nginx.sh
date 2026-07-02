#!/usr/bin/env bash
#
# Pig-NMP - Nginx Module
#

_nginx_get_bin() {
    if [[ -x "${NGINX_DIR}/sbin/nginx" ]]; then
        echo "${NGINX_DIR}/sbin/nginx"
    else
        which nginx 2>/dev/null
    fi
}

nginx_is_installed() {
    [[ -x "${NGINX_DIR}/sbin/nginx" ]] || command -v nginx &>/dev/null
}

nginx_get_version() {
    local bin=$(_nginx_get_bin)
    [[ -x "$bin" ]] && "$bin" -v 2>&1 | grep -oP 'nginx/\K[\d.]+' || echo "unknown"
}

nginx_install_apt() {
    local branch="${1:-stable}"
    require_os
    log_info "Installing Nginx (${branch}) from official APT repository..."

    install_deps curl gnupg2 ca-certificates lsb-release

    local keyring="/usr/share/keyrings/nginx-archive-keyring.gpg"
    curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o "$keyring" 2>/dev/null || {
        log_error "Failed to import Nginx GPG key"; return 1
    }
    chmod 644 "$keyring"

    local repo_line="deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://nginx.org/packages/${OS_ID}/ $(lsb_release -cs) nginx"
    [[ "$branch" == "mainline" ]] && repo_line="deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://nginx.org/packages/mainline/${OS_ID}/ $(lsb_release -cs) nginx"
    echo "$repo_line" > /etc/apt/sources.list.d/nginx.list

    apt-get update -qq 2>&1 | tail -3

    # Stop auto-started nginx to free port 80
    systemctl stop nginx 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx 2>/dev/null

    # Set up symlink structure for consistency
    ensure_dirs "${NGINX_DIR}/sbin"
    ln -sf /usr/sbin/nginx "${NGINX_DIR}/sbin/nginx"

    nginx_setup_config
    systemctl enable nginx &>/dev/null
    systemctl start nginx &>/dev/null

    if is_service_active nginx; then
        log_success "Nginx $(nginx_get_version) installed via APT"
    else
        log_warn "Nginx installed but failed to start"
    fi
}

nginx_install_source() {
    local ver="${1:-}"
    require_os
    install_build_deps

    if [[ -z "$ver" ]]; then
        ver=$(prompt_input "Nginx version" "${NGINX_STABLE_VERSION}")
    fi

    local src_dir="${TMP_DIR}/nginx-${ver}"
    ensure_dirs "$TMP_DIR"

    log_info "Downloading Nginx ${ver}..."
    download_and_extract "https://nginx.org/download/nginx-${ver}.tar.gz" "$src_dir" 1 || {
        log_error "Failed to download Nginx ${ver}"; return 1
    }

    cd "$src_dir" || return 1

    local -a configure_opts=(
        --prefix="${NGINX_DIR}"
        --with-http_ssl_module
        --with-http_v2_module
        --with-http_realip_module
        --with-http_stub_status_module
        --with-http_gzip_static_module
        --with-http_sub_module
        --with-stream
        --with-stream_ssl_module
    )

    log_info "Configuring Nginx ${ver}..."
    ./configure "${configure_opts[@]}" 2>&1 | tee "${LOG_DIR}/nginx-configure.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Nginx configure failed"; cd -; return 1
    fi

    log_info "Compiling Nginx ${ver}..."
    make -j"$(nproc)" 2>&1 | tee "${LOG_DIR}/nginx-make.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Nginx compile failed"; cd -; return 1
    fi

    make install 2>&1 | tee "${LOG_DIR}/nginx-install.log"
    cd - || return 1
    rm -rf "$src_dir"

    nginx_setup_config
    nginx_setup_systemd

    systemctl start nginx &>/dev/null
    is_service_active nginx && log_success "Nginx ${ver} installed and running" || log_warn "Nginx installed but failed to start"
}

nginx_setup_config() {
    ensure_dirs \
        "${NGINX_ETC_DIR}" \
        "${NGINX_SITES_AVAILABLE}" \
        "${NGINX_SITES_ENABLED}" \
        "${NGINX_DIR}/conf" \
        "${LOG_DIR}/nginx"

    # Copy mime.types and fastcgi_params from system if not present
    [[ ! -f "${NGINX_DIR}/conf/mime.types" ]] && cp -n /etc/nginx/mime.types "${NGINX_DIR}/conf/" 2>/dev/null
    [[ ! -f "${NGINX_DIR}/conf/fastcgi_params" ]] && cp -n /etc/nginx/fastcgi_params "${NGINX_DIR}/conf/" 2>/dev/null

    local nginx_conf="${NGINX_ETC_DIR}/nginx.conf"
    if [[ ! -f "$nginx_conf" ]]; then
        render_template "${TEMPLATES_DIR}/nginx/nginx.conf.tpl" "$nginx_conf" \
            NGINX_DIR="${NGINX_DIR}" \
            NGINX_ETC_DIR="${NGINX_ETC_DIR}" \
            LOG_DIR="${LOG_DIR}"
    fi

    # Symlink nginx.conf to the install dir
    ln -sf "$nginx_conf" "${NGINX_DIR}/conf/nginx.conf"

    # Create default site if none exists
    if [[ ! -f "${NGINX_SITES_AVAILABLE}/default.conf" ]]; then
        render_template "${TEMPLATES_DIR}/nginx/default.conf.tpl" "${NGINX_SITES_AVAILABLE}/default.conf" \
            DOMAINS_DIR="${DOMAINS_DIR}"
        ln -sf "${NGINX_SITES_AVAILABLE}/default.conf" "${NGINX_SITES_ENABLED}/default.conf"
    fi
}

nginx_setup_systemd() {
    local service_file="/etc/systemd/system/nginx.service"
    [[ -f "$service_file" ]] && return
    render_template "${TEMPLATES_DIR}/systemd/nginx.service.tpl" "$service_file" \
        NGINX_DIR="${NGINX_DIR}"
    systemctl daemon-reload
    systemctl enable nginx &>/dev/null
}

nginx_install() {
    if nginx_is_installed; then
        log_warn "Nginx is already installed: $(nginx_get_version)"
        confirm "Reinstall?" || return 0
        nginx_uninstall
    fi

    local method
    method=$(prompt_select "Select Nginx installation method:" "APT - Official repository (recommended)" "Source compilation")
    case "$method" in
        *APT*)  nginx_install_apt stable ;;
        *Source*) nginx_install_source ;;
    esac
}

nginx_uninstall() {
    nginx_is_installed || { log_warn "Nginx is not installed"; return 0; }
    confirm "Uninstall Nginx? Configurations will be backed up." || return 0

    # Backup configs
    local backup_dir="${BACKUP_DIR}/nginx-$(date +%Y%m%d%H%M%S)"
    ensure_dirs "$backup_dir"
    cp -a "${NGINX_ETC_DIR}" "$backup_dir/" 2>/dev/null
    log_info "Configs backed up to: ${backup_dir}"

    systemctl stop nginx &>/dev/null
    systemctl disable nginx &>/dev/null

    # Try APT remove
    DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq nginx nginx-common nginx-full 2>/dev/null
    apt-get autoremove -y -qq 2>/dev/null

    rm -rf "${NGINX_DIR}" "${NGINX_ETC_DIR}"
    rm -f /etc/systemd/system/nginx.service
    rm -f /etc/apt/sources.list.d/nginx.list
    systemctl daemon-reload

    log_success "Nginx uninstalled"
}

nginx_default_site_enable() {
    local vhost_file="${NGINX_SITES_AVAILABLE}/default.conf"
    if [[ ! -f "$vhost_file" ]]; then
        ensure_dirs "${NGINX_SITES_AVAILABLE}" "${NGINX_SITES_ENABLED}"
        render_template "${TEMPLATES_DIR}/nginx/default.conf.tpl" "$vhost_file" \
            DOMAINS_DIR="${DOMAINS_DIR}"
    fi
    ln -sf "$vhost_file" "${NGINX_SITES_ENABLED}/default.conf"
    nginx_test_config && nginx_reload
    log_success "Default site enabled"
}

nginx_default_site_disable() {
    rm -f "${NGINX_SITES_ENABLED}/default.conf"
    nginx_test_config && nginx_reload
    log_success "Default site disabled"
}

nginx_default_site_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== Default Site Management ===${C_RESET}"
        if [[ -L "${NGINX_SITES_ENABLED}/default.conf" ]]; then
            echo -e "  Status: ${C_GREEN}enabled${C_RESET}"
        else
            echo -e "  Status: ${C_RED}disabled${C_RESET}"
        fi
        echo ""
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Enable default site"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Disable default site"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice
        case "$choice" in
            1) nginx_default_site_enable ;;
            2) nginx_default_site_disable ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}

nginx_test_config() {
    local bin=$(_nginx_get_bin)
    if "$bin" -t 2>/dev/null; then
        log_success "Nginx configuration test passed"
        return 0
    else
        log_error "Nginx configuration test failed"
        "$bin" -t 2>&1
        return 1
    fi
}

nginx_reload() {
    nginx_test_config && systemctl reload nginx &>/dev/null && log_success "Nginx reloaded"
}

nginx_status() {
    echo -e "\n${HEADER_COLOR}=== Nginx Status ===${C_RESET}"
    if nginx_is_installed; then
        print_status "Nginx" "installed"
        echo -e "  Version: $(nginx_get_version)"
        echo -e "  Binary:  $(_nginx_get_bin)"
        is_service_active nginx && print_status "Service" "running" || print_status "Service" "stopped"
    else
        print_status "Nginx" "not_installed"
    fi
}

nginx_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== Nginx Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install/Reinstall Nginx"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall Nginx"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Default site management"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Test configuration"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Reload configuration"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice
        case "$choice" in
            1) nginx_install ;;
            2) nginx_uninstall ;;
            3) nginx_default_site_menu ;;
            4) nginx_test_config ;;
            5) nginx_reload ;;
            6) nginx_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
