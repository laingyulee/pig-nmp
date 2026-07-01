#!/usr/bin/env bash
#
# Pig-NMP - MySQL/MariaDB Module
#

source "${CONF_DIR}/versions.conf"

mysql_is_installed() {
    is_installed mysql || is_installed mariadb || [[ -x /usr/sbin/mysqld ]]
}

mysql_get_type() {
    if is_installed mariadb || dpkg -l mariadb-server &>/dev/null 2>&1 | grep -q '^ii'; then
        echo "mariadb"
    elif is_installed mysql || dpkg -l mysql-server &>/dev/null 2>&1 | grep -q '^ii'; then
        echo "mysql"
    else
        echo "none"
    fi
}

mysql_get_version() {
    local type
    type=$(mysql_get_type)
    if [[ "$type" == "mariadb" ]]; then
        mariadb --version 2>/dev/null | grep -oP 'Ver\s+\K[\d.]+' | head -1
    elif [[ "$type" == "mysql" ]]; then
        mysql --version 2>/dev/null | grep -oP 'Ver\s+\K[\d.]+' | head -1
    fi
}

mysql_install() {
    if mysql_is_installed; then
        log_warn "$(mysql_get_type | tr '[:lower:]' '[:upper:]') is already installed: $(mysql_get_version)"
        if ! confirm "Reinstall?"; then
            return 0
        fi
    fi

    echo -e "\n${HEADER_COLOR}Select database server:${C_RESET}"
    local db_type
    db_type=$(prompt_select "Choose database:" "MySQL" "MariaDB" "Cancel")
    [[ "$db_type" == "Cancel" ]] && return 0

    case "$db_type" in
        MySQL)  mysql_install_mysql ;;
        MariaDB) mysql_install_mariadb ;;
    esac
}

mysql_install_mysql() {
    require_os

    local -a versions=($MYSQL_VERSIONS)
    echo -e "\n${HEADER_COLOR}Select MySQL version:${C_RESET}"
    local -a opts=()
    for v in "${versions[@]}"; do
        opts+=("MySQL ${v}")
    done
    local sel
    sel=$(prompt_select "Choose version:" "${opts[@]}")
    local version="${sel#MySQL }"

    log_info "Installing MySQL ${version}..."

    install_deps wget curl gnupg lsb-release

    local keyring="/usr/share/keyrings/mysql-archive-keyring.gpg"
    rm -f "$keyring"

    local gpg_key_url="https://repo.mysql.com/RPM-GPG-KEY-mysql-2023"
    curl -fsSL "$gpg_key_url" | gpg --dearmor -o "$keyring" 2>/dev/null || {
        log_warn "MySQL GPG key import failed, trying fallback..."
        curl -fsSL "https://repo.mysql.com/RPM-GPG-KEY-mysql" | gpg --dearmor -o "$keyring" 2>/dev/null || {
            log_error "Failed to import MySQL GPG key"
            return 1
        }
    }
    chmod 644 "$keyring"

    local deb_url="$MYSQL_APT_URL"
    local deb_file="${TMP_DIR}/mysql-apt-config.deb"
    ensure_dirs "$TMP_DIR"

    download_file "$deb_url" "$deb_file" || return 1

    DEBIAN_FRONTEND=noninteractive dpkg -i "$deb_file" 2>/dev/null

    echo "mysql-apt-config mysql-apt-config/select-server select mysql-${version}" | debconf-set-selections 2>/dev/null
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a 2>/dev/null

    apt-get update -qq 2>/dev/null

    local pkg_name="mysql-server"
    if [[ "$version" != "8.0" ]]; then
        pkg_name="mysql-server"
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ${pkg_name} 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "MySQL ${version} installed"
    else
        log_error "Failed to install MySQL ${version}"
        return 1
    fi

    mysql_secure
}

mysql_install_mariadb() {
    require_os

    local -a versions=($MARIADB_VERSIONS)
    echo -e "\n${HEADER_COLOR}Select MariaDB version:${C_RESET}"
    local -a opts=()
    for v in "${versions[@]}"; do
        opts+=("MariaDB ${v}")
    done
    local sel
    sel=$(prompt_select "Choose version:" "${opts[@]}")
    local version="${sel#MariaDB }"

    log_info "Installing MariaDB ${version}..."

    install_deps wget curl gnupg lsb-release

    local keyring="/usr/share/keyrings/mariadb-archive-keyring.gpg"
    rm -f "$keyring"

    log_info "Importing MariaDB GPG key..."
    if ! curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp | gpg --dearmor -o "$keyring" 2>/dev/null; then
        log_warn "Primary key download failed, trying alternative..."
        rm -f "$keyring"
        if ! curl -fsSL https://downloads.mariadb.com/MariaDB/mariadb-keyring-2019.gpg -o "$keyring" 2>/dev/null; then
            log_error "Failed to import MariaDB GPG key"
            return 1
        fi
    fi
    chmod 644 "$keyring"

    local repo_line="deb [arch=${OS_ARCH} signed-by=${keyring}] https://deb.mariadb.org/${version}/${OS_ID} ${OS_CODENAME} main"
    echo "$repo_line" > /etc/apt/sources.list.d/mariadb.list

    apt-get update -qq 2>/dev/null

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mariadb-server mariadb-client 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "MariaDB ${version} installed"
    else
        log_error "Failed to install MariaDB ${version}"
        return 1
    fi

    mysql_secure
}

mysql_secure() {
    echo -e "\n${HEADER_COLOR}=== MySQL/MariaDB Security Setup ===${C_RESET}"

    local root_password
    prompt_password "Set root password (leave empty for auto-generated)" root_password
    if [[ -z "$root_password" ]]; then
        root_password=$(gen_password 20)
        log_info "Generated root password: ${C_BOLD}${root_password}${C_RESET}"
    fi

    local db_type
    db_type=$(mysql_get_type)

    local escaped_password
    escaped_password="${root_password//\'/\\\'}"
    escaped_password="${escaped_password//\\/\\\\}"

    if [[ "$db_type" == "mariadb" ]]; then
        mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_password}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    else
        mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_password}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    fi

    ensure_dirs "${MYSQL_ETC_DIR}"
    cat > "${MYSQL_ETC_DIR}/.root_password" <<EOF
# Generated by Pig-NMP
# Date: $(date '+%Y-%m-%d %H:%M:%S')
DB_TYPE=${db_type}
ROOT_PASSWORD=${root_password}
EOF
    chmod 600 "${MYSQL_ETC_DIR}/.root_password"

    log_success "MySQL/MariaDB secured. Root password saved to ${MYSQL_ETC_DIR}/.root_password"
    log_warn "${C_RED}Please save the root password in a safe place!${C_RESET}"
}

mysql_create_database() {
    local db_name db_user db_pass
    prompt_input "Database name" "" db_name
    [[ -z "$db_name" ]] && return 1
    prompt_input "Database user" "$db_name" db_user
    prompt_password "Database password (leave empty for auto-generated)" db_pass
    [[ -z "$db_pass" ]] && db_pass=$(gen_password 16)

    local root_pass
    if [[ -f "${MYSQL_ETC_DIR}/.root_password" ]]; then
        root_pass=$(grep '^ROOT_PASSWORD=' "${MYSQL_ETC_DIR}/.root_password" | cut -d= -f2)
    else
        prompt_password "MySQL root password" root_pass
    fi

    local escaped_pass="${db_pass//\'/\\\'}"
    escaped_pass="${escaped_pass//\\/\\\\}"
    local escaped_user="${db_user//\'/\\\'}"
    escaped_user="${escaped_user//\\/\\\\}"

    local tmp_mysql_cnf="${TMP_DIR}/.mysql_creds_$$.cnf"
    ensure_dirs "$TMP_DIR"
    cat > "$tmp_mysql_cnf" << EOF
[client]
user=root
password=${root_pass}
EOF
    chmod 600 "$tmp_mysql_cnf"

    mysql --defaults-extra-file="$tmp_mysql_cnf" <<EOF
CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${escaped_user}'@'localhost' IDENTIFIED BY '${escaped_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${escaped_user}'@'localhost';
FLUSH PRIVILEGES;
EOF
    local ret=$?

    rm -f "$tmp_mysql_cnf"

    if [[ $ret -eq 0 ]]; then
        log_success "Database created: ${db_name}"
        echo -e "  ${C_GREEN}DB:     ${C_RESET}${db_name}"
        echo -e "  ${C_GREEN}User:   ${C_RESET}${db_user}"
        echo -e "  ${C_GREEN}Pass:   ${C_RESET}${db_pass}"
    else
        log_error "Failed to create database"
    fi
}

mysql_setup_config() {
    local db_type
    db_type=$(mysql_get_type)

    ensure_dirs "${MYSQL_ETC_DIR}" "${MYSQL_DATA_DIR}" "${LOG_DIR}/mysql"

    local my_cnf="${MYSQL_ETC_DIR}/my.cnf"
    local mem_mb=$((SYSCTL_MEM / 1024))
    local innodb_buf=$((mem_mb * 70 / 100))

    if [[ ! -f "$my_cnf" ]]; then
        render_template "${TEMPLATES_DIR}/mysql/my.cnf.tpl" "$my_cnf" \
            DB_TYPE="${db_type}" \
            MYSQL_DATA_DIR="${MYSQL_DATA_DIR}" \
            MYSQL_ETC_DIR="${MYSQL_ETC_DIR}" \
            LOG_DIR="${LOG_DIR}" \
            INNODB_BUFFER_POOL="${innodb_buf}M" \
            MAX_CONNECTIONS="200" \
            SERVER_ID="1"
    fi
}

mysql_uninstall() {
    if ! mysql_is_installed; then
        log_warn "MySQL/MariaDB is not installed"
        return 0
    fi

    local db_type
    db_type=$(mysql_get_type)

    if ! confirm "Uninstall ${db_type}? This will stop the service and remove packages."; then
        return 0
    fi

    local keep_data="n"
    if confirm "Keep data files?"; then
        keep_data="y"
    fi

    systemctl stop mysql mariadb mysqld 2>/dev/null

    if [[ "$db_type" == "mariadb" ]]; then
        apt_remove mariadb-server mariadb-client mariadb-common
    else
        apt_remove mysql-server mysql-client mysql-common
    fi

    if [[ "$keep_data" != "y" ]]; then
        rm -rf /var/lib/mysql
        rm -rf "${MYSQL_DATA_DIR}"
    fi

    rm -rf "${MYSQL_ETC_DIR}"
    rm -f /etc/apt/sources.list.d/mariadb.list /etc/apt/sources.list.d/mysql.list
    apt-get autoremove -y -qq 2>/dev/null

    log_success "${db_type} uninstalled"
}

mysql_status() {
    echo -e "\n${HEADER_COLOR}=== MySQL/MariaDB Status ===${C_RESET}"
    local db_type
    db_type=$(mysql_get_type)
    print_status "Type" "${db_type}"
    if mysql_is_installed; then
        print_status "Version" "$(mysql_get_version)"
        print_status "Service" "$(is_service_active mysql && echo 'running' || echo 'stopped')"
        print_status "Port 3306" "$(port_in_use 3306 && echo 'in_use' || echo 'free')"
    fi
}

mysql_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== MySQL/MariaDB Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install MySQL/MariaDB"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Secure installation (set root password)"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Create database and user"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Start/Stop/Restart"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) mysql_install ;;
            2) mysql_uninstall ;;
            3) mysql_secure ;;
            4) mysql_create_database ;;
            5)
                local action
                action=$(prompt_select "Service action:" "Start" "Stop" "Restart")
                case "$action" in
                    Start)   systemctl start mysql mariadb 2>/dev/null ;;
                    Stop)    systemctl stop mysql mariadb 2>/dev/null ;;
                    Restart) systemctl restart mysql mariadb 2>/dev/null ;;
                esac
                ;;
            6) mysql_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
