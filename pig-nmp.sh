#!/usr/bin/env bash
#
# Pig-NMP - Nginx + MySQL/MariaDB + PHP Environment Manager
# Main Entry Point
#
# Usage:
#   sudo bash pig-nmp.sh           # Interactive menu
#   sudo bash pig-nmp.sh install   # Quick install all
#   sudo bash pig-nmp.sh status    # Show status
#

set -uo pipefail
set -o errtrace

trap 'log_error "Error on line $LINENO in $BASH_SOURCE"; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/config.inc.sh"
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/color.sh"
source "${LIB_DIR}/download.sh"
source "${LIB_DIR}/os.sh"

source "${MODULES_DIR}/nginx.sh"
source "${MODULES_DIR}/php.sh"
source "${MODULES_DIR}/mysql.sh"
source "${MODULES_DIR}/redis.sh"
source "${MODULES_DIR}/memcached.sh"
source "${MODULES_DIR}/php-ext.sh"
source "${MODULES_DIR}/phpmyadmin.sh"
source "${MODULES_DIR}/ftp.sh"
source "${MODULES_DIR}/firewall.sh"
source "${MODULES_DIR}/ioncube.sh"

source "${WIZARD_DIR}/vhost.sh"
source "${WIZARD_DIR}/ssl.sh"
source "${WIZARD_DIR}/manager.sh"

check_root
check_os
detect_os

ensure_dirs "${LOG_DIR}" "${RUN_DIR}" "${DATA_DIR}" "${ETC_DIR}" "${BACKUP_DIR}"

show_main_menu() {
    print_banner

    echo -e "  ${C_BOLD}Component Status:${C_RESET}"
    nginx_is_installed && echo -e "  ${C_GREEN}●${C_RESET} Nginx $(nginx_get_version)" || echo -e "  ${C_RED}○${C_RESET} Nginx (not installed)"

    local versions
    versions=$(get_php_versions_installed)
    if [[ -n "$versions" ]]; then
        while IFS= read -r ver; do
            echo -e "  ${C_GREEN}●${C_RESET} PHP ${ver}"
        done <<< "$versions"
    else
        echo -e "  ${C_RED}○${C_RESET} PHP (not installed)"
    fi

    mysql_is_installed && echo -e "  ${C_GREEN}●${C_RESET} $(mysql_get_type | tr '[:lower:]' '[:upper:]') $(mysql_get_version)" || echo -e "  ${C_RED}○${C_RESET} MySQL/MariaDB (not installed)"
    redis_is_installed && echo -e "  ${C_GREEN}●${C_RESET} Redis $(redis_get_version)" || echo -e "  ${C_RED}○${C_RESET} Redis (not installed)"
    memcached_is_installed && echo -e "  ${C_GREEN}●${C_RESET} Memcached $(memcached_get_version)" || echo -e "  ${C_RED}○${C_RESET} Memcached (not installed)"
    pma_is_installed && echo -e "  ${C_GREEN}●${C_RESET} phpMyAdmin $(pma_get_version)" || echo -e "  ${C_RED}○${C_RESET} phpMyAdmin (not installed)"
    ftp_is_installed && echo -e "  ${C_GREEN}●${C_RESET} vsftpd $(ftp_get_version)" || echo -e "  ${C_RED}○${C_RESET} FTP (not installed)"

    echo ""
    print_separator
    echo ""

    echo -e "  ${MENU_NUM_COLOR}1)${C_RESET}  Install/Update Components"
    echo -e "  ${MENU_NUM_COLOR}2)${C_RESET}  Manage Virtual Hosts"
    echo -e "  ${MENU_NUM_COLOR}3)${C_RESET}  Configure SSL Certificates"
    echo -e "  ${MENU_NUM_COLOR}4)${C_RESET}  PHP Version & Extension Management"
    echo -e "  ${MENU_NUM_COLOR}5)${C_RESET}  FTP Server Management"
    echo -e "  ${MENU_NUM_COLOR}6)${C_RESET}  Firewall (UFW) Management"
    echo -e "  ${MENU_NUM_COLOR}7)${C_RESET}  System Status & Manager"
    echo -e "  ${MENU_NUM_COLOR}8)${C_RESET}  Uninstall Components"
    echo ""
    echo -e "  ${MENU_NUM_COLOR}0)${C_RESET}  Exit"
    echo ""
}

menu_install() {
    echo -e "\n${HEADER_COLOR}=== Install/Update Components ===${C_RESET}"
    echo -e "  ${MENU_NUM_COLOR}1)${C_RESET}  Nginx"
    echo -e "  ${MENU_NUM_COLOR}2)${C_RESET}  PHP (multi-version)"
    echo -e "  ${MENU_NUM_COLOR}3)${C_RESET}  MySQL / MariaDB"
    echo -e "  ${MENU_NUM_COLOR}4)${C_RESET}  Redis"
    echo -e "  ${MENU_NUM_COLOR}5)${C_RESET}  Memcached"
    echo -e "  ${MENU_NUM_COLOR}6)${C_RESET}  phpMyAdmin"
    echo -e "  ${MENU_NUM_COLOR}7)${C_RESET}  FTP (vsftpd)"
    echo -e "  ${MENU_NUM_COLOR}8)${C_RESET}  ionCube Loader"
    echo -e "  ${MENU_NUM_COLOR}9)${C_RESET}  Quick Install (NMP Stack)"
    echo ""
    echo -e "  ${MENU_NUM_COLOR}0)${C_RESET}  Back"
    echo ""
}

menu_uninstall() {
    echo -e "\n${HEADER_COLOR}=== Uninstall Components ===${C_RESET}"
    echo -e "  ${MENU_NUM_COLOR}1)${C_RESET}  Uninstall Nginx"
    echo -e "  ${MENU_NUM_COLOR}2)${C_RESET}  Uninstall PHP version"
    echo -e "  ${MENU_NUM_COLOR}3)${C_RESET}  Uninstall MySQL/MariaDB"
    echo -e "  ${MENU_NUM_COLOR}4)${C_RESET}  Uninstall Redis"
    echo -e "  ${MENU_NUM_COLOR}5)${C_RESET}  Uninstall Memcached"
    echo -e "  ${MENU_NUM_COLOR}6)${C_RESET}  Uninstall phpMyAdmin"
    echo -e "  ${MENU_NUM_COLOR}7)${C_RESET}  Uninstall FTP (vsftpd)"
    echo -e "  ${MENU_NUM_COLOR}8)${C_RESET}  Uninstall ionCube"
    echo -e "  ${MENU_NUM_COLOR}9)${C_RESET}  Uninstall Firewall (UFW)"
    echo -e "  ${C_RED}${MENU_NUM_COLOR}P)${C_RESET}  Purge ALL components${C_RESET}"
    echo ""
    echo -e "  ${MENU_NUM_COLOR}0)${C_RESET}  Back"
    echo ""
}

handle_install_menu() {
    menu_install
    local choice
    read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

    case "$choice" in
        1) nginx_install ;;
        2) php_install ;;
        3) mysql_install ;;
        4) redis_install ;;
        5) memcached_install ;;
        6) pma_install ;;
        7) ftp_install ;;
        8) ioncube_install ;;
        9) manager_quick_install ;;
        0) return ;;
        *) log_warn "Invalid choice" ;;
    esac
}

handle_uninstall_menu() {
    menu_uninstall
    local choice
    read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

    case "$choice" in
        1) nginx_uninstall ;;
        2) php_uninstall ;;
        3) mysql_uninstall ;;
        4) redis_uninstall ;;
        5) memcached_uninstall ;;
        6) pma_uninstall ;;
        7) ftp_uninstall ;;
        8) ioncube_uninstall ;;
        9) firewall_uninstall ;;
        p|P) cmd_purge ;;
        0) return ;;
        *) log_warn "Invalid choice" ;;
    esac
}

cmd_install() {
    log_info "Starting quick NMP stack installation..."
    ensure_dirs "${LOG_DIR}" "${RUN_DIR}" "${DATA_DIR}" "${ETC_DIR}" "${BACKUP_DIR}"

    if ! nginx_is_installed; then
        nginx_install_apt stable || { log_error "Nginx installation failed"; return 1; }
        nginx_setup_config
        systemctl start nginx &>/dev/null
    fi

    if ! php_is_installed "$PHP_VERSION_DEFAULT"; then
        php_install "$PHP_VERSION_DEFAULT" || { log_error "PHP installation failed"; return 1; }
    fi

    if ! mysql_is_installed; then
        local db_type
        db_type=$(prompt_select "Choose database:" "MySQL 8.0" "MariaDB 10.11")
        case "$db_type" in
            MySQL*) mysql_install_mysql || { log_error "MySQL installation failed"; return 1; } ;;
            MariaDB*) mysql_install_mariadb || { log_error "MariaDB installation failed"; return 1; } ;;
        esac
    fi

    echo ""
    print_separator
    log_success "NMP Stack installation complete!"
    print_separator
    manager_services_status
}

cmd_status() {
    manager_system_status
    manager_services_status
    manager_ports_status
}

cmd_purge() {
    echo -e "\n${C_RED}${C_BOLD}WARNING: This will uninstall ALL Pig-NMP components!${C_RESET}"
    echo -e "${C_RED}Including: Nginx, PHP, MySQL/MariaDB, Redis, Memcached, phpMyAdmin, FTP, ionCube, and all configurations.${C_RESET}\n"

    if ! confirm "Are you sure you want to purge everything?"; then
        return 0
    fi

    local keep_data="n"
    if confirm "Keep data files (databases, website files)?"; then
        keep_data="y"
    fi

    log_info "Purging all Pig-NMP components..."

    # Stop and disable all php-fpm services by listing matching units
    local -a php_fpm_units=()
    while IFS= read -r unit; do
        [[ -n "$unit" ]] && php_fpm_units+=("$unit")
    done < <(systemctl list-units --type=service --no-legend --no-pager 'php*-fpm.service' 2>/dev/null | awk '{print $1}')

    systemctl stop nginx mysql mariadb redis memcached vsftpd "${php_fpm_units[@]}" 2>/dev/null || true
    systemctl disable nginx mysql mariadb redis memcached vsftpd "${php_fpm_units[@]}" 2>/dev/null || true

    apt_remove nginx nginx-common nginx-full 2>/dev/null || true
    apt_remove mysql-server mysql-client mysql-common mariadb-server mariadb-client mariadb-common 2>/dev/null || true
    apt_remove redis-server redis-tools memcached vsftpd 2>/dev/null || true

    local -a php_pkgs=()
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && php_pkgs+=("$pkg")
    done < <(dpkg -l 2>/dev/null | awk '/^ii[[:space:]]+php[0-9]+\.[0-9]+/{print $2}')
    if [[ ${#php_pkgs[@]} -gt 0 ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq "${php_pkgs[@]}" 2>/dev/null || true
    fi

    rm -f /etc/systemd/system/nginx.service /etc/systemd/system/php*-fpm*.service
    rm -f /etc/systemd/system/redis.service /etc/systemd/system/memcached.service
    rm -f /etc/systemd/system/vsftpd.service /etc/systemd/system/mysqld.service
    rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/sources.list.d/mysql.list
    rm -f /etc/apt/sources.list.d/mariadb.list /etc/apt/sources.list.d/php.list
    rm -f /etc/pam.d/vsftpd.virtual /etc/logrotate.d/pig-nmp
    systemctl daemon-reload

    if [[ "$keep_data" != "y" ]]; then
        rm -rf /var/lib/mysql
        rm -rf "${MYSQL_DATA_DIR}" "${REDIS_DATA_DIR}"
    fi

    rm -rf "${INSTALL_PREFIX}/nginx" "${INSTALL_PREFIX}/php"* "${INSTALL_PREFIX}/ioncube"
    rm -rf "${PHP_BASE_DIR}" "${PHPMYADMIN_DIR}"
    rm -rf "${ETC_DIR}" "${LOG_DIR}" "${FTP_ETC_DIR}" "${FTP_USER_DIR}" "${SSL_DIR}"
    rm -rf "${NGINX_SITES_AVAILABLE}" "${NGINX_SITES_ENABLED}"

    if [[ "$keep_data" != "y" ]]; then
        rm -rf "${DOMAINS_DIR}" "${DATA_DIR}"
    fi

    apt-get autoremove -y -qq 2>/dev/null || true

    log_success "All Pig-NMP components have been purged"
    if [[ "$keep_data" == "y" ]]; then
        log_info "Data files were preserved"
    fi
}

cmd_help() {
    echo -e "${C_BOLD}Pig-NMP v${PIG_NMP_VERSION}${C_RESET} - Nginx + MySQL/MariaDB + PHP Environment Manager"
    echo ""
    echo "Usage: sudo bash pig-nmp.sh [command]"
    echo ""
    echo "Commands:"
    echo "  (none)     Interactive menu mode"
    echo "  install    Quick install NMP stack"
    echo "  status     Show system and service status"
    echo "  purge      Uninstall all Pig-NMP components"
    echo "  help       Show this help message"
    echo ""
    echo "Component commands:"
    echo "  nginx      Nginx management menu"
    echo "  php        PHP management menu"
    echo "  mysql      MySQL/MariaDB management menu"
    echo "  redis      Redis management menu"
    echo "  memcached  Memcached management menu"
    echo "  pma        phpMyAdmin management menu"
    echo "  ftp        FTP server management menu"
    echo "  firewall   UFW firewall management menu"
    echo "  ioncube    ionCube Loader management menu"
    echo "  vhost      Virtual host management menu"
    echo "  ssl        SSL certificate management menu"
    echo ""
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        install)   cmd_install ;;
        status)    cmd_status ;;
        purge)     cmd_purge ;;
        help|--help|-h) cmd_help ;;
        nginx)     nginx_menu ;;
        php)       php_menu ;;
        mysql)     mysql_menu ;;
        redis)     redis_menu ;;
        memcached) memcached_menu ;;
        pma)       pma_menu ;;
        ftp)       ftp_menu ;;
        firewall)  firewall_menu ;;
        ioncube)   ioncube_menu ;;
        vhost)     vhost_menu ;;
        ssl)       ssl_menu ;;
        *)         log_error "Unknown command: $1"; cmd_help; exit 1 ;;
    esac
    exit 0
fi

while true; do
    show_main_menu

    main_choice=""
    read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" main_choice

    case "$main_choice" in
        1) handle_install_menu ;;
        2) vhost_menu ;;
        3) ssl_menu ;;
        4)
            echo -e "\n${HEADER_COLOR}=== PHP Management ===${C_RESET}"
            echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} PHP version management"
            echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} PHP extension management"
            echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} ionCube Loader"
            echo ""
            php_choice=""
            read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" php_choice
            case "$php_choice" in
                1) php_menu ;;
                2) php_ext_menu ;;
                3) ioncube_menu ;;
            esac
            ;;
        5) ftp_menu ;;
        6) firewall_menu ;;
        7) manager_menu ;;
        8) handle_uninstall_menu ;;
        0)
            echo -e "\n${C_GREEN}Thank you for using Pig-NMP!${C_RESET}\n"
            exit 0
            ;;
        *)
            log_warn "Invalid choice"
            ;;
    esac
done
