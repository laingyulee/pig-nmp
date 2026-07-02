#!/usr/bin/env bash
#
# Pig-NMP - Virtual Host Wizard
#

ensure_domains_dir() {
    if [[ ! -d "${DOMAINS_DIR}" ]]; then
        mkdir -p "${DOMAINS_DIR}"
        chown www-data:www-data "${DOMAINS_DIR}"
        chmod 755 "${DOMAINS_DIR}"
    fi
    if [[ ! -d "${DOMAINS_DIR}/default" ]]; then
        mkdir -p "${DOMAINS_DIR}/default"
        chown www-data:www-data "${DOMAINS_DIR}/default"
    fi
}

vhost_list() {
    echo -e "\n${HEADER_COLOR}=== Virtual Hosts ===${C_RESET}"
    local count=0
    local conf
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name=$(basename "$conf" .conf)
        [[ "$name" == "default" ]] && continue
        local enabled="${C_RED}disabled${C_RESET}"
        [[ -L "${NGINX_SITES_ENABLED}/${name}.conf" ]] && enabled="${C_GREEN}enabled${C_RESET}"
        local root=$(grep -oP 'root\s+\K[^;]+' "$conf" 2>/dev/null | head -1)
        printf "  %-25s %-12s %s\n" "$name" "[$enabled]" "${root:-unknown}"
        ((count++))
    done
    [[ $count -eq 0 ]] && echo -e "  ${C_YELLOW}No virtual hosts configured${C_RESET}"
}

vhost_create() {
    ensure_domains_dir

    echo -e "\n${HEADER_COLOR}=== Create Virtual Host ===${C_RESET}"

    local domain
    prompt_input "Domain name (e.g., example.com)" "" domain
    [[ -z "$domain" ]] && return 1
    validate_domain "$domain" || { log_error "Invalid domain name: ${domain}"; return 1; }

    local doc_root="${DOMAINS_DIR}/${domain}"
    mkdir -p "$doc_root"

    # PHP version selection
    local php_ver=""
    local versions
    versions=$(get_php_versions_installed)
    if [[ -n "$versions" ]]; then
        local -a opts=()
        while IFS= read -r v; do opts+=("PHP ${v}"); done <<< "$versions"
        opts+=("No PHP")
        local sel
        sel=$(prompt_select "PHP version:" "${opts[@]}")
        [[ "$sel" != "No PHP" ]] && php_ver="${sel#PHP }"
    fi

    # SSL
    local use_ssl="no"
    if confirm "Enable SSL for this site?" "n"; then
        use_ssl="yes"
    fi

    # Rewrite rules
    local rewrite_rules=""
    local rewrite_sel
    rewrite_sel=$(prompt_select "Framework rewrite rules:" "None" "WordPress" "Laravel" "ThinkPHP" "Typecho" "CodeIgniter" "Drupal")
    case "$rewrite_sel" in
        WordPress)    rewrite_rules="try_files \$uri \$uri/ /index.php?\$args;" ;;
        Laravel)      rewrite_rules="try_files \$uri \$uri/ /index.php\$is_args\$request_uri;" ;;
        ThinkPHP)     rewrite_rules="try_files \$uri \$uri/ /index.php?s=\$uri&\$args;" ;;
        Typecho)      rewrite_rules="try_files \$uri \$uri/ /index.php;" ;;
        CodeIgniter)  rewrite_rules="try_files \$uri \$uri/ /index.php/\$1;" ;;
        Drupal)       rewrite_rules="try_files \$uri /index.php?\$query_string;" ;;
    esac

    # Create config
    local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    local fpm_pass=""
    [[ -n "$php_ver" ]] && fpm_pass="unix:$(get_php_fpm_sock "$php_ver")"

    if [[ "$use_ssl" == "yes" ]]; then
        render_template "${TEMPLATES_DIR}/nginx/vhost-ssl.conf.tpl" "$vhost_file" \
            DOMAIN="$domain" DOC_ROOT="$doc_root" PHP_VER="$php_ver" \
            SSL_DIR="${SSL_DIR}" LOG_DIR="${LOG_DIR}"
    else
        render_template "${TEMPLATES_DIR}/nginx/vhost-http.conf.tpl" "$vhost_file" \
            DOMAIN="$domain" DOC_ROOT="$doc_root" PHP_VER="$php_ver" LOG_DIR="${LOG_DIR}"
    fi

    # Patch PHP block
    if [[ -n "$fpm_pass" ]]; then
        vhost_patch_php_block "$vhost_file" "$fpm_pass" "$use_ssl"
    else
        sed_inplace "$vhost_file" '/PHP_LOCATION_BLOCK/d'
    fi

    # Apply rewrite rules
    if [[ -n "$rewrite_rules" ]]; then
        local tmp_rewrite
        tmp_rewrite=$(mktemp)
        cat > "$tmp_rewrite" << EOF
        # ${rewrite_sel} rewrite rules
        location / {
            ${rewrite_rules}
        }
EOF
        sed -i "/REWRITE_RULES_MARKER/r $tmp_rewrite" "$vhost_file"
        sed -i "/REWRITE_RULES_MARKER/d" "$vhost_file"
        rm -f "$tmp_rewrite"
    else
        sed_inplace "$vhost_file" '/REWRITE_RULES_MARKER/d'
    fi

    ln -sf "$vhost_file" "${NGINX_SITES_ENABLED}/${domain}.conf"

    # Create index.php
    cat > "${doc_root}/index.php" << 'PHPEOF'
<?php
phpinfo();
PHPEOF
    chown -R www-data:www-data "$doc_root"

    nginx_test_config && nginx_reload
    log_success "Virtual host '${domain}' created"
    echo -e "  ${C_BOLD}Domain:${C_RESET}    ${domain}"
    echo -e "  ${C_BOLD}Root:${C_RESET}      ${doc_root}"
    [[ -n "$php_ver" ]] && echo -e "  ${C_BOLD}PHP:${C_RESET}       ${php_ver}"
    echo -e "  ${C_BOLD}SSL:${C_RESET}       ${use_ssl}"
}

vhost_delete() {
    vhost_list
    local domain
    prompt_input "Domain to delete" "" domain
    [[ -z "$domain" ]] && return 1

    local conf="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    [[ ! -f "$conf" ]] && { log_error "Virtual host '${domain}' not found"; return 1; }

    confirm "Delete virtual host '${domain}'? Files will be preserved." || return 0

    rm -f "${NGINX_SITES_ENABLED}/${domain}.conf"
    rm -f "$conf"

    nginx_test_config && nginx_reload
    log_success "Virtual host '${domain}' deleted"
}

vhost_enable() {
    vhost_list
    local domain
    prompt_input "Domain to enable" "" domain
    [[ -z "$domain" ]] && return 1

    local conf="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    [[ ! -f "$conf" ]] && { log_error "Virtual host '${domain}' not found"; return 1; }

    ln -sf "$conf" "${NGINX_SITES_ENABLED}/${domain}.conf"
    nginx_test_config && nginx_reload
    log_success "Virtual host '${domain}' enabled"
}

vhost_disable() {
    vhost_list
    local domain
    prompt_input "Domain to disable" "" domain
    [[ -z "$domain" ]] && return 1

    rm -f "${NGINX_SITES_ENABLED}/${domain}.conf"
    nginx_test_config && nginx_reload
    log_success "Virtual host '${domain}' disabled"
}

vhost_edit() {
    vhost_list
    local domain
    prompt_input "Domain to edit" "" domain
    [[ -z "$domain" ]] && return 1

    local conf="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    [[ ! -f "$conf" ]] && { log_error "Virtual host '${domain}' not found"; return 1; }

    nano "$conf"
    nginx_test_config && nginx_reload
}

vhost_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== Virtual Host Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} List virtual hosts"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Create virtual host"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Delete virtual host"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Enable virtual host"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Disable virtual host"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Edit virtual host config"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice
        case "$choice" in
            1) vhost_list ;;
            2) vhost_create ;;
            3) vhost_delete ;;
            4) vhost_enable ;;
            5) vhost_disable ;;
            6) vhost_edit ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
