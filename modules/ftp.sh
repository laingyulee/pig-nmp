#!/usr/bin/env bash
#
# Pig-NMP - FTP (vsftpd) Module
#

source "${CONF_DIR}/versions.conf"

ftp_is_installed() {
    is_installed vsftpd || [[ -x /usr/sbin/vsftpd ]]
}

ftp_get_version() {
    if is_installed vsftpd; then
        vsftpd -version 2>&1 | grep -oP '[\d.]+'
    fi
}

ftp_install() {
    if ftp_is_installed; then
        log_warn "vsftpd is already installed: $(ftp_get_version)"
        if ! confirm "Reinstall?"; then
            return 0
        fi
    fi

    require_os

    echo -e "\n${HEADER_COLOR}Select vsftpd installation method:${C_RESET}"
    local method
    method=$(prompt_select "Installation method:" "APT (recommended)" "Source compilation")

    local ftp_passive=false ftp_ssl=false
    if confirm "Configure passive mode for FTP?" "y"; then
        ftp_passive=true
    fi
    if confirm "Enable FTP over TLS/SSL?" "n"; then
        ftp_ssl=true
    fi

    case "$method" in
        "APT"*)
            log_info "Installing vsftpd via APT..."
            apt_install vsftpd
            ;;
        "Source"*)
            local version="${1:-$VSFTPD_VERSION}"
            ftp_install_source "$version"
            ;;
    esac

    ftp_setup_config
    ftp_setup_systemd

    if $ftp_passive; then
        ftp_configure_passive
    fi

    if $ftp_ssl; then
        ftp_setup_ssl
    fi

    systemctl start vsftpd &>/dev/null
    systemctl enable vsftpd &>/dev/null

    if is_service_active vsftpd; then
        log_success "vsftpd installed and running"
    else
        log_warn "vsftpd installed but service may need configuration"
    fi
}

ftp_install_source() {
    local version="$1"
    install_build_deps
    install_deps libpam0g-dev libcap-dev libssl-dev

    local url="https://security.appspot.com/downloads/vsftpd-${version}.tar.gz"
    local src_dir="${TMP_DIR}/vsftpd-${version}"

    log_info "Installing vsftpd ${version} from source..."
    ensure_dirs "$TMP_DIR"

    if ! download_and_extract "$url" "$src_dir" 1; then
        log_error "Failed to download vsftpd ${version}"
        return 1
    fi

    cd "$src_dir" || return 1

    sed_inplace "vsf_findlibs.sh" "s|/lib|/lib/x86_64-linux-gnu|g"

    make -j"$(nproc)" &>/dev/null || {
        log_error "vsftpd compile failed"
        cd - || return 1
        return 1
    }

    cp vsftpd /usr/sbin/vsftpd
    cp vsftpd.conf.5 /usr/share/man/man5/ 2>/dev/null
    cp vsftpd.8 /usr/share/man/man8/ 2>/dev/null

    cd - || return 1
    rm -rf "$src_dir"

    log_success "vsftpd ${version} compiled and installed"
}

ftp_setup_config() {
    ensure_dirs "${FTP_ETC_DIR}" "${FTP_USER_DIR}" "${LOG_DIR}/vsftpd"

    local conf="${FTP_ETC_DIR}/vsftpd.conf"
    if [[ -f /etc/vsftpd.conf ]] && [[ ! -f "$conf" ]]; then
        cp /etc/vsftpd.conf "$conf"
    fi

    if [[ ! -f "$conf" ]] || [[ $(wc -l < "$conf" 2>/dev/null) -lt 5 ]]; then
        render_template "${TEMPLATES_DIR}/ftp/vsftpd.conf.tpl" "$conf" \
            FTP_ETC_DIR="${FTP_ETC_DIR}" \
            FTP_USER_DIR="${FTP_USER_DIR}" \
            LOG_DIR="${LOG_DIR}" \
            FTP_PASV_MIN_PORT="40000" \
            FTP_PASV_MAX_PORT="40100" \
            FTP_PASV_ADDRESS="$(get_ip)"
    fi

    if [[ -f /etc/vsftpd.conf ]]; then
        backup_file /etc/vsftpd.conf
        ln -sf "$conf" /etc/vsftpd.conf
    fi

    install_deps db-util

    cat > /etc/pam.d/vsftpd.virtual << EOF
auth required pam_userdb.so db=${FTP_USER_DIR}/users
account required pam_userdb.so db=${FTP_USER_DIR}/users
EOF
}

ftp_setup_systemd() {
    local service_file="/etc/systemd/system/vsftpd.service"
    if [[ ! -f "$service_file" ]]; then
        render_template "${TEMPLATES_DIR}/systemd/vsftpd.service.tpl" "$service_file" \
            VSFTPD_BIN="/usr/sbin/vsftpd" \
            VSFTPD_CONF="${FTP_ETC_DIR}/vsftpd.conf"
        systemctl daemon-reload
    fi
}

ftp_configure_passive() {
    local min_port max_port
    prompt_input "Passive port range start" "40000" min_port
    prompt_input "Passive port range end" "40100" max_port
    local server_ip
    server_ip=$(get_ip)
    prompt_input "Server public IP" "$server_ip" server_ip

    local conf="${FTP_ETC_DIR}/vsftpd.conf"
    if [[ -f "$conf" ]]; then
        sed_inplace "$conf" "/^pasv_enable/d"
        sed_inplace "$conf" "/^pasv_min_port/d"
        sed_inplace "$conf" "/^pasv_max_port/d"
        sed_inplace "$conf" "/^pasv_address/d"

        cat >> "$conf" << EOF
pasv_enable=YES
pasv_min_port=${min_port}
pasv_max_port=${max_port}
pasv_address=${server_ip}
EOF
    fi

    log_info "Passive mode configured: ports ${min_port}-${max_port}"
    log_info "Make sure these ports are open in your firewall"
}

ftp_setup_ssl() {
    ensure_dirs "${SSL_DIR}"

    local cert_file="${SSL_DIR}/ftp.crt"
    local key_file="${SSL_DIR}/ftp.key"

    if [[ ! -f "$cert_file" ]] || [[ ! -f "$key_file" ]]; then
        log_info "Generating self-signed certificate for FTP..."
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$key_file" -out "$cert_file" \
            -subj "/C=US/ST=State/L=City/O=Pig-NMP/CN=$(hostname)" 2>/dev/null
    fi

    local conf="${FTP_ETC_DIR}/vsftpd.conf"
    if [[ -f "$conf" ]]; then
        sed_inplace "$conf" "/^ssl_enable/d"
        sed_inplace "$conf" "/^rsa_cert_file/d"
        sed_inplace "$conf" "/^rsa_private_key_file/d"
        sed_inplace "$conf" "/^allow_anon_ssl/d"
        sed_inplace "$conf" "/^force_local_data_ssl/d"
        sed_inplace "$conf" "/^force_local_logins_ssl/d"
        sed_inplace "$conf" "/^ssl_tlsv1/d"
        sed_inplace "$conf" "/^ssl_sslv2/d"
        sed_inplace "$conf" "/^ssl_sslv3/d"
        sed_inplace "$conf" "/^require_ssl_reuse/d"
        sed_inplace "$conf" "/^ssl_ciphers/d"

        cat >> "$conf" << EOF
ssl_enable=YES
rsa_cert_file=${cert_file}
rsa_private_key_file=${key_file}
allow_anon_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH
EOF
    fi

    log_success "FTP SSL/TLS configured"
    systemctl restart vsftpd &>/dev/null
}

ftp_add_user() {
    echo -e "\n${HEADER_COLOR}=== Add FTP User ===${C_RESET}"

    local username password home_dir
    prompt_input "Username" "" username
    [[ -z "$username" ]] && return 1
    prompt_password "Password" password
    [[ -z "$password" ]] && return 1

    local default_home="${DOMAINS_DIR}/${username}"
    prompt_input "Home directory" "$default_home" home_dir

    echo -e "\n${HEADER_COLOR}User type:${C_RESET}"
    local user_type
    user_type=$(prompt_select "Select user type:" "Virtual user (recommended)" "System user")

    case "$user_type" in
        "Virtual"*)
            ftp_add_virtual_user "$username" "$password" "$home_dir"
            ;;
        "System"*)
            ftp_add_system_user "$username" "$password" "$home_dir"
            ;;
    esac
}

ftp_add_virtual_user() {
    local username="$1"
    local password="$2"
    local home_dir="$3"

    ensure_dirs "$home_dir" "$FTP_USER_DIR"
    ensure_domains_dir

    local tmp_file="${TMP_DIR}/ftp_users.txt"
    {
        if [[ -f "${FTP_USER_DIR}/users.txt" ]]; then
            grep -v "^${username}$" "${FTP_USER_DIR}/users.txt" || true
        fi
        echo "$username"
        echo "$password"
    } > "$tmp_file"

    db_load -T -t hash -f "$tmp_file" "${FTP_USER_DIR}/users.db" 2>/dev/null
    cp "$tmp_file" "${FTP_USER_DIR}/users.txt" 2>/dev/null
    chmod 600 "${FTP_USER_DIR}/users.db" "${FTP_USER_DIR}/users.txt"
    rm -f "$tmp_file"

    cat > "${FTP_USER_DIR}/${username}" << EOF
local_root=${home_dir}
write_enable=YES
anon_upload_enable=YES
anon_mkdir_write_enable=YES
anon_other_write_enable=YES
EOF

    ensure_dirs "$home_dir"
    chown -R www-data:www-data "$home_dir"

    log_success "Virtual FTP user '${username}' created (home: ${home_dir})"
    systemctl restart vsftpd &>/dev/null
}

ftp_add_system_user() {
    local username="$1"
    local password="$2"
    local home_dir="$3"

    ensure_dirs "$home_dir"

    id "$username" &>/dev/null || \
        useradd -d "$home_dir" -s /usr/sbin/nologin -M "$username"

    echo "${username}:${password}" | chpasswd

    chown -R "${username}:www-data" "$home_dir"
    chmod 755 "$home_dir"

    log_success "System FTP user '${username}' created (home: ${home_dir})"
    systemctl restart vsftpd &>/dev/null
}

ftp_delete_user() {
    local username="$1"
    if [[ -z "$username" ]]; then
        ftp_list_users
        prompt_input "Username to delete" "" username
    fi
    [[ -z "$username" ]] && return 1

    if ! confirm "Delete FTP user '${username}'?"; then
        return 0
    fi

    if id "$username" &>/dev/null; then
        userdel "$username" 2>/dev/null
    fi

    rm -f "${FTP_USER_DIR}/${username}"

    local tmp_file="${TMP_DIR}/ftp_users.txt"
    if [[ -f "${FTP_USER_DIR}/users.txt" ]]; then
        local skip_next=false
        while IFS= read -r line; do
            if [[ "$skip_next" == "true" ]]; then
                skip_next=false
                continue
            fi
            if [[ "$line" == "$username" ]]; then
                skip_next=true
                continue
            fi
            echo "$line"
        done < "${FTP_USER_DIR}/users.txt" > "$tmp_file" 2>/dev/null || true
        cp "$tmp_file" "${FTP_USER_DIR}/users.txt" 2>/dev/null
        db_load -T -t hash -f "${FTP_USER_DIR}/users.txt" "${FTP_USER_DIR}/users.db" 2>/dev/null
    fi

    log_success "FTP user '${username}' deleted"
    systemctl restart vsftpd &>/dev/null
}

ftp_list_users() {
    echo -e "\n${HEADER_COLOR}=== FTP Users ===${C_RESET}"

    echo -e "  ${C_CYAN}Virtual Users:${C_RESET}"
    if [[ -d "$FTP_USER_DIR" ]]; then
        for f in "${FTP_USER_DIR}"/*; do
            [[ -f "$f" ]] || continue
            local name
            name=$(basename "$f")
            [[ "$name" == "users.db" || "$name" == "users.txt" ]] && continue
            local home
            home=$(grep "^local_root=" "$f" 2>/dev/null | cut -d= -f2)
            printf "  %-20s %s\n" "$name" "${home:-N/A}"
        done
    fi

    echo -e "\n  ${C_CYAN}System Users with FTP access:${C_RESET}"
    grep -E '/bin/bash|/bin/sh' /etc/passwd | grep -v 'root\|nobody' | while read line; do
        local uname
        uname=$(echo "$line" | cut -d: -f1)
        local uhome
        uhome=$(echo "$line" | cut -d: -f6)
        printf "  %-20s %s\n" "$uname" "$uhome"
    done
}

ftp_uninstall() {
    if ! ftp_is_installed; then
        log_warn "vsftpd is not installed"
        return 0
    fi

    if ! confirm "Uninstall vsftpd?"; then return 0; fi

    systemctl stop vsftpd &>/dev/null
    systemctl disable vsftpd &>/dev/null

    if dpkg -l vsftpd &>/dev/null 2>&1 | grep -q '^ii'; then
        apt_remove vsftpd
    else
        rm -f /usr/sbin/vsftpd
    fi

    rm -f /etc/systemd/system/vsftpd.service
    rm -f /etc/pam.d/vsftpd.virtual
    systemctl daemon-reload

    if confirm "Remove FTP configuration and user data?"; then
        rm -rf "${FTP_ETC_DIR}" "${FTP_USER_DIR}"
    fi

    log_success "vsftpd uninstalled"
}

ftp_status() {
    echo -e "\n${HEADER_COLOR}=== FTP Status ===${C_RESET}"
    print_status "vsftpd" "$(ftp_is_installed && echo 'installed' || echo 'not_installed')"
    if ftp_is_installed; then
        print_status "Version" "$(ftp_get_version)"
        print_status "Service" "$(is_service_active vsftpd && echo 'running' || echo 'stopped')"
        print_status "Port 21" "$(port_in_use 21 && echo 'in_use' || echo 'free')"
        if [[ -f "${FTP_ETC_DIR}/vsftpd.conf" ]]; then
            local ssl_enabled="NO"
            grep -q "^ssl_enable=YES" "${FTP_ETC_DIR}/vsftpd.conf" 2>/dev/null && ssl_enabled="YES"
            print_status "SSL/TLS" "$ssl_enabled"
        fi
    fi
}

ftp_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== FTP Server Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install vsftpd"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall vsftpd"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Add FTP user"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Delete FTP user"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} List FTP users"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Start/Stop/Restart"
        echo -e "  ${MENU_NUM_COLOR}7)${C_RESET} Configure passive mode"
        echo -e "  ${MENU_NUM_COLOR}8)${C_RESET} Configure SSL/TLS"
        echo -e "  ${MENU_NUM_COLOR}9)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) ftp_install ;;
            2) ftp_uninstall ;;
            3) ftp_add_user ;;
            4) ftp_delete_user ;;
            5) ftp_list_users ;;
            6)
                local action
                action=$(prompt_select "Service action:" "Start" "Stop" "Restart")
                case "$action" in
                    Start)   systemctl start vsftpd ;;
                    Stop)    systemctl stop vsftpd ;;
                    Restart) systemctl restart vsftpd ;;
                esac
                ;;
            7) ftp_configure_passive; systemctl restart vsftpd ;;
            8) ftp_setup_ssl ;;
            9) ftp_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
