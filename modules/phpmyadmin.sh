#!/usr/bin/env bash
#
# Pig-NMP - phpMyAdmin Module
#

source "${CONF_DIR}/versions.conf"

pma_is_installed() {
    [[ -f "${PHPMYADMIN_DIR}/index.php" ]]
}

pma_get_version() {
    if [[ -f "${PHPMYADMIN_DIR}/libraries/Config.php" ]]; then
        grep -oP "PMA_VERSION\s*=\s*'[^']*'" "${PHPMYADMIN_DIR}/libraries/Config.php" 2>/dev/null | grep -oP "[\d.]+" | head -1
    elif [[ -f "${PHPMYADMIN_DIR}/version.php" ]]; then
        grep -oP "PMA_VERSION.*?[\d.]+" "${PHPMYADMIN_DIR}/version.php" 2>/dev/null | grep -oP "[\d.]+$"
    fi
}

pma_install() {
    if pma_is_installed; then
        log_warn "phpMyAdmin is already installed at ${PHPMYADMIN_DIR}"
        if ! confirm "Reinstall?"; then
            return 0
        fi
    fi

    if ! nginx_is_installed; then
        log_error "Nginx must be installed first"
        return 1
    fi

    local versions
    versions=$(get_php_versions_installed)
    if [[ -z "$versions" ]]; then
        log_error "At least one PHP version must be installed first"
        return 1
    fi

    if ! mysql_is_installed; then
        log_error "MySQL/MariaDB must be installed first"
        return 1
    fi

    local version="${1:-$PHPMYADMIN_VERSION}"

    echo -e "\n${HEADER_COLOR}phpMyAdmin Access Configuration:${C_RESET}"
    local access_type
    access_type=$(prompt_select "Access method:" "Subdomain (e.g., pma.example.com)" "URL path (e.g., example.com/pma)")

    local pma_domain="" pma_path="" pma_allowed_ip="" pma_auth_user="" pma_auth_pass=""
    case "$access_type" in
        Subdomain*)
            local subdomain
            prompt_input "Subdomain for phpMyAdmin" "pma" subdomain
            pma_domain="${subdomain}.$(get_ip)"
            prompt_input "Full domain" "$pma_domain" pma_domain
            ;;
        URL\ path*)
            prompt_input "URL path" "/pma" pma_path
            ;;
    esac

    echo -e "\n${HEADER_COLOR}Security Configuration:${C_RESET}"
    if confirm "Set up IP whitelist for phpMyAdmin?" "y"; then
        prompt_input "Allowed IP (or CIDR, e.g., 192.168.1.0/24)" "$(get_ip)/32" pma_allowed_ip
    fi

    if confirm "Set up HTTP Basic Auth for phpMyAdmin?" "y"; then
        prompt_input "Auth username" "admin" pma_auth_user
        prompt_password "Auth password" pma_auth_pass
    fi

    local url="https://files.phpmyadmin.net/phpMyAdmin/${version}/phpMyAdmin-${version}-all-languages.tar.xz"
    log_info "Installing phpMyAdmin ${version}..."
    ensure_dirs "$TMP_DIR" "${PHPMYADMIN_DIR}"

    if ! download_and_extract "$url" "${PHPMYADMIN_DIR}" 1; then
        log_error "Failed to download phpMyAdmin ${version}"
        return 1
    fi

    pma_setup_config

    if [[ -n "$pma_domain" ]]; then
        pma_setup_vhost_subdomain "$pma_domain"
    elif [[ -n "$pma_path" ]]; then
        pma_setup_vhost_path "$pma_path"
    fi

    if [[ -n "$pma_allowed_ip" ]]; then
        pma_setup_ip_whitelist "$pma_allowed_ip"
    fi

    if [[ -n "$pma_auth_user" && -n "$pma_auth_pass" ]]; then
        pma_setup_basic_auth "$pma_auth_user" "$pma_auth_pass"
    fi

    nginx_reload

    log_success "phpMyAdmin ${version} installed"
    log_info "Access: Check your Nginx configuration for the URL"
}

pma_setup_config() {
    ensure_dirs "${PHPMYADMIN_ETC_DIR}" "${DATA_DIR}/pma/tmp" "${DATA_DIR}/pma/save"

    local blowfish_secret
    blowfish_secret=$(gen_password 32)

    cat > "${PHPMYADMIN_DIR}/config.inc.php" << PHPEOF
<?php
\$cfg['blowfish_secret'] = '${blowfish_secret}';

\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type'] = 'cookie';
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['compress'] = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;

\$cfg['UploadDir'] = '${DATA_DIR}/pma/tmp';
\$cfg['SaveDir'] = '${DATA_DIR}/pma/save';

\$cfg['TempDir'] = '${DATA_DIR}/pma/tmp';
\$cfg['VersionCheck'] = false;
\$cfg['MaxRows'] = 100;
\$cfg['DefaultLang'] = 'en';
\$cfg['DefaultCharset'] = 'utf-8';

\$cfg['LoginCookieValidity'] = 86400;
\$cfg['LoginCookieStore'] = 0;

\$cfg['NavigationTreeEnableGrouping'] = true;
\$cfg['NavigationTreeDbSeparator'] = '_';
\$cfg['ShowDbStructureComment'] = true;
PHPEOF

    chmod 640 "${PHPMYADMIN_DIR}/config.inc.php"
    chown -R www-data:www-data "${PHPMYADMIN_DIR}" "${DATA_DIR}/pma"
}

pma_setup_vhost_subdomain() {
    local domain="$1"
    local php_ver
    php_ver=$(php_select_version)
    [[ -z "$php_ver" ]] && { log_error "No PHP version available"; return 1; }

    local fpm_sock
    fpm_sock=$(get_php_fpm_sock "$php_ver")
    local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"

    render_template "${TEMPLATES_DIR}/nginx/vhost-phpmyadmin.conf.tpl" "$vhost_file" \
        DOMAIN="$domain" \
        DOCUMENT_ROOT="${PHPMYADMIN_DIR}" \
        PHP_FPM_SOCK="${fpm_sock}" \
        PHP_VER="$php_ver" \
        LOG_DIR="${LOG_DIR}" \
        NGINX_ETC_DIR="${NGINX_ETC_DIR}"
    vhost_patch_php_block "$vhost_file" "$fpm_sock"

    ln -sf "$vhost_file" "${NGINX_SITES_ENABLED}/${domain}.conf"

    log_info "phpMyAdmin virtual host created: ${domain}"
    log_info "Don't forget to add DNS record for ${domain}"
}

pma_save_config() {
    local path="$1"
    local php_ver="$2"
    local fpm_sock="$3"
    mkdir -p "${ETC_DIR}"
    cat > "${ETC_DIR}/pma-config" << PMACFG
PMA_PATH="${path}"
PMA_PHP_VER="${php_ver}"
PMA_FPM_SOCK="${fpm_sock}"
PMACFG
}

pma_get_config() {
    local key="$1"
    local config_file="${ETC_DIR}/pma-config"
    [[ -f "$config_file" ]] || return 1
    source "$config_file"
    case "$key" in
        path) echo "$PMA_PATH" ;;
        php_ver) echo "$PMA_PHP_VER" ;;
        fpm_sock) echo "$PMA_FPM_SOCK" ;;
    esac
}

pma_has_config() {
    [[ -f "${ETC_DIR}/pma-config" ]]
}

pma_inject_location() {
    local vhost_file="$1"
    local pma_path="$2"
    local fpm_sock="$3"

    # Remove any existing PMA block first (idempotent)
    sed -i '/^    # PIG-NMP phpMyAdmin start/,/^    # PIG-NMP phpMyAdmin end/d' "$vhost_file"

    # Build the location block in a temp file
    local block_file
    block_file=$(mktemp)
    cat > "$block_file" << PMAEOF
    # PIG-NMP phpMyAdmin start
    location ${pma_path} {
        alias ${PHPMYADMIN_DIR};
        index index.php index.html;

        location ~ ^${pma_path}/(.+\.php)$ {
            alias ${PHPMYADMIN_DIR};
            try_files \$uri =404;
            fastcgi_split_path_info ^${pma_path}/(.+\.php)(/.+)$;
            fastcgi_pass unix:${fpm_sock};
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME ${PHPMYADMIN_DIR}/\$fastcgi_script_name;
            fastcgi_param PATH_INFO \$fastcgi_path_info;
            include fastcgi_params;
            fastcgi_buffers 16 16k;
            fastcgi_buffer_size 32k;
        }

        location ~* ^${pma_path}/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
            alias ${PHPMYADMIN_DIR};
        }
    }
    # PIG-NMP phpMyAdmin end
PMAEOF

    # Find the last line matching ^} (the server block closing brace).
    # This is robust against trailing blank lines or multiple server{} blocks.
    local last_brace
    last_brace=$(grep -n '^}[[:space:]]*$' "$vhost_file" | tail -1 | cut -d: -f1)
    if [[ -z "$last_brace" ]]; then
        log_warn "Cannot find server block closing brace in ${vhost_file}"
        rm -f "$block_file"
        return 1
    fi

    # Insert the block before the closing brace line
    awk -v insert_line="$last_brace" -v block_file="$block_file" '
        NR == insert_line {
            while ((getline line < block_file) > 0) print line
        }
        { print }
    ' "$vhost_file" > "${vhost_file}.pma_tmp" && mv "${vhost_file}.pma_tmp" "$vhost_file"

    rm -f "$block_file"
}

pma_remove_location() {
    local vhost_file="$1"
    sed -i '/^    # PIG-NMP phpMyAdmin start/,/^    # PIG-NMP phpMyAdmin end/d' "$vhost_file"
}

pma_inject_location_all() {
    local pma_path pma_fpm_sock
    pma_path=$(pma_get_config path) || return 0
    pma_fpm_sock=$(pma_get_config fpm_sock) || return 0

    for vhost in "${NGINX_SITES_ENABLED}"/*.conf; do
        [[ -f "$vhost" ]] || continue
        pma_inject_location "$vhost" "$pma_path" "$pma_fpm_sock"
    done

    if [[ -f "${NGINX_ETC_DIR}/conf.d/default.conf" ]]; then
        pma_inject_location "${NGINX_ETC_DIR}/conf.d/default.conf" "$pma_path" "$pma_fpm_sock"
    fi
}

pma_setup_vhost_path() {
    local path="$1"
    local php_ver
    php_ver=$(php_select_version)
    [[ -z "$php_ver" ]] && { log_error "No PHP version available"; return 1; }

    local fpm_sock
    fpm_sock=$(get_php_fpm_sock "$php_ver")

    pma_save_config "$path" "$php_ver" "$fpm_sock"
    pma_inject_location_all

    log_info "phpMyAdmin path configured: ${path}"
}

pma_setup_ip_whitelist() {
    local allowed_ip="$1"
    local pma_path
    pma_path=$(pma_get_config path) || return 0

    local vhosts=("${NGINX_SITES_ENABLED}"/*.conf)
    [[ -f "${NGINX_ETC_DIR}/conf.d/default.conf" ]] && vhosts+=("${NGINX_ETC_DIR}/conf.d/default.conf")

    for vhost in "${vhosts[@]}"; do
        [[ -f "$vhost" ]] || continue
        if grep -q "allow.*${allowed_ip}" "$vhost" 2>/dev/null; then
            continue
        fi
        sed -i "/^    # PIG-NMP phpMyAdmin start/,/^    # PIG-NMP phpMyAdmin end/{
            /^    location ${pma_path//\//\\/} {/a\        allow ${allowed_ip};\n        deny all;
        }" "$vhost"
    done
    log_info "IP whitelist set: ${allowed_ip}"
}

pma_setup_basic_auth() {
    local user="$1"
    local pass="$2"
    local htpasswd_file="${NGINX_ETC_DIR}/.htpasswd-pma"

    install_deps apache2-utils
    htpasswd -bc "$htpasswd_file" "$user" "$pass" 2>/dev/null
    chmod 640 "$htpasswd_file"

    local vhosts=("${NGINX_SITES_ENABLED}"/*.conf)
    [[ -f "${NGINX_ETC_DIR}/conf.d/default.conf" ]] && vhosts+=("${NGINX_ETC_DIR}/conf.d/default.conf")

    for vhost in "${vhosts[@]}"; do
        [[ -f "$vhost" ]] || continue
        if grep -q "auth_basic" "$vhost" 2>/dev/null; then
            continue
        fi
        sed -i "/^    # PIG-NMP phpMyAdmin start/,/^    # PIG-NMP phpMyAdmin end/{
            /^    location .* {$/a\        auth_basic \"phpMyAdmin Login\";\n        auth_basic_user_file ${htpasswd_file};
        }" "$vhost"
    done

    log_info "HTTP Basic Auth configured (user: ${user})"
}

pma_update() {
    if ! pma_is_installed; then
        log_warn "phpMyAdmin is not installed"
        return 1
    fi

    local current_ver
    current_ver=$(pma_get_version)
    log_info "Current version: ${current_ver}"

    local new_ver
    prompt_input "New version" "$PHPMYADMIN_VERSION" new_ver

    if [[ "$new_ver" == "$current_ver" ]]; then
        log_info "Already at version ${current_ver}"
        return 0
    fi

    local backup_dir="${BACKUP_DIR}/phpmyadmin-${current_ver}-$(date +%Y%m%d%H%M%S)"
    ensure_dirs "$backup_dir"
    cp -a "${PHPMYADMIN_DIR}/config.inc.php" "$backup_dir/" 2>/dev/null

    local url="https://files.phpmyadmin.net/phpMyAdmin/${new_ver}/phpMyAdmin-${new_ver}-all-languages.tar.xz"
    rm -rf "${PHPMYADMIN_DIR:?}"/*
    download_and_extract "$url" "${PHPMYADMIN_DIR}" 1 || {
        log_error "Update failed, restoring backup..."
        cp -a "$backup_dir"/* "${PHPMYADMIN_DIR}/" 2>/dev/null
        return 1
    }

    cp -a "$backup_dir/config.inc.php" "${PHPMYADMIN_DIR}/" 2>/dev/null
    chown -R www-data:www-data "${PHPMYADMIN_DIR}"

    log_success "phpMyAdmin updated to ${new_ver}"
}

pma_uninstall() {
    if ! pma_is_installed; then
        log_warn "phpMyAdmin is not installed"
        return 0
    fi

    if ! confirm "Uninstall phpMyAdmin?"; then return 0; fi

    rm -rf "${PHPMYADMIN_DIR}"
    rm -rf "${PHPMYADMIN_ETC_DIR}"
    rm -rf "${DATA_DIR}/pma"
    rm -f "${NGINX_SITES_AVAILABLE}"/pma*.conf
    rm -f "${NGINX_SITES_ENABLED}"/pma*.conf
    rm -f "${NGINX_ETC_DIR}"/includes/*.conf "${NGINX_ETC_DIR}"/conf.d/phpmyadmin.conf
    rm -f "${NGINX_ETC_DIR}"/.htpasswd-pma
    rm -f "${ETC_DIR}/pma-config"

    for vhost in "${NGINX_SITES_ENABLED}"/*.conf; do
        [[ -f "$vhost" ]] || continue
        pma_remove_location "$vhost"
    done
    if [[ -f "${NGINX_ETC_DIR}/conf.d/default.conf" ]]; then
        pma_remove_location "${NGINX_ETC_DIR}/conf.d/default.conf"
    fi

    nginx_reload

    log_success "phpMyAdmin uninstalled"
}

pma_status() {
    echo -e "\n${HEADER_COLOR}=== phpMyAdmin Status ===${C_RESET}"
    print_status "phpMyAdmin" "$(pma_is_installed && echo 'installed' || echo 'not_installed')"
    if pma_is_installed; then
        print_status "Version" "$(pma_get_version)"
        print_status "Path" "${PHPMYADMIN_DIR}"
    fi
}

pma_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== phpMyAdmin Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install phpMyAdmin"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Update phpMyAdmin"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Uninstall phpMyAdmin"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Configure security (IP whitelist / Basic Auth)"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) pma_install ;;
            2) pma_update ;;
            3) pma_uninstall ;;
            4)
                echo -e "\n${HEADER_COLOR}Security Options:${C_RESET}"
                local sec_opt
                sec_opt=$(prompt_select "Choose:" "Set IP whitelist" "Set HTTP Basic Auth" "Remove all restrictions")
                case "$sec_opt" in
                    "Set IP whitelist")
                        local ip
                        prompt_input "Allowed IP/CIDR" "$(get_ip)/32" ip
                        pma_setup_ip_whitelist "$ip"
                        nginx_reload
                        ;;
                    "Set HTTP Basic Auth")
                        local user pass
                        prompt_input "Username" "admin" user
                        prompt_password "Password" pass
                        pma_setup_basic_auth "$user" "$pass"
                        nginx_reload
                        ;;
                    "Remove all restrictions")
                        rm -f "${NGINX_ETC_DIR}"/.htpasswd-pma
                        log_info "Restrictions removed. Reload nginx to apply."
                        nginx_reload
                        ;;
                esac
                ;;
            5) pma_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
