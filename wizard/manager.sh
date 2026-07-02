#!/usr/bin/env bash
#
# Pig-NMP - System Manager & Status
#

manager_system_status() {
    echo -e "\n${HEADER_COLOR}=== System Status ===${C_RESET}"

    local os_name hostname uptime_str load cpu_count mem_total mem_free mem_percent disk_used
    hostname=$(hostname 2>/dev/null)
    os_name=$(PRETTY_NAME 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)
    uptime_str=$(uptime -p 2>/dev/null || uptime)
    load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')
    cpu_count=$(nproc 2>/dev/null)
    mem_total=$(awk '/MemTotal/{printf "%.0fMB", $2/1024}' /proc/meminfo 2>/dev/null)
    mem_free=$(awk '/MemAvailable/{printf "%.0fMB", $2/1024}' /proc/meminfo 2>/dev/null)
    mem_percent=$(awk '/MemAvailable/{printf "%.1f", (1-$2/$1)*100}' /proc/meminfo 2>/dev/null)
    disk_used=$(df -h / 2>/dev/null | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')

    printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "Hostname:" "${hostname}"
    printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "OS:" "${os_name}"
    printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "Uptime:" "${uptime_str}"
    printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "Load:" "${load}"
    printf "  ${C_BOLD}%-12s${C_RESET} %s cores\n" "CPU:" "${cpu_count}"
    printf "  ${C_BOLD}%-12s${C_RESET} %s / %s (%s%% used)\n" "Memory:" "${mem_free}" "${mem_total}" "${mem_percent}"
    printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "Disk /:" "${disk_used}"
    printf "  ${C_BOLD}%-12s${C_RESET} %s\n" "IP:" "$(get_ip)"
}

manager_services_status() {
    echo -e "\n${HEADER_COLOR}=== Services Status ===${C_RESET}"

    # Nginx
    nginx_is_installed && print_status "Nginx" "installed" || print_status "Nginx" "not_installed"
    is_service_active nginx && print_status "  nginx.service" "running" || print_status "  nginx.service" "stopped"

    # PHP-FPM
    local versions
    versions=$(get_php_versions_installed)
    if [[ -n "$versions" ]]; then
        while IFS= read -r ver; do
            print_status "PHP ${ver}" "installed"
            is_service_active "php${ver}-fpm" && print_status "  php${ver}-fpm.service" "running" || print_status "  php${ver}-fpm.service" "stopped"
        done <<< "$versions"
    else
        print_status "PHP" "not_installed"
    fi

    # MySQL/MariaDB
    mysql_is_installed && print_status "$(mysql_get_type | tr '[:lower:]' '[:upper:]')" "installed" || print_status "MySQL/MariaDB" "not_installed"
    (is_service_active mysql || is_service_active mariadb) && print_status "  mysql/mariadb.service" "running" || print_status "  mysql/mariadb.service" "stopped"

    # Redis
    redis_is_installed && print_status "Redis" "installed" || print_status "Redis" "not_installed"
    (is_service_active redis || is_service_active redis-server) && print_status "  redis.service" "running" || print_status "  redis.service" "stopped"
}

manager_ports_status() {
    echo -e "\n${HEADER_COLOR}=== Port Usage ===${C_RESET}"

    printf "  ${C_BOLD}%-10s %-15s %s${C_RESET}\n" "Port" "Service" "Status"
    print_separator

    local ports=(22 80 443 3306 6379)
    # Add PHP-FPM ports
    local versions
    versions=$(get_php_versions_installed)
    if [[ -n "$versions" ]]; then
        while IFS= read -r ver; do
            ports+=("$(get_php_fpm_port "$ver")")
        done <<< "$versions"
    fi

    local port
    for port in "${ports[@]}"; do
        local service="unknown"
        case "$port" in
            22)   service="SSH" ;;
            80)   service="HTTP (Nginx)" ;;
            443)  service="HTTPS (Nginx)" ;;
            3306) service="MySQL/MariaDB" ;;
            6379) service="Redis" ;;
        esac
        # Check if it's a PHP-FPM port
        if [[ -n "$versions" ]]; then
            while IFS= read -r ver; do
                local fpm_port=$(get_php_fpm_port "$ver")
                [[ "$port" == "$fpm_port" ]] && service="PHP ${ver}-FPM"
            done <<< "$versions"
        fi

        if port_in_use "$port"; then
            printf "  %-10s %-15s ${C_GREEN}in use${C_RESET}\n" "$port" "$service"
        else
            printf "  %-10s %-15s ${C_YELLOW}free${C_RESET}\n" "$port" "$service"
        fi
    done
}

manager_quick_install() {
    echo -e "\n${HEADER_COLOR}=== Quick Install NMP Stack ===${C_RESET}"

    # Nginx
    if ! nginx_is_installed; then
        log_info "Installing Nginx..."
        nginx_install_apt stable || { log_error "Nginx installation failed"; return 1; }
        nginx_setup_config
        systemctl start nginx &>/dev/null
    else
        log_info "Nginx already installed, skipping"
    fi

    # PHP
    local php_ver="${PHP_VERSION_DEFAULT}"
    if ! php_is_installed "$php_ver"; then
        log_info "Installing PHP ${php_ver}..."
        php_install_apt "$php_ver" || { log_error "PHP installation failed"; return 1; }
    else
        log_info "PHP ${php_ver} already installed, skipping"
    fi

    # Database
    if ! mysql_is_installed; then
        local db_type
        db_type=$(prompt_select "Choose database:" "MySQL 8.0" "MariaDB 10.11")
        case "$db_type" in
            MySQL*)    mysql_install_mysql || { log_error "MySQL installation failed"; return 1; } ;;
            MariaDB*)  mysql_install_mariadb || { log_error "MariaDB installation failed"; return 1; } ;;
        esac
    else
        log_info "$(mysql_get_type) already installed, skipping"
    fi

    echo ""
    print_separator
    log_success "NMP Stack installation complete!"
    print_separator
    manager_services_status
}

manager_backup() {
    local backup_dir="${BACKUP_DIR}/full-$(date +%Y%m%d%H%M%S)"
    ensure_dirs "$backup_dir"

    log_info "Backing up configurations..."

    # Nginx
    nginx_is_installed && cp -a "${NGINX_ETC_DIR}" "$backup_dir/nginx" 2>/dev/null

    # PHP configs
    local versions
    versions=$(get_php_versions_installed)
    if [[ -n "$versions" ]]; then
        mkdir -p "$backup_dir/php"
        while IFS= read -r ver; do
            local php_etc="${PHP_ETC_DIR}/php${ver}"
            [[ -d "$php_etc" ]] && cp -a "$php_etc" "$backup_dir/php/" 2>/dev/null
        done <<< "$versions"
    fi

    # MySQL
    mysql_is_installed && cp -a "${MYSQL_ETC_DIR}" "$backup_dir/mysql" 2>/dev/null

    # Redis
    redis_is_installed && cp -a "${REDIS_ETC_DIR}" "$backup_dir/redis" 2>/dev/null

    # SSL
    [[ -d "${SSL_DIR}" ]] && cp -a "${SSL_DIR}" "$backup_dir/ssl" 2>/dev/null

    # Create tarball
    local tarball="${BACKUP_DIR}/backup-$(date +%Y%m%d%H%M%S).tar.gz"
    tar -czf "$tarball" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" 2>/dev/null
    rm -rf "$backup_dir"

    if [[ -f "$tarball" ]]; then
        log_success "Backup created: ${tarball}"
    else
        log_error "Backup failed"; return 1
    fi
}

manager_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== System Manager ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} System status"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Services status"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Ports status"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Quick install NMP stack"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Backup configurations"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice
        case "$choice" in
            1) manager_system_status ;;
            2) manager_services_status ;;
            3) manager_ports_status ;;
            4) manager_quick_install ;;
            5) manager_backup ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
