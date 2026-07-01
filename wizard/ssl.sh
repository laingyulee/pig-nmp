#!/usr/bin/env bash
#
# Pig-NMP - SSL Certificate Configuration Wizard
#

ssl_is_acme_installed() {
    [[ -x "${ACME_DIR}/acme.sh" ]] || [[ -x "$HOME/.acme.sh/acme.sh" ]]
}

ssl_install_acme() {
    if ssl_is_acme_installed; then
        log_info "acme.sh is already installed"
        return 0
    fi

    log_info "Installing acme.sh..."
    curl -fsSL https://get.acme.sh | sh -s email=admin@$(hostname) 2>/dev/null || {
        log_error "Failed to install acme.sh"
        return 1
    }

    if [[ -x "$HOME/.acme.sh/acme.sh" ]]; then
        ACME_SH="$HOME/.acme.sh/acme.sh"
    else
        ACME_SH=$(which acme.sh 2>/dev/null)
    fi

    log_success "acme.sh installed"
}

ssl_issue_letsencrypt() {
    if ! nginx_is_installed; then
        log_error "Nginx must be installed first"
        return 1
    fi

    ssl_install_acme

    echo -e "\n${HEADER_COLOR}=== Let's Encrypt Certificate ===${C_RESET}"

    local domain
    prompt_input "Domain name" "" domain
    [[ -z "$domain" ]] && return 1

    local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    if [[ ! -f "$vhost_file" ]]; then
        log_warn "No virtual host found for ${domain}. Creating a basic one..."
        local docroot="${DOMAINS_DIR}/${domain}"
        ensure_domains_dir
        ensure_dirs "$docroot"
        render_template "${TEMPLATES_DIR}/nginx/vhost-http.conf.tpl" "$vhost_file" \
            DOMAIN="$domain" \
            DOCUMENT_ROOT="$docroot" \
            PHP_FPM_SOCK="" \
            PHP_VER="" \
            LOG_DIR="${LOG_DIR}" \
            NGINX_ETC_DIR="${NGINX_ETC_DIR}"
        vhost_patch_php_block "$vhost_file" ""
        ln -sf "$vhost_file" "${NGINX_SITES_ENABLED}/${domain}.conf"
        nginx_reload
    fi

    echo -e "\n${HEADER_COLOR}Verification method:${C_RESET}"
    local method
    method=$(prompt_select "Select verification method:" "HTTP (webroot)" "DNS (manual)" "DNS (Cloudflare API)")

    local acme_cmd="${ACME_SH:-$HOME/.acme.sh/acme.sh}"
    local -a acme_opts=("--issue")

    case "$method" in
        HTTP*)
            local docroot
            docroot=$(grep -oP 'root\s+\K[^;]+' "$vhost_file" 2>/dev/null | head -1)
            if [[ -z "$docroot" ]]; then
                docroot="${DOMAINS_DIR}/${domain}"
                ensure_dirs "$docroot"
            fi
            acme_opts+=("--webroot" "$docroot")
            ;;
        "DNS (manual)")
            acme_opts+=("--dns" "--yes-I-know-dns-manual-mode-enough-go-ahead-please")
            ;;
        "DNS (Cloudflare API)")
            local cf_email cf_key
            prompt_input "Cloudflare email" "" cf_email
            prompt_input "Cloudflare API key" "" cf_key
            CF_Email="$cf_email" CF_Key="$cf_key" "$acme_cmd" "${acme_opts[@]}" --dns cf -d "$domain" 2>&1
            local acme_ret=$?
            unset CF_Email CF_Key 2>/dev/null
            if [[ $acme_ret -ne 0 ]]; then
                log_error "Certificate issuance failed"
                return 1
            fi
            ssl_install_certificate "$domain"
            log_success "Let's Encrypt certificate issued for ${domain}"
            return 0
            ;;
    esac

    acme_opts+=("-d" "$domain")

    log_info "Issuing certificate for ${domain}..."
    "$acme_cmd" "${acme_opts[@]}" 2>&1

    if [[ $? -ne 0 ]]; then
        log_error "Certificate issuance failed"
        return 1
    fi

    ssl_install_certificate "$domain"

    log_success "Let's Encrypt certificate issued for ${domain}"
}

ssl_get_fpm_pass() {
    local vhost_file="$1"
    local fpm_pass
    fpm_pass=$(grep -oP 'fastcgi_pass\s+\K[^;]+' "$vhost_file" 2>/dev/null | head -1)
    if [[ -n "$fpm_pass" ]]; then
        fpm_pass="${fpm_pass#"${fpm_pass%%[![:space:]]*}"}"
        fpm_pass="${fpm_pass%"${fpm_pass##*[![:space:]]}"}"
    fi
    echo "$fpm_pass"
}

ssl_install_certificate() {
    local domain="$1"
    local acme_cmd="${ACME_SH:-$HOME/.acme.sh/acme.sh}"
    local cert_dir="${SSL_DIR}/${domain}"
    ensure_dirs "$cert_dir"

    "$acme_cmd" --install-cert -d "$domain" \
        --key-file "${cert_dir}/privkey.pem" \
        --fullchain-file "${cert_dir}/fullchain.pem" \
        --cert-file "${cert_dir}/cert.pem" \
        --ca-file "${cert_dir}/chain.pem" \
        --reloadcmd "systemctl reload nginx" 2>&1

    local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    if [[ -f "$vhost_file" ]]; then
        if grep -q "listen.*443" "$vhost_file" 2>/dev/null; then
            sed_inplace "$vhost_file" "s|ssl_certificate .*|ssl_certificate ${cert_dir}/fullchain.pem;|"
            sed_inplace "$vhost_file" "s|ssl_certificate_key .*|ssl_certificate_key ${cert_dir}/privkey.pem;|"
        else
            local docroot
            docroot=$(grep -oP 'root\s+\K[^;]+' "$vhost_file" 2>/dev/null | head -1)
            local fpm_sock
            fpm_sock=$(ssl_get_fpm_pass "$vhost_file")
            local php_ver
            php_ver=$(grep -oP 'php(\d\.\d)' "$vhost_file" 2>/dev/null | head -1 | grep -oP '[\d.]+')

            backup_file "$vhost_file"
            render_template "${TEMPLATES_DIR}/nginx/vhost-ssl.conf.tpl" "$vhost_file" \
                DOMAIN="$domain" \
                DOCUMENT_ROOT="$docroot" \
                PHP_FPM_SOCK="$fpm_sock" \
                PHP_VER="$php_ver" \
                SSL_CERT="${cert_dir}/fullchain.pem" \
                SSL_KEY="${cert_dir}/privkey.pem" \
                LOG_DIR="${LOG_DIR}" \
                NGINX_ETC_DIR="${NGINX_ETC_DIR}"
            vhost_patch_php_block "$vhost_file" "$fpm_sock" "yes"
        fi
    fi

    nginx_reload
}

ssl_issue_self_signed() {
    echo -e "\n${HEADER_COLOR}=== Self-Signed Certificate ===${C_RESET}"

    local domain
    prompt_input "Domain name (or IP)" "" domain
    [[ -z "$domain" ]] && return 1

    local cert_dir="${SSL_DIR}/${domain}"
    ensure_dirs "$cert_dir"

    log_info "Generating self-signed certificate for ${domain}..."

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${cert_dir}/privkey.pem" \
        -out "${cert_dir}/fullchain.pem" \
        -subj "/C=US/ST=State/L=City/O=Pig-NMP/CN=${domain}" 2>/dev/null

    chmod 600 "${cert_dir}/privkey.pem"
    chmod 644 "${cert_dir}/fullchain.pem"

    log_success "Self-signed certificate generated for ${domain}"
    echo -e "  ${C_GREEN}Cert:${C_RESET} ${cert_dir}/fullchain.pem"
    echo -e "  ${C_GREEN}Key:${C_RESET}  ${cert_dir}/privkey.pem"

    if nginx_is_installed; then
        local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
        if [[ -f "$vhost_file" ]]; then
            if confirm "Apply SSL certificate to virtual host ${domain}?"; then
                ssl_apply_to_vhost "$domain" "${cert_dir}/fullchain.pem" "${cert_dir}/privkey.pem"
            fi
        fi
    fi
}

ssl_apply_to_vhost() {
    local domain="$1"
    local cert="$2"
    local key="$3"

    local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    if [[ ! -f "$vhost_file" ]]; then
        log_error "Virtual host ${domain} not found"
        return 1
    fi

    if grep -q "listen.*443" "$vhost_file" 2>/dev/null; then
        sed_inplace "$vhost_file" "s|ssl_certificate .*|ssl_certificate ${cert};|"
        sed_inplace "$vhost_file" "s|ssl_certificate_key .*|ssl_certificate_key ${key};|"
    else
        local docroot
        docroot=$(grep -oP 'root\s+\K[^;]+' "$vhost_file" 2>/dev/null | head -1)
        local fpm_sock
        fpm_sock=$(ssl_get_fpm_pass "$vhost_file")
        local php_ver
        php_ver=$(grep -oP 'php(\d\.\d)' "$vhost_file" 2>/dev/null | head -1 | grep -oP '[\d.]+')

        backup_file "$vhost_file"
        render_template "${TEMPLATES_DIR}/nginx/vhost-ssl.conf.tpl" "$vhost_file" \
            DOMAIN="$domain" \
            DOCUMENT_ROOT="$docroot" \
            PHP_FPM_SOCK="$fpm_sock" \
            PHP_VER="$php_ver" \
            SSL_CERT="$cert" \
            SSL_KEY="$key" \
            LOG_DIR="${LOG_DIR}" \
            NGINX_ETC_DIR="${NGINX_ETC_DIR}"
        vhost_patch_php_block "$vhost_file" "$fpm_sock" "yes"
    fi

    nginx_reload
    log_success "SSL applied to ${domain}"
}

ssl_renew() {
    local domain="$1"
    local acme_cmd="${ACME_SH:-$HOME/.acme.sh/acme.sh}"

    if [[ -n "$domain" ]]; then
        log_info "Renewing certificate for ${domain}..."
        "$acme_cmd" --renew -d "$domain" --force 2>&1
    else
        log_info "Renewing all certificates..."
        "$acme_cmd" --renew-all --force 2>&1
    fi

    if [[ $? -eq 0 ]]; then
        log_success "Certificate(s) renewed"
    else
        log_error "Certificate renewal failed"
    fi
}

ssl_show_info() {
    local domain="$1"
    if [[ -z "$domain" ]]; then
        prompt_input "Domain name" "" domain
    fi
    [[ -z "$domain" ]] && return 1

    local cert_file="${SSL_DIR}/${domain}/fullchain.pem"
    if [[ ! -f "$cert_file" ]]; then
        log_error "Certificate not found: ${cert_file}"
        return 1
    fi

    echo -e "\n${HEADER_COLOR}=== Certificate Info: ${domain} ===${C_RESET}"
    openssl x509 -in "$cert_file" -noout -subject -issuer -dates -subject 2>/dev/null | while read line; do
        echo "  $line"
    done
}

ssl_list() {
    echo -e "\n${HEADER_COLOR}=== SSL Certificates ===${C_RESET}"
    if [[ ! -d "$SSL_DIR" ]] || [[ -z "$(ls -A "$SSL_DIR" 2>/dev/null)" ]]; then
        echo -e "  ${C_YELLOW}No certificates found${C_RESET}"
        return
    fi

    for cert_dir in "${SSL_DIR}"/*/; do
        [[ -d "$cert_dir" ]] || continue
        local domain
        domain=$(basename "$cert_dir")
        local cert_file="${cert_dir}/fullchain.pem"
        if [[ -f "$cert_file" ]]; then
            local expiry
            expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
            local issuer
            issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | cut -d= -f2-)
            printf "  %-30s Expires: %-25s Issuer: %s\n" "$domain" "$expiry" "$issuer"
        fi
    done
}

ssl_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== SSL Certificate Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Issue Let's Encrypt certificate"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Generate self-signed certificate"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Renew certificate"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Apply certificate to virtual host"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} List certificates"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Show certificate info"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) ssl_issue_letsencrypt ;;
            2) ssl_issue_self_signed ;;
            3)
                local domain
                prompt_input "Domain (leave empty for all)" "" domain
                ssl_renew "$domain"
                ;;
            4)
                local domain cert key
                prompt_input "Domain" "" domain
                prompt_input "Certificate path" "${SSL_DIR}/${domain}/fullchain.pem" cert
                prompt_input "Key path" "${SSL_DIR}/${domain}/privkey.pem" key
                ssl_apply_to_vhost "$domain" "$cert" "$key"
                ;;
            5) ssl_list ;;
            6) ssl_show_info ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
