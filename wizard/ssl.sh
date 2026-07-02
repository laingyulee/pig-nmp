#!/usr/bin/env bash
#
# Pig-NMP - SSL Certificate Wizard
#

ACME_DIR="${INSTALL_PREFIX}/acme.sh"

ssl_is_acme_installed() { [[ -x "${ACME_DIR}/acme.sh" ]]; }

ssl_install_acme() {
    if ssl_is_acme_installed; then
        log_info "acme.sh is already installed"
        return 0
    fi

    log_info "Installing acme.sh..."
    curl -fsSL https://get.acme.sh | sh -s -- --install-dir "${ACME_DIR}" --accountemail admin@localhost 2>&1 | tail -5

    if ssl_is_acme_installed; then
        log_success "acme.sh installed"
    else
        log_error "Failed to install acme.sh"; return 1
    fi
}

ssl_issue_letsencrypt() {
    local domain="$1" email="${2:-}"
    [[ -z "$domain" ]] && prompt_input "Domain" "" domain
    [[ -z "$domain" ]] && return 1

    ssl_is_acme_installed || ssl_install_acme

    local webroot="${DOMAINS_DIR}/${domain}"
    [[ ! -d "$webroot" ]] && { log_error "Document root not found: ${webroot}"; return 1; }

    log_info "Issuing Let's Encrypt certificate for ${domain}..."

    local -a acme_opts=(--issue -d "$domain" --webroot "$webroot" --force)
    [[ -n "$email" ]] && acme_opts+=(--accountemail "$email")

    "${ACME_DIR}/acme.sh" "${acme_opts[@]}" 2>&1 | tail -10
    local ret=$?

    if [[ $ret -eq 0 ]]; then
        log_success "Certificate issued for ${domain}"
        ssl_install_certificate "$domain"
    else
        log_error "Failed to issue certificate for ${domain}"
        return 1
    fi
}

ssl_get_fpm_pass() {
    local vhost_file="$1"
    grep -oP 'fastcgi_pass\s+\K[^;]+' "$vhost_file" 2>/dev/null | head -1
}

ssl_install_certificate() {
    local domain="$1"
    [[ -z "$domain" ]] && prompt_input "Domain" "" domain

    local cert_dir="${SSL_DIR}/${domain}"
    ensure_dirs "$cert_dir"

    log_info "Installing certificate for ${domain}..."

    "${ACME_DIR}/acme.sh" --install-cert -d "$domain" \
        --key-file       "${cert_dir}/key.pem" \
        --fullchain-file "${cert_dir}/fullchain.pem" \
        --reloadcmd      "systemctl reload nginx" 2>&1 | tail -5

    local ret=$?
    if [[ $ret -eq 0 ]]; then
        log_success "Certificate installed for ${domain}"

        # Update vhost config
        local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
        if [[ -f "$vhost_file" ]]; then
            local fpm_pass=$(ssl_get_fpm_pass "$vhost_file")
            render_template "${TEMPLATES_DIR}/nginx/vhost-ssl.conf.tpl" "$vhost_file" \
                DOMAIN="$domain" DOC_ROOT="${DOMAINS_DIR}/${domain}" \
                SSL_DIR="${SSL_DIR}" LOG_DIR="${LOG_DIR}"
            [[ -n "$fpm_pass" ]] && vhost_patch_php_block "$vhost_file" "$fpm_pass" "yes"
            nginx_test_config && nginx_reload
        fi
    else
        log_error "Failed to install certificate for ${domain}"
        return 1
    fi
}

ssl_issue_self_signed() {
    local domain="$1"
    [[ -z "$domain" ]] && prompt_input "Domain" "" domain
    [[ -z "$domain" ]] && return 1

    local cert_dir="${SSL_DIR}/${domain}"
    ensure_dirs "$cert_dir"

    log_info "Generating self-signed certificate for ${domain}..."

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "${cert_dir}/key.pem" \
        -out "${cert_dir}/fullchain.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${domain}" 2>/dev/null

    if [[ -f "${cert_dir}/key.pem" ]]; then
        log_success "Self-signed certificate generated for ${domain}"
    else
        log_error "Failed to generate certificate"; return 1
    fi
}

ssl_apply_to_vhost() {
    local domain="$1"
    [[ -z "$domain" ]] && prompt_input "Domain" "" domain

    local cert_dir="${SSL_DIR}/${domain}"
    [[ ! -f "${cert_dir}/key.pem" ]] && { log_error "No certificate found for ${domain}"; return 1; }

    local vhost_file="${NGINX_SITES_AVAILABLE}/${domain}.conf"
    [[ ! -f "$vhost_file" ]] && { log_error "No vhost found for ${domain}"; return 1; }

    local fpm_pass=$(ssl_get_fpm_pass "$vhost_file")
    render_template "${TEMPLATES_DIR}/nginx/vhost-ssl.conf.tpl" "$vhost_file" \
        DOMAIN="$domain" DOC_ROOT="${DOMAINS_DIR}/${domain}" \
        SSL_DIR="${SSL_DIR}" LOG_DIR="${LOG_DIR}"
    [[ -n "$fpm_pass" ]] && vhost_patch_php_block "$vhost_file" "$fpm_pass" "yes"

    nginx_test_config && nginx_reload
    log_success "SSL applied to ${domain}"
}

ssl_renew() {
    local domain="$1"
    if [[ -n "$domain" ]]; then
        "${ACME_DIR}/acme.sh" --renew -d "$domain" --force 2>&1 | tail -5
    else
        "${ACME_DIR}/acme.sh" --renew-all --force 2>&1 | tail -10
    fi
}

ssl_show_info() {
    local domain="$1"
    [[ -z "$domain" ]] && prompt_input "Domain" "" domain

    local cert_file="${SSL_DIR}/${domain}/fullchain.pem"
    [[ ! -f "$cert_file" ]] && { log_error "No certificate found for ${domain}"; return 1; }

    echo -e "\n${HEADER_COLOR}=== SSL Certificate: ${domain} ===${C_RESET}"
    openssl x509 -in "$cert_file" -noout -subject -dates -issuer 2>/dev/null
}

ssl_list() {
    echo -e "\n${HEADER_COLOR}=== SSL Certificates ===${C_RESET}"
    local count=0
    local dir
    for dir in "${SSL_DIR}"/*/; do
        [[ -f "${dir}fullchain.pem" ]] || continue
        local domain=$(basename "$dir")
        local expiry
        expiry=$(openssl x509 -in "${dir}/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        printf "  %-30s Expires: %s\n" "$domain" "${expiry:-unknown}"
        ((count++))
    done
    [[ $count -eq 0 ]] && echo -e "  ${C_YELLOW}No certificates found${C_RESET}"
}

ssl_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== SSL Certificate Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install acme.sh"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Issue Let's Encrypt certificate"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Generate self-signed certificate"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Install certificate to vhost"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Apply SSL to existing vhost"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Renew certificates"
        echo -e "  ${MENU_NUM_COLOR}7)${C_RESET} Show certificate info"
        echo -e "  ${MENU_NUM_COLOR}8)${C_RESET} List certificates"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice
        case "$choice" in
            1) ssl_install_acme ;;
            2) ssl_issue_letsencrypt ;;
            3) ssl_issue_self_signed ;;
            4) ssl_install_certificate ;;
            5) ssl_apply_to_vhost ;;
            6) ssl_renew ;;
            7) ssl_show_info ;;
            8) ssl_list ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
