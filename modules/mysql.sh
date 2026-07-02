#!/usr/bin/env bash
#
# Pig-NMP - MySQL/MariaDB Module
#

mysql_is_installed() {
    command -v mysql &>/dev/null || command -v mariadb &>/dev/null
}

mysql_get_type() {
    if command -v mariadb &>/dev/null; then
        echo "mariadb"
    elif command -v mysql &>/dev/null; then
        echo "mysql"
    else
        echo "none"
    fi
}

mysql_get_version() {
    local type=$(mysql_get_type)
    case "$type" in
        mariadb) mariadb --version 2>&1 | grep -oP '[\d.]+-MariaDB' | head -1 ;;
        mysql)   mysql --version 2>&1 | grep -oP 'Ver \K[\d.]+' ;;
        *)       echo "unknown" ;;
    esac
}

mysql_install() {
    if mysql_is_installed; then
        log_warn "MySQL/MariaDB is already installed: $(mysql_get_type) $(mysql_get_version)"
        confirm "Reinstall?" || return 0
        mysql_uninstall
    fi

    local db_type
    db_type=$(prompt_select "Choose database:" "MySQL 8.0" "MariaDB 10.11")
    case "$db_type" in
        MySQL*)    mysql_install_mysql ;;
        MariaDB*)  mysql_install_mariadb ;;
    esac
}

mysql_install_mysql() {
    require_os
    log_info "Installing MySQL..."

    local version
    version=$(prompt_select "Select MySQL version:" "8.0" "8.4" "9.1")

    # Use MySQL APT repository
    local deb_pkg="mysql-apt-config_0.8.33-1_all.deb"
    local tmp_deb="${TMP_DIR}/${deb_pkg}"
    ensure_dirs "$TMP_DIR"

    log_info "Setting up MySQL APT repository..."
    download_file "https://dev.mysql.com/get/${deb_pkg}" "$tmp_deb" || {
        log_error "Failed to download MySQL APT config"; return 1
    }

    DEBIAN_FRONTEND=noninteractive dpkg -i "$tmp_deb" 2>/dev/null
    apt-get update -qq 2>&1 | tail -3

    log_info "Installing MySQL ${version}..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server 2>&1 | tail -5
    local ret=$?

    if [[ $ret -ne 0 ]]; then
        log_error "Failed to install MySQL"; return 1
    fi

    systemctl enable mysql &>/dev/null
    systemctl start mysql &>/dev/null

    if is_service_active mysql; then
        log_success "MySQL installed and running"
        mysql_secure
    else
        log_warn "MySQL installed but failed to start"
    fi
}

mysql_install_mariadb() {
    require_os
    log_info "Installing MariaDB..."

    local version
    version=$(prompt_select "Select MariaDB version:" "10.11" "11.4" "11.6")

    # Import MariaDB GPG key
    local keyring="/usr/share/keyrings/mariadb-archive-keyring.gpg"
    curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp | gpg --dearmor -o "$keyring" 2>/dev/null || {
        log_error "Failed to import MariaDB GPG key"; return 1
    }
    chmod 644 "$keyring"

    echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] https://deb.mariadb.org/${version}/${OS_ID} ${OS_CODENAME} main" \
        > /etc/apt/sources.list.d/mariadb.list

    apt-get update -qq 2>&1 | tail -3

    log_info "Installing MariaDB ${version}..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mariadb-server 2>&1 | tail -5
    local ret=$?

    if [[ $ret -ne 0 ]]; then
        log_error "Failed to install MariaDB"; return 1
    fi

    systemctl enable mariadb &>/dev/null
    systemctl start mariadb &>/dev/null

    if is_service_active mariadb; then
        log_success "MariaDB installed and running"
        mysql_secure
    else
        log_warn "MariaDB installed but failed to start"
    fi
}

mysql_secure() {
    local root_pass="$1"
    if [[ -z "$root_pass" ]]; then
        # Try to read saved password
        local pass_file="${MYSQL_ETC_DIR}/.root_password"
        if [[ -f "$pass_file" ]]; then
            root_pass=$(cat "$pass_file")
        else
            prompt_password "Set root password" root_pass
            [[ -z "$root_pass" ]] && { log_error "Root password cannot be empty"; return 1; }
        fi
    fi

    log_info "Securing MySQL installation..."

    local sql=$(cat <<EOSQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOSQL
)

    mysql -u root -e "$sql" 2>/dev/null || \
    mysql -u root -p"${root_pass}" -e "$sql" 2>/dev/null || \
    mysqladmin -u root password "${root_pass}" 2>/dev/null

    ensure_dirs "${MYSQL_ETC_DIR}"
    echo "$root_pass" > "${MYSQL_ETC_DIR}/.root_password"
    chmod 600 "${MYSQL_ETC_DIR}/.root_password"

    log_success "MySQL secured successfully"
}

mysql_create_database() {
    local db_name="$1" db_user="$2" db_pass="$3"
    [[ -z "$db_name" ]] && prompt_input "Database name" "" db_name
    [[ -z "$db_user" ]] && prompt_input "Database user" "" db_user
    [[ -z "$db_pass" ]] && db_pass=$(gen_password 16)

    local root_pass=""
    local pass_file="${MYSQL_ETC_DIR}/.root_password"
    [[ -f "$pass_file" ]] && root_pass=$(cat "$pass_file")

    local sql=$(cat <<EOSQL
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOSQL
)

    mysql -u root -p"${root_pass}" -e "$sql" 2>/dev/null || \
    mysql -u root -e "$sql" 2>/dev/null || {
        log_error "Failed to create database"; return 1
    }

    log_success "Database '${db_name}' created with user '${db_user}'"
    echo -e "  ${C_BOLD}Database:${C_RESET} ${db_name}"
    echo -e "  ${C_BOLD}User:${C_RESET}     ${db_user}"
    echo -e "  ${C_BOLD}Password:${C_RESET} ${db_pass}"
}

mysql_setup_config() {
    local type=$(mysql_get_type)
    local conf_dir
    [[ "$type" == "mariadb" ]] && conf_dir="/etc/mysql/mariadb.conf.d" || conf_dir="/etc/mysql/conf.d"
    ensure_dirs "$conf_dir"

    local conf_file="${conf_dir}/pig-nmp.cnf"
    local innodb_buffer=$(($SYSCTL_MEM / 1024 / 4))  # 25% of RAM in MB
    (( innodb_buffer < 256 )) && innodb_buffer=256

    cat > "$conf_file" << EOF
[mysqld]
innodb_buffer_pool_size = ${innodb_buffer}M
innodb_log_file_size = 128M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
max_connections = 200
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
skip-name-resolve

[client]
default-character-set = utf8mb4
EOF

    log_success "MySQL config written to ${conf_file}"
}

mysql_uninstall() {
    mysql_is_installed || { log_warn "MySQL/MariaDB is not installed"; return 0; }
    confirm "Uninstall MySQL/MariaDB? All databases will be lost!" || return 0

    local keep_data="n"
    confirm "Keep data files (databases)?" "y" && keep_data="y"

    local type=$(mysql_get_type)
    local service_name="mysql"
    [[ "$type" == "mariadb" ]] && service_name="mariadb"

    systemctl stop "$service_name" &>/dev/null
    systemctl disable "$service_name" &>/dev/null

    DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq mysql-server mysql-client mysql-common 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq mariadb-server mariadb-client mariadb-common 2>/dev/null
    apt-get autoremove -y -qq 2>/dev/null

    rm -f /etc/apt/sources.list.d/mysql.list /etc/apt/sources.list.d/mariadb.list
    rm -f /etc/systemd/system/mysqld.service

    if [[ "$keep_data" != "y" ]]; then
        rm -rf /var/lib/mysql "${MYSQL_DATA_DIR}"
    fi

    rm -rf "${MYSQL_ETC_DIR}"
    systemctl daemon-reload

    log_success "MySQL/MariaDB uninstalled"
}

mysql_status() {
    echo -e "\n${HEADER_COLOR}=== MySQL/MariaDB Status ===${C_RESET}"
    if mysql_is_installed; then
        local type=$(mysql_get_type)
        print_status "${type}" "installed"
        echo -e "  Version: $(mysql_get_version)"
        is_service_active mysql && print_status "Service" "running" || print_status "Service" "stopped"
    else
        print_status "MySQL/MariaDB" "not_installed"
    fi
}

mysql_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== MySQL/MariaDB Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install MySQL / MariaDB"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall MySQL / MariaDB"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Secure installation (set root password)"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Create database"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Setup configuration"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice
        case "$choice" in
            1) mysql_install ;;
            2) mysql_uninstall ;;
            3) mysql_secure ;;
            4)
                local db_name db_user db_pass
                prompt_input "Database name" "" db_name
                prompt_input "Database user" "" db_user
                db_pass=$(gen_password 16)
                mysql_create_database "$db_name" "$db_user" "$db_pass"
                ;;
            5) mysql_setup_config ;;
            6) mysql_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
