#!/usr/bin/env bash
#
# Pig-NMP - System Manager / Status Dashboard
#

manager_system_status() {
    print_banner
    echo -e "${HEADER_COLOR}=== System Status ===${C_RESET}\n"

    local os_info="${OS_ID} ${OS_VERSION} (${OS_CODENAME})"
    local uptime_info
    uptime_info=$(uptime -p 2>/dev/null || echo "N/A")
    local load
    load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo "N/A")
    local mem_total mem_used mem_free mem_cached
    mem_total=$(awk '/MemTotal/{printf "%.0fMB", $2/1024}' /proc/meminfo 2>/dev/null)
    mem_used=$(awk '/MemAvailable/{printf "%.0fMB", ($2)/1024}' /proc/meminfo 2>/dev/null)
    mem_free=$(free -m 2>/dev/null | awk '/Mem:/{print $4"MB"}')
    local disk_info
    disk_info=$(df -h / 2>/dev/null | awk 'NR==2{print $2" total, "$3" used, "$4" free ("$5" used)"}')

    printf "  %-18s %s\n" "OS:" "$os_info"
    printf "  %-18s %s\n" "Uptime:" "$uptime_info"
    printf "  %-18s %s\n" "Load:" "$load"
    printf "  %-18s %s\n" "CPU Cores:" "$CPU_CORES"
    printf "  %-18s %s\n" "Memory:" "${mem_total} (Free: ${mem_free})"
    printf "  %-18s %s\n" "Disk (/):" "$disk_info"
    printf "  %-18s %s\n" "Server IP:" "$(get_ip)"
}

manager_services_status() {
    echo -e "\n${HEADER_COLOR}=== Services Status ===${C_RESET}\n"

    print_status "Nginx" "$(nginx_is_installed && (is_service_active nginx && echo 'running' || echo 'stopped') || echo 'not_installed')"

    local versions
    versions=$(get_php_versions_installed)
    if [[ -n "$versions" ]]; then
        while IFS= read -r ver; do
            print_status "PHP ${ver} FPM" "$(is_service_active php${ver}-fpm && echo 'running' || echo 'stopped')"
        done <<< "$versions"
    else
        print_status "PHP" "not_installed"
    fi

    print_status "MySQL/MariaDB" "$(mysql_is_installed && (is_service_active mysql && echo 'running' || (is_service_active mariadb && echo 'running' || echo 'stopped')) || echo 'not_installed')"
    print_status "Redis" "$(redis_is_installed && (is_service_active redis && echo 'running' || echo 'stopped') || echo 'not_installed')"
    print_status "Memcached" "$(memcached_is_installed && (is_service_active memcached && echo 'running' || echo 'stopped') || echo 'not_installed')"
    print_status "vsftpd" "$(ftp_is_installed && (is_service_active vsftpd && echo 'running' || echo 'stopped') || echo 'not_installed')"
    print_status "UFW Firewall" "$(firewall_is_active && echo 'active' || (firewall_is_installed && echo 'inactive' || echo 'not_installed'))"
}

manager_ports_status() {
    echo -e "\n${HEADER_COLOR}=== Port Status ===${C_RESET}\n"

    local -a port_map=(
        "22:SSH"
        "80:HTTP (Nginx)"
        "443:HTTPS (Nginx)"
        "21:FTP"
        "3306:MySQL/MariaDB"
        "6379:Redis"
        "11211:Memcached"
    )

    local versions
    versions=$(get_php_versions_installed)
    if [[ -n "$versions" ]]; then
        while IFS= read -r ver; do
            local php_port
            php_port=$(get_php_fpm_port "$ver")
            port_map+=("${php_port}:PHP-FPM ${ver}")
        done <<< "$versions"
    fi

    printf "  %-8s %-20s %s\n" "Port" "Service" "Status"
    printf "  %s\n" "$(printf '%.0s-' {1..50})"
    for entry in "${port_map[@]}"; do
        local port="${entry%%:*}"
        local name="${entry#*:}"
        local status="free"
        port_in_use "$port" && status="in use"
        local color="$C_GREEN"
        [[ "$status" == "free" ]] && color="$C_YELLOW"
        printf "  %-8s %-20s ${color}%s${C_RESET}\n" "$port" "$name" "$status"
    done
}

manager_quick_install() {
    echo -e "\n${HEADER_COLOR}=== Quick Install (NMP Stack) ===${C_RESET}"
    echo -e "  This will install Nginx + PHP ${PHP_VERSION_DEFAULT} + MySQL/MariaDB in one go.\n"

    echo -e "\n${HEADER_COLOR}Configure installation options:${C_RESET}"

    local db_sel
    db_sel=$(prompt_select "Select database:" "MariaDB 10.11" "MySQL 8.0")
    local db_type="${db_sel% *}"
    local db_version="${db_sel#* }"

    local db_password
    echo -e "\n${HEADER_COLOR}Set ${db_type} root password${C_RESET}"
    prompt_password "Root password (leave empty for auto-generated)" db_password
    if [[ -z "$db_password" ]]; then
        db_password=$(gen_password 20)
        log_info "Generated root password: ${C_BOLD}${db_password}${C_RESET}"
    fi

    local php_method
    php_method=$(prompt_select "Select PHP installation method:" "APT - SURY repository (fast)" "Source compilation")

    local setup_default_site=false
    if confirm "Set up default site (catch-all for IP/unconfigured domains)?" "y"; then
        setup_default_site=true
    fi

    if ! confirm "Start quick installation?"; then
        return 0
    fi

    log_info "Starting quick NMP stack installation..."
    ensure_dirs "${LOG_DIR}" "${RUN_DIR}" "${DATA_DIR}" "${ETC_DIR}" "${BACKUP_DIR}"

    local step_ok=true

    if ! nginx_is_installed; then
        log_info "[1/3] Installing Nginx..."
        nginx_install_apt stable || { log_error "Nginx install failed"; step_ok=false; }
        if $step_ok; then
            nginx_setup_config
            systemctl start nginx &>/dev/null
            if $setup_default_site; then
                nginx_default_site_enable
            fi
        fi
    fi

    if $step_ok && ! php_is_installed "$PHP_VERSION_DEFAULT"; then
        log_info "[2/3] Installing PHP ${PHP_VERSION_DEFAULT}..."
        case "$php_method" in
            *APT*|*SURY*)
                php_install_apt "$PHP_VERSION_DEFAULT" || {
                    log_warn "APT install failed, trying source compilation..."
                    php_install_source "$PHP_VERSION_DEFAULT" || { log_error "PHP ${PHP_VERSION_DEFAULT} install failed"; step_ok=false; }
                }
                ;;
            *Source*)
                php_install_source "$PHP_VERSION_DEFAULT" || { log_error "PHP ${PHP_VERSION_DEFAULT} install failed"; step_ok=false; }
                ;;
        esac
        if $step_ok; then
            php_setup_config "$PHP_VERSION_DEFAULT"
            systemctl start "php${PHP_VERSION_DEFAULT}-fpm" &>/dev/null || true
        fi
    fi

    if $step_ok; then
        case "$db_type" in
            MySQL)
                if ! mysql_is_installed; then
                    log_info "[3/3] Installing MySQL ${db_version}..."
                    mysql_install_mysql "$db_version" "$db_password" || { log_error "MySQL install failed"; step_ok=false; }
                fi
                ;;
            MariaDB)
                if ! mysql_is_installed; then
                    log_info "[3/3] Installing MariaDB ${db_version}..."
                    mysql_install_mariadb "$db_version" "$db_password" || { log_error "MariaDB install failed"; step_ok=false; }
                fi
                ;;
        esac
    fi

    echo ""
    print_separator
    if $step_ok; then
        log_success "NMP Stack installation complete!"
    else
        log_error "NMP Stack installation completed with errors!"
    fi
    print_separator

    manager_services_status
}

manager_backup() {
    echo -e "\n${HEADER_COLOR}=== Backup Configuration ===${C_RESET}"

    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    local backup_dir="${BACKUP_DIR}/${timestamp}"
    ensure_dirs "$backup_dir"

    log_info "Creating backup in ${backup_dir}..."

    if [[ -d "${NGINX_ETC_DIR}" ]]; then
        cp -a "${NGINX_ETC_DIR}" "$backup_dir/nginx"
        log_info "Backed up: Nginx configuration"
    fi

    local versions
    versions=$(get_php_versions_installed)
    if [[ -n "$versions" ]]; then
        while IFS= read -r ver; do
            if [[ -d "${PHP_ETC_DIR}/php${ver}" ]]; then
                cp -a "${PHP_ETC_DIR}/php${ver}" "$backup_dir/php${ver}"
                log_info "Backed up: PHP ${ver} configuration"
            fi
        done <<< "$versions"
    fi

    if [[ -d "${MYSQL_ETC_DIR}" ]]; then
        cp -a "${MYSQL_ETC_DIR}" "$backup_dir/mysql"
        log_info "Backed up: MySQL configuration"
    fi

    if [[ -d "${REDIS_ETC_DIR}" ]]; then
        cp -a "${REDIS_ETC_DIR}" "$backup_dir/redis"
        log_info "Backed up: Redis configuration"
    fi

    if [[ -d "${FTP_ETC_DIR}" ]]; then
        cp -a "${FTP_ETC_DIR}" "$backup_dir/vsftpd"
        log_info "Backed up: FTP configuration"
    fi

    if [[ -d "$SSL_DIR" ]]; then
        cp -a "$SSL_DIR" "$backup_dir/ssl"
        log_info "Backed up: SSL certificates"
    fi

    tar -czf "${BACKUP_DIR}/pig-nmp-backup-${timestamp}.tar.gz" -C "$backup_dir" . 2>/dev/null
    rm -rf "$backup_dir"

    log_success "Backup created: ${BACKUP_DIR}/pig-nmp-backup-${timestamp}.tar.gz"
}

manager_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== System Manager ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} System status"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Services status"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Port status"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Quick install NMP stack"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Backup configuration"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} System optimization"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) manager_system_status; wait_enter ;;
            2) manager_services_status; wait_enter ;;
            3) manager_ports_status; wait_enter ;;
            4) manager_quick_install ;;
            5) manager_backup ;;
            6) optimize_system ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
