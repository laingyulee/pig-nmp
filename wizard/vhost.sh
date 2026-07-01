#!/usr/bin/env bash
#
# Pig-NMP - Virtual Host Configuration Wizard
#

VHOST_REWRITE_RULES_DIR="${TEMPLATES_DIR}/nginx/rewrite"

vhost_list() {
    echo -e "\n${HEADER_COLOR}=== Virtual Hosts ===${C_RESET}"

    if [[ ! -d "$NGINX_SITES_AVAILABLE" ]] || [[ -z "$(ls -A "$NGINX_SITES_AVAILABLE" 2>/dev/null)" ]]; then
        echo -e "  ${C_YELLOW}No virtual hosts configured${C_RESET}"
        return
    fi

    printf "  %-35s %-10s %s\n" "Domain" "Status" "Document Root"
    printf "  %s\n" "$(printf '%.0s-' {1..80})"

    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local domain
        domain=$(basename "$conf" .conf)
        local enabled="disabled"
        [[ -f "${NGINX_SITES_ENABLED}/${domain}.conf" ]] && enabled="enabled"
        local docroot
        docroot=$(grep -oP 'root\s+\K[^;]+' "$conf" 2>/dev/null | head -1)
        local color="$C_RED"
        [[ "$enabled" == "enabled" ]] && color="$C_GREEN"
        printf "  %-35s ${color}%-10s${C_RESET} %s\n" "$domain" "$enabled" "${docroot:-N/A}"
    done
}

vhost_create() {
    echo -e "\n${HEADER_COLOR}=== Create Virtual Host ===${C_RESET}"

    if ! nginx_is_installed; then
        log_error "Nginx must be installed first"
        return 1
    fi

    local domain
    prompt_input "Domain name (e.g., example.com)" "" domain
    if [[ -z "$domain" ]]; then
        log_error "Domain name is required"
        return 1
    fi

    if ! validate_domain "$domain"; then
        log_warn "Domain format may be invalid, continuing anyway..."
    fi

    if [[ -f "${NGINX_SITES_AVAILABLE}/${domain}.conf" ]]; then
        log_warn "Virtual host for ${domain} already exists"
        if ! confirm "Overwrite?"; then
            return 0
        fi
    fi

    local docroot="${DOMAINS_DIR}/${domain}"
    prompt_input "Document root" "$docroot" docroot

    local php_ver=""
    local fpm_sock=""
    if [[ -n "$(get_php_versions_installed)" ]]; then
        echo -e "\n${HEADER_COLOR}Select PHP version for this site:${C_RESET}"
        php_ver=$(php_select_version)
        if [[ -n "$php_ver" ]]; then
            fpm_sock=$(get_php_fpm_sock "$php_ver")
        fi
    fi

    local ssl="no"
    if confirm "Enable SSL (HTTPS)?"; then
        ssl="yes"
    fi

    local rewrite=""
    if confirm "Configure rewrite rules (for framework)?"; then
        rewrite=$(vhost_select_rewrite)
    fi

    ensure_domains_dir
    ensure_dirs "$docroot"
    chown -R www-data:www-data "$docroot"

    local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"

    if [[ "$ssl" == "yes" ]]; then
        local ssl_cert ssl_key
        if [[ -f "${SSL_DIR}/${domain}/fullchain.pem" ]]; then
            ssl_cert="${SSL_DIR}/${domain}/fullchain.pem"
            ssl_key="${SSL_DIR}/${domain}/privkey.pem"
        else
            echo -e "\n${HEADER_COLOR}SSL Certificate:${C_RESET}"
            local cert_type
            cert_type=$(prompt_select "Certificate type:" "Self-signed (for testing)" "Use existing certificate" "Skip SSL for now")
            case "$cert_type" in
                Self-signed*)
                    ssl_cert="${SSL_DIR}/${domain}.crt"
                    ssl_key="${SSL_DIR}/${domain}.key"
                    ensure_dirs "${SSL_DIR}"
                    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                        -keyout "$ssl_key" -out "$ssl_cert" \
                        -subj "/C=US/ST=State/L=City/O=Pig-NMP/CN=${domain}" 2>/dev/null
                    ;;
                Use\ existing*)
                    prompt_input "Certificate path" "" ssl_cert
                    prompt_input "Private key path" "" ssl_key
                    ;;
                Skip*)
                    ssl="no"
                    ;;
            esac
        fi
    fi

    if [[ "$ssl" == "yes" ]]; then
        render_template "${TEMPLATES_DIR}/nginx/vhost-ssl.conf.tpl" "$vhost_file" \
            DOMAIN="$domain" \
            DOCUMENT_ROOT="$docroot" \
            PHP_FPM_SOCK="$fpm_sock" \
            PHP_VER="$php_ver" \
            SSL_CERT="$ssl_cert" \
            SSL_KEY="$ssl_key" \
            LOG_DIR="${LOG_DIR}" \
            NGINX_ETC_DIR="${NGINX_ETC_DIR}"
        vhost_patch_php_block "$vhost_file" "$fpm_sock" "yes"
    else
        render_template "${TEMPLATES_DIR}/nginx/vhost-http.conf.tpl" "$vhost_file" \
            DOMAIN="$domain" \
            DOCUMENT_ROOT="$docroot" \
            PHP_FPM_SOCK="$fpm_sock" \
            PHP_VER="$php_ver" \
            LOG_DIR="${LOG_DIR}" \
            NGINX_ETC_DIR="${NGINX_ETC_DIR}"
        vhost_patch_php_block "$vhost_file" "$fpm_sock"
    fi

    if [[ -n "$rewrite" ]]; then
        vhost_apply_rewrite "$vhost_file" "$rewrite"
    fi

    ln -sf "$vhost_file" "${NGINX_SITES_ENABLED}/${domain}.conf"

    cat > "${docroot}/index.php" << EOF
<?php
phpinfo();
EOF
    chown www-data:www-data "${docroot}/index.php"

    if nginx_test_config &>/dev/null; then
        nginx_reload
        log_success "Virtual host created: ${domain}"
        echo -e "  ${C_GREEN}Document Root:${C_RESET} ${docroot}"
        echo -e "  ${C_GREEN}PHP Version:${C_RESET} ${php_ver:-none}"
        echo -e "  ${C_GREEN}SSL:${C_RESET} ${ssl}"
        echo -e "  ${C_GREEN}URL:${C_RESET} http://${domain}"
    else
        log_error "Nginx configuration test failed"
        nginx_test_config
    fi
}

vhost_delete() {
    vhost_list

    local domain
    prompt_input "Domain to delete" "" domain
    [[ -z "$domain" ]] && return 1

    local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    if [[ ! -f "$vhost_file" ]]; then
        log_error "Virtual host ${domain} not found"
        return 1
    fi

    local docroot
    docroot=$(grep -oP 'root\s+\K[^;]+' "$vhost_file" 2>/dev/null | head -1)

    if ! confirm "Delete virtual host ${domain}?"; then
        return 0
    fi

    rm -f "${NGINX_SITES_AVAILABLE}/${domain}.conf"
    rm -f "${NGINX_SITES_ENABLED}/${domain}.conf"

    if [[ -n "$docroot" ]] && [[ -d "$docroot" ]]; then
        if confirm "Delete document root ${docroot}?"; then
            rm -rf "$docroot"
        fi
    fi

    nginx_reload
    log_success "Virtual host ${domain} deleted"
}

vhost_enable() {
    vhost_list

    local domain
    prompt_input "Domain to enable" "" domain
    [[ -z "$domain" ]] && return 1

    if [[ ! -f "${NGINX_SITES_AVAILABLE}/${domain}.conf" ]]; then
        log_error "Virtual host ${domain} not found"
        return 1
    fi

    if [[ -f "${NGINX_SITES_ENABLED}/${domain}.conf" ]]; then
        log_info "Virtual host ${domain} is already enabled"
        return 0
    fi

    ln -sf "${NGINX_SITES_AVAILABLE}/${domain}.conf" "${NGINX_SITES_ENABLED}/${domain}.conf"
    nginx_reload
    log_success "Virtual host ${domain} enabled"
}

vhost_disable() {
    vhost_list

    local domain
    prompt_input "Domain to disable" "" domain
    [[ -z "$domain" ]] && return 1

    if [[ ! -f "${NGINX_SITES_ENABLED}/${domain}.conf" ]]; then
        log_info "Virtual host ${domain} is already disabled"
        return 0
    fi

    rm -f "${NGINX_SITES_ENABLED}/${domain}.conf"
    nginx_reload
    log_success "Virtual host ${domain} disabled"
}

vhost_select_rewrite() {
    echo -e "\n${HEADER_COLOR}Select rewrite rules:${C_RESET}"
    local rules
    rules=$(prompt_select "Framework/CMS:" \
        "WordPress" "Laravel" "ThinkPHP" "Typecho" "CodeIgniter" "Drupal" "None")
    echo "$rules"
}

vhost_apply_rewrite() {
    local vhost_file="$1"
    local framework="$2"
    local rewrite_rules=""

    case "$framework" in
        WordPress)
            rewrite_rules='
    location / {
        try_files $uri $uri/ /index.php?$args;
    }'
            ;;
        Laravel)
            rewrite_rules='
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }'
            ;;
        ThinkPHP)
            rewrite_rules='
    location / {
        if (!-e $request_filename) {
            rewrite ^(.*)$ /index.php?s=$1 last;
        }
    }'
            ;;
        Typecho)
            rewrite_rules='
    location / {
        if (!-e $request_filename) {
            rewrite ^(.*)$ /index.php$1 last;
        }
    }'
            ;;
        CodeIgniter)
            rewrite_rules='
    location / {
        try_files $uri $uri/ /index.php/$uri?$query_string;
    }'
            ;;
        Drupal)
            rewrite_rules='
    location / {
        try_files $uri /index.php?$query_string;
    }'
            ;;
        None)
            return
            ;;
    esac

    if [[ -n "$rewrite_rules" ]]; then
        local tmp_rewrite
        tmp_rewrite=$(mktemp)
        printf '%s\n' "$rewrite_rules" > "$tmp_rewrite"
        sed -i "/# REWRITE_RULES_MARKER/r $tmp_rewrite" "$vhost_file"
        rm -f "$tmp_rewrite"
        log_info "Rewrite rules applied: ${framework}"
    fi
}

vhost_edit() {
    vhost_list

    local domain
    prompt_input "Domain to edit" "" domain
    [[ -z "$domain" ]] && return 1

    local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    if [[ ! -f "$vhost_file" ]]; then
        log_error "Virtual host ${domain} not found"
        return 1
    fi

    log_info "Opening ${vhost_file} with nano..."
    log_warn "After editing, run 'nginx -t' to test and 'systemctl reload nginx' to apply"
    echo ""
    nano "$vhost_file"

    echo ""
    if confirm "Test and reload Nginx configuration?"; then
        if nginx_test_config; then
            nginx_reload
        else
            log_error "Configuration test failed, Nginx not reloaded"
        fi
    fi
}

vhost_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== Virtual Host Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Create virtual host"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Delete virtual host"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} List virtual hosts"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Enable virtual host"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Disable virtual host"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Edit virtual host config"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) vhost_create ;;
            2) vhost_delete ;;
            3) vhost_list ;;
            4) vhost_enable ;;
            5) vhost_disable ;;
            6) vhost_edit ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
