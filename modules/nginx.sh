#!/usr/bin/env bash
#
# Pig-NMP - Nginx Module
#

source "${CONF_DIR}/versions.conf"

_nginx_get_bin() {
    if [[ -x "${NGINX_DIR}/sbin/nginx" ]]; then
        echo "${NGINX_DIR}/sbin/nginx"
    elif is_installed nginx; then
        which nginx 2>/dev/null
    fi
}

nginx_is_installed() {
    [[ -n "$(_nginx_get_bin)" ]]
}

nginx_get_version() {
    local nginx_bin
    nginx_bin=$(_nginx_get_bin)
    if [[ -n "$nginx_bin" ]]; then
        "$nginx_bin" -v 2>&1 | grep -oP '[\d.]+'
    fi
}

nginx_install_apt() {
    local branch="${1:-stable}"
    require_os

    log_info "Installing Nginx from official APT repository (${branch})..."

    local keyring="/usr/share/keyrings/nginx-archive-keyring.gpg"
    rm -f "$keyring"
    curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o "$keyring"
    chmod 644 "$keyring"

    local repo_line
    if [[ "$branch" == "mainline" ]]; then
        repo_line="deb [signed-by=${keyring}] https://nginx.org/packages/mainline/${OS_ID} ${OS_CODENAME} nginx"
    else
        repo_line="deb [signed-by=${keyring}] https://nginx.org/packages/${OS_ID} ${OS_CODENAME} nginx"
    fi

    echo "$repo_line" > /etc/apt/sources.list.d/nginx.list

    systemctl stop nginx 2>/dev/null || true
    apt-get update -qq 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx 2>&1 | grep -iv 'kill:'
    local apt_ret=${PIPESTATUS[0]}

    if [[ $apt_ret -eq 0 ]] && is_installed nginx; then
        log_success "Nginx installed via APT: $(nginx -v 2>&1)"
        # APT postinst auto-starts nginx with /etc/nginx/nginx.conf (listening on :80).
        # Stop it immediately so port 80 is free for the pig-nmp managed unit which
        # loads /etc/pig-nmp/nginx/nginx.conf. Otherwise systemctl start nginx later
        # fails with "address already in use" and trips the ERR trap.
        systemctl stop nginx 2>/dev/null || true
        systemctl disable nginx 2>/dev/null || true
    else
        log_error "Failed to install Nginx via APT"
        return 1
    fi
}

nginx_install_source() {
    local version="${1:-$NGINX_STABLE_VERSION}"
    local -a extra_modules=("${@:2}")

    require_os
    install_build_deps
    install_deps libpcre2-dev libssl-dev zlib1g-dev

    log_info "Installing Nginx ${version} from source..."

    local url="https://nginx.org/download/nginx-${version}.tar.gz"
    local src_dir="${TMP_DIR}/nginx-${version}"

    ensure_dirs "$TMP_DIR"
    download_and_extract "$url" "$src_dir" 1 || return 1

    cd "$src_dir" || return 1

    local -a configure_opts=(
        --prefix="${INSTALL_PREFIX}/nginx"
        --conf-path="${NGINX_ETC_DIR}/nginx.conf"
        --error-log-path="${LOG_DIR}/nginx/error.log"
        --http-log-path="${LOG_DIR}/nginx/access.log"
        --pid-path="${RUN_DIR}/nginx.pid"
        --lock-path=/var/lock/nginx.lock
        --user=www-data
        --group=www-data
        --with-http_ssl_module
        --with-http_v2_module
        --with-http_realip_module
        --with-http_gzip_static_module
        --with-http_stub_status_module
        --with-http_sub_module
        --with-http_flv_module
        --with-http_mp4_module
        --with-stream
        --with-stream_ssl_module
        --with-stream_realip_module
        --with-pcre-jit
        --with-file-aio
    )

    for mod in "${extra_modules[@]}"; do
        case "$mod" in
            http_image_filter)  configure_opts+=(--with-http_image_filter_module) ;;
            http_geoip)         configure_opts+=(--with-http_geoip_module) ;;
            http_xslt)          configure_opts+=(--with-http_xslt_module) ;;
            http_dav)           configure_opts+=(--with-http_dav_module) ;;
            mail)               configure_opts+=(--with-mail --with-mail_ssl_module) ;;
        esac
    done

    log_info "Configuring Nginx ${version}..."
    ./configure "${configure_opts[@]}" &>/dev/null || {
        log_error "Nginx configure failed"
        cd - || return 1
        return 1
    }

    log_info "Compiling Nginx (this may take a while)..."
    make -j"$(nproc)" &>/dev/null || {
        log_error "Nginx compile failed"
        cd - || return 1
        return 1
    }

    make install &>/dev/null || {
        log_error "Nginx install failed"
        cd - || return 1
        return 1
    }

    cd - || return 1
    rm -rf "$src_dir"

    log_success "Nginx ${version} compiled and installed"
}

nginx_setup_config() {
    ensure_dirs \
        "${NGINX_ETC_DIR}" \
        "${NGINX_SITES_AVAILABLE}" \
        "${NGINX_SITES_ENABLED}" \
        "${NGINX_ETC_DIR}/includes" \
        "${LOG_DIR}/nginx" \
        "${RUN_DIR}"

    local nginx_conf="${NGINX_ETC_DIR}/nginx.conf"
    if [[ ! -f "$nginx_conf" ]] || [[ $(wc -l < "$nginx_conf" 2>/dev/null) -lt 5 ]]; then
        render_template "${TEMPLATES_DIR}/nginx/nginx.conf.tpl" "$nginx_conf" \
            NGINX_USER=www-data \
            NGINX_WORKER_PROCESSES="${CPU_CORES}" \
            NGINX_ETC_DIR="${NGINX_ETC_DIR}" \
            NGINX_SITES_ENABLED="${NGINX_SITES_ENABLED}" \
            RUN_DIR="${RUN_DIR}" \
            LOG_DIR="${LOG_DIR}"
    fi

    if [[ ! -d "${NGINX_ETC_DIR}/conf.d" ]]; then
        mkdir -p "${NGINX_ETC_DIR}/conf.d"
    fi

    if [[ ! -f "${NGINX_ETC_DIR}/mime.types" ]]; then
        if [[ -f /etc/nginx/mime.types ]]; then
            cp -a /etc/nginx/mime.types "${NGINX_ETC_DIR}/mime.types"
        elif [[ -f "${NGINX_DIR}/conf/mime.types" ]]; then
            cp -a "${NGINX_DIR}/conf/mime.types" "${NGINX_ETC_DIR}/mime.types"
        fi
    fi

    if [[ ! -f "${NGINX_ETC_DIR}/fastcgi_params" ]]; then
        if [[ -f /etc/nginx/fastcgi_params ]]; then
            cp -a /etc/nginx/fastcgi_params "${NGINX_ETC_DIR}/fastcgi_params"
        fi
    fi

    if [[ ! -f "${NGINX_ETC_DIR}/fastcgi.conf" ]]; then
        if [[ -f /etc/nginx/fastcgi.conf ]]; then
            cp -a /etc/nginx/fastcgi.conf "${NGINX_ETC_DIR}/fastcgi.conf"
        fi
    fi

    nginx_setup_systemd
}

nginx_setup_systemd() {
    local service_file="/etc/systemd/system/nginx.service"
    if [[ ! -f "$service_file" ]]; then
        local nginx_bin
        nginx_bin=$(_nginx_get_bin)
        if [[ -z "$nginx_bin" ]]; then
            nginx_bin="${NGINX_DIR}/sbin/nginx"
        fi
        render_template "${TEMPLATES_DIR}/systemd/nginx.service.tpl" "$service_file" \
            NGINX_BIN="${nginx_bin}" \
            NGINX_ETC_DIR="${NGINX_ETC_DIR}" \
            NGINX_PID="${RUN_DIR}/nginx.pid"
        systemctl daemon-reload
        systemctl enable nginx &>/dev/null || true
    fi
}

nginx_install() {
    if nginx_is_installed; then
        log_warn "Nginx is already installed: $(nginx_get_version)"
        if ! confirm "Reinstall Nginx?"; then
            return 0
        fi
    fi

    echo -e "\n${HEADER_COLOR}Select Nginx installation method:${C_RESET}" >&2
    echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} APT - Official repository (stable)" >&2
    echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} APT - Official repository (mainline)" >&2
    echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Source compilation" >&2
    local method_choice
    read -rp "$(echo -e "${C_CYAN}Enter number [1-3]:${C_RESET} ")" method_choice

    local setup_default_site=false
    if confirm "Set up default site (catch-all for IP/unconfigured domains)?" "y"; then
        setup_default_site=true
    fi

    case "$method_choice" in
        1) nginx_install_apt stable ;;
        2) nginx_install_apt mainline ;;
        3)
            local version
            prompt_input "Nginx version" "$NGINX_STABLE_VERSION" version
            nginx_install_source "$version"
            ;;
        *)
            log_error "Invalid choice"
            return 1
            ;;
    esac

    rm -f /etc/systemd/system/nginx.service
    nginx_setup_config

    id www-data &>/dev/null || useradd -r -s /sbin/nologin www-data

    # Ensure no stale nginx process (e.g. APT-auto-started one) holds port 80
    systemctl stop nginx 2>/dev/null || true
    # Use `if` guard so a failed start does not trip the global ERR trap
    if ! systemctl start nginx 2>&1; then
        log_error "Nginx failed to start"
        local nginx_bin
        nginx_bin=$(_nginx_get_bin)
        [[ -n "$nginx_bin" ]] && "$nginx_bin" -t -c "${NGINX_ETC_DIR}/nginx.conf" 2>&1 | tail -10
        return 1
    fi
    if is_service_active nginx; then
        log_success "Nginx is running on port 80"
    else
        log_error "Nginx is not active after start"
        return 1
    fi

    if $setup_default_site; then
        nginx_default_site_enable
    fi
}

nginx_uninstall() {
    if ! nginx_is_installed; then
        log_warn "Nginx is not installed"
        return 0
    fi

    if ! confirm "Uninstall Nginx? This will remove all Nginx files and configurations."; then
        return 0
    fi

    systemctl stop nginx &>/dev/null
    systemctl disable nginx &>/dev/null

    if [[ -x "${INSTALL_PREFIX}/nginx/sbin/nginx" ]]; then
        rm -rf "${INSTALL_PREFIX}/nginx"
    fi

    if is_installed nginx && dpkg -l nginx &>/dev/null; then
        apt_remove nginx nginx-common nginx-full
    fi

    rm -f /etc/systemd/system/nginx.service
    rm -f /etc/apt/sources.list.d/nginx.list
    systemctl daemon-reload

    if confirm "Remove Nginx configuration files?"; then
        rm -rf "${NGINX_ETC_DIR}"
    fi

    if confirm "Remove default site directory (/home/www/default)?"; then
        rm -rf "/home/www/default"
    fi

    log_success "Nginx uninstalled"
}

nginx_default_site_enable() {
    local default_conf="${NGINX_ETC_DIR}/conf.d/default.conf"

    ensure_dirs "/home/www/default"

    if [[ ! -f "/home/www/default/index.html" ]]; then
        cat > "/home/www/default/index.html" << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>I Am Alive</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{height:100%}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;background:linear-gradient(135deg,#0f0f14 0%,#1a1a24 50%,#0f0f14 100%);display:flex;align-items:center;justify-content:center;color:#e8e8ee;line-height:1.6}
.card{text-align:center;padding:60px 48px;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.06);border-radius:20px;backdrop-filter:blur(12px);max-width:420px;width:90%}
.logo{margin:0 auto 24px;width:72px;height:72px}
.logo svg{width:100%;height:100%}
h1{font-size:28px;font-weight:600;letter-spacing:-.02em;margin-bottom:8px}
p{color:#92929e;font-size:15px}
.tag{display:inline-block;margin-top:24px;padding:4px 14px;border-radius:100px;background:rgba(212,161,71,.1);border:1px solid rgba(212,161,71,.2);font-size:12px;font-weight:500;color:#d4a147;letter-spacing:.04em;text-transform:uppercase}
.dot{width:6px;height:6px;border-radius:50%;background:#4caf7d;display:inline-block;margin-right:6px;vertical-align:middle;animation:pulse 2s ease-in-out infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
</style>
</head>
<body>
<div class="card">
<div class="logo">
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px" width="48px" height="48px" viewBox="0 0 48 48"><g >
<path fill="#D39B75" d="M42,31.1123c-0.55225,0-1-0.44727-1-1s0.44775-1,1-1c1.36865,0,3-0.52051,3-3
	c0-1.6377-1.01758-1.97363-1.22168-2.02539c-0.52832-0.13086-0.86475-0.66406-0.74316-1.19531
	c0.12109-0.53125,0.6333-0.87305,1.16895-0.75781C45.17139,22.33496,47,23.42578,47,26.1123C47,29.14941,45.0376,31.1123,42,31.1123
	z"/>
<path fill="#EEBC99" d="M30,17H18.64111c-2.35938-4.74902-6.84814-4.68164-8.97021-3.94434
	c-0.5166,0.17969-0.79248,0.74121-0.61963,1.26074l1.65576,4.96777C8.61182,20.71094,6.97559,22.70312,6.01221,25H2
	c-0.55225,0-1,0.44727-1,1v10c0,0.55273,0.44775,1,1,1h5.0874C8.52539,39.23633,10.5918,40.97852,13,41.98828V46
	c0,0.55273,0.44775,1,1,1h6c0.55225,0,1-0.44727,1-1v-3h6v3c0,0.55273,0.44775,1,1,1h6c0.55225,0,1-0.44727,1-1v-4.01172
	C39.81348,39.98047,43,35.25,43,30C43,22.83203,37.16846,17,30,17z"/>
<path fill="#444444" d="M14,28c-1.10303,0-2-0.89746-2-2s0.89697-2,2-2s2,0.89746,2,2S15.10303,28,14,28z M14,26.00098h0.01025H14z
	 M14,26.00098h0.01025H14z M14,26.00098h0.01025H14z M14,26.00098h0.01025H14z M14,26.00098h0.01025H14z M14,26h0.01025H14z M14,26
	h0.00977H14z M14,26h0.00977H14z"/>
</g></svg>
</div>
<h1>Hello World</h1>
<p>Powered by Pig-NMP</p>
<div class="tag"><span class="dot"></span>Server Ready</div>
</div>
</body>
</html>
HTML
    fi

    render_template "${TEMPLATES_DIR}/nginx/default.conf.tpl" "$default_conf" \
        LOG_DIR="${LOG_DIR}"

    log_success "Default site enabled (catch-all for IP/unconfigured domains)"
    nginx_reload
}

nginx_default_site_disable() {
    rm -f "${NGINX_ETC_DIR}/conf.d/default.conf"
    log_success "Default site disabled"
    nginx_reload
}

nginx_default_site_status() {
    [[ -f "${NGINX_ETC_DIR}/conf.d/default.conf" ]]
}

nginx_default_site_menu() {
    while true; do
        local status_text
        if nginx_default_site_status; then
            status_text="${C_GREEN}enabled${C_RESET}"
        else
            status_text="${C_RED}disabled${C_RESET}"
        fi

        echo -e "\n${HEADER_COLOR}=== Default Site Management ===${C_RESET}"
        echo -e "  Status: ${status_text}"
        echo -e "  Document root: ${C_CYAN}/home/www/default${C_RESET}"
        echo ""
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Enable Default Site"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Disable Default Site"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Show Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) nginx_default_site_enable ;;
            2) nginx_default_site_disable ;;
            3)
                if nginx_default_site_status; then
                    log_info "Default site is enabled"
                    echo -e "  Config: ${C_CYAN}${NGINX_ETC_DIR}/conf.d/default.conf${C_RESET}"
                    echo -e "  Root:   ${C_CYAN}/home/www/default${C_RESET}"
                else
                    log_info "Default site is disabled"
                fi
                ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}

nginx_test_config() {
    local nginx_bin
    nginx_bin=$(_nginx_get_bin)
    if [[ -n "$nginx_bin" ]]; then
        "$nginx_bin" -t -c "${NGINX_ETC_DIR}/nginx.conf" 2>&1
    fi
}

nginx_reload() {
    if nginx_test_config &>/dev/null; then
        systemctl reload nginx &>/dev/null
        log_success "Nginx reloaded"
    else
        log_error "Nginx configuration test failed, not reloading"
        nginx_test_config
        return 1
    fi
}

nginx_status() {
    echo -e "\n${HEADER_COLOR}=== Nginx Status ===${C_RESET}"
    print_status "Nginx" "$(nginx_is_installed && echo 'installed' || echo 'not_installed')"
    if nginx_is_installed; then
        print_status "Version" "$(nginx_get_version)"
        print_status "Service" "$(is_service_active nginx && echo 'running' || echo 'stopped')"
        print_status "Config" "$(nginx_test_config &>/dev/null && echo 'OK' || echo 'ERROR')"
        print_status "Port 80" "$(port_in_use 80 && echo 'in_use' || echo 'free')"
    fi
}

nginx_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== Nginx Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install Nginx"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall Nginx"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Start/Stop/Restart"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Reload Configuration"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Test Configuration"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}7)${C_RESET} Default Site (catch-all)"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) nginx_install ;;
            2) nginx_uninstall ;;
            3)
                local action
                action=$(prompt_select "Service action:" "Start" "Stop" "Restart")
                case "$action" in
                    Start)   systemctl start nginx ;;
                    Stop)    systemctl stop nginx ;;
                    Restart) systemctl restart nginx ;;
                esac
                ;;
            4) nginx_reload ;;
            5) nginx_test_config ;;
            6) nginx_status ;;
            7) nginx_default_site_menu ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
