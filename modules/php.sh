#!/usr/bin/env bash
#
# Pig-NMP - PHP Module (Multi-version)
#

source "${CONF_DIR}/versions.conf"

php_is_installed() {
    local ver="${1:-}"
    if [[ -n "$ver" ]]; then
        [[ -x "${PHP_BASE_DIR}/php${ver}/sbin/php-fpm" ]]
    else
        local versions
        versions=$(get_php_versions_installed)
        [[ -n "$versions" ]]
    fi
}

php_install_method() {
    local ver="$1"
    local php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    if [[ ! -e "$php_bin" ]]; then
        echo "none"
    elif [[ -L "$php_bin" ]]; then
        echo "apt"
    else
        echo "source"
    fi
}

php_get_version() {
    local ver="${1:-}"
    local php_bin
    if [[ -n "$ver" ]]; then
        php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    else
        php_bin="$(which php 2>/dev/null)"
    fi
    if [[ -x "$php_bin" ]]; then
        "$php_bin" -r "echo PHP_VERSION;" 2>/dev/null
    fi
}

php_get_ini_path() {
    local ver="$1"
    # APT-installed PHP loads ini from /etc/php/<ver>/{fpm,cli}/php.ini, not the
    # pig-nmp symlink target. Source-installed PHP uses PHP_ETC_DIR/php<ver>/php.ini.
    local method
    method=$(php_install_method "$ver" 2>/dev/null)
    if [[ "$method" == "apt" ]]; then
        # Prefer fpm php.ini (used by php-fpm service); fall back to cli if missing
        if [[ -f "/etc/php/${ver}/fpm/php.ini" ]]; then
            echo "/etc/php/${ver}/fpm/php.ini"
        elif [[ -f "/etc/php/${ver}/cli/php.ini" ]]; then
            echo "/etc/php/${ver}/cli/php.ini"
        else
            echo "/etc/php/${ver}/fpm/php.ini"
        fi
    else
        echo "${PHP_ETC_DIR}/php${ver}/php.ini"
    fi
}

php_get_ext_dir() {
    local ver="$1"
    local php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    if [[ -x "$php_bin" ]]; then
        "$php_bin" -r "echo ini_get('extension_dir');" 2>/dev/null
    fi
}

php_get_fpm_conf() {
    local ver="$1"
    echo "${PHP_ETC_DIR}/php${ver}/php-fpm.conf"
}

php_get_fpm_pool_dir() {
    local ver="$1"
    echo "${PHP_ETC_DIR}/php${ver}/fpm/pool.d"
}

php_install() {
    local ver="${1:-}"

    if [[ -z "$ver" ]]; then
        echo -e "\n${HEADER_COLOR}Select PHP version to install:${C_RESET}" >&2
        local -a versions=($PHP_VERSIONS_SUPPORTED)
        local -a available=()
        for v in "${versions[@]}"; do
            if ! php_is_installed "$v"; then
                available+=("PHP ${v}")
            fi
        done
        if [[ ${#available[@]} -eq 0 ]]; then
            log_warn "All supported PHP versions are already installed"
            return 0
        fi
        available+=("Cancel")
        local sel
        sel=$(prompt_select "Choose version:" "${available[@]}")
        [[ "$sel" == "Cancel" ]] && return 0
        ver="${sel#PHP }"
    fi

    if php_is_installed "$ver"; then
        log_warn "PHP ${ver} is already installed"
        if ! confirm "Reinstall PHP ${ver}?"; then
            return 0
        fi
        php_uninstall "$ver"
    fi

    local method
    method=$(prompt_select "Select PHP ${ver} installation method:" "APT - SURY repository (fast, binary)" "Source compilation (customizable)")

    case "$method" in
        *APT*|*SURY*) php_install_apt "$ver" ;;
        *Source*|*compilation*) php_install_source "$ver" ;;
        *) log_error "Invalid choice"; return 1 ;;
    esac
}

php_install_apt() {
    local ver="$1"
    require_os

    log_info "Installing PHP ${ver} from SURY APT repository..."

    install_deps ca-certificates curl gnupg lsb-release apt-transport-https

    local keyring="/usr/share/keyrings/sury-php-archive-keyring.gpg"
    rm -f "$keyring"
    if ! curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o "$keyring" 2>/dev/null; then
        log_error "Failed to import SURY GPG key"
        return 1
    fi
    chmod 644 "$keyring"

    echo "deb [signed-by=${keyring}] https://packages.sury.org/php/ ${OS_CODENAME} main" \
        > /etc/apt/sources.list.d/sury-php.list

    log_info "Running apt-get update..."
    apt-get update -qq 2>&1 | tail -5 || {
        log_warn "apt-get update had warnings, continuing..."
    }

    local p="php${ver}"

    local -a all_pkgs=(
        "${p}"           "${p}-common"
        "${p}-cli"       "${p}-fpm"
        "${p}-mysql"     "${p}-curl"
        "${p}-mbstring"  "${p}-xml"
        "${p}-gd"        "${p}-intl"
        "${p}-zip"       "${p}-bcmath"
        "${p}-opcache"   "${p}-readline"
        "${p}-soap"      "${p}-bz2"
        "${p}-sqlite3"   "${p}-gmp"
        "${p}-exif"      "${p}-gettext"
        "${p}-sockets"   "${p}-pcntl"
        "${p}-sodium"
    )

    local -a extra_pkgs=(
        "${p}-mysqli"    "${p}-pdo"
        "${p}-pgsql"     "${p}-redis"
        "${p}-imagick"   "${p}-memcached"
        "${p}-xsl"       "${p}-ftp"
    )

    local -a pkgs=()
    local pkg
    for pkg in "${all_pkgs[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            pkgs+=("$pkg")
        else
            log_warn "Package ${pkg} not found in repository, skipping"
        fi
    done

    for pkg in "${extra_pkgs[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            pkgs+=("$pkg")
        fi
    done

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        log_error "No PHP ${ver} packages found in SURY repository"
        log_error "Check if the repository was added correctly: cat /etc/apt/sources.list.d/sury-php.list"
        log_error "Search available: apt-cache search php${ver}"
        return 1
    fi

    log_info "Installing ${#pkgs[@]} packages: ${pkgs[*]}"
    local apt_log="${LOG_DIR}/php-${ver}-apt-install.log"
    ensure_dirs "${LOG_DIR}"

    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}" 2>&1 | tee "$apt_log" | tail -20

    if ! is_installed "${p}"; then
        log_error "Failed to install PHP ${ver} via APT"
        log_error "Full log: ${apt_log}"
        log_error "You can check available packages with: apt-cache search php${ver}"
        return 1
    fi

    local system_php_bin
    system_php_bin=$(which "${p}" 2>/dev/null || echo "/usr/bin/${p}")
    local system_fpm_bin
    system_fpm_bin=$(which "php-fpm${ver}" 2>/dev/null || echo "/usr/sbin/php-fpm${ver}")

    local php_prefix="${PHP_BASE_DIR}/php${ver}"
    ensure_dirs "${php_prefix}/bin" "${php_prefix}/sbin"

    ln -sf "$system_php_bin" "${php_prefix}/bin/php"
    ln -sf "$system_php_bin" "${php_prefix}/bin/${p}"
    ln -sf "/usr/bin/phpize${ver}" "${php_prefix}/bin/phpize" 2>/dev/null
    ln -sf "/usr/bin/php-config${ver}" "${php_prefix}/bin/php-config" 2>/dev/null
    ln -sf "/usr/bin/pear${ver}" "${php_prefix}/bin/pear" 2>/dev/null
    ln -sf "/usr/bin/pecl${ver}" "${php_prefix}/bin/pecl" 2>/dev/null
    ln -sf "$system_fpm_bin" "${php_prefix}/sbin/php-fpm"

    local real_etc="/etc/php/${ver}"
    local php_etc="${PHP_ETC_DIR}/php${ver}"
    ensure_dirs "${PHP_ETC_DIR}"

    if [[ -d "$real_etc" ]] && [[ ! -e "$php_etc" ]]; then
        ln -sf "$real_etc" "$php_etc"
    elif [[ ! -d "$php_etc" ]]; then
        ensure_dirs "$php_etc"
    fi

    php_setup_config_apt "$ver"

    id www-data &>/dev/null || useradd -r -s /sbin/nologin www-data

    systemctl enable "${p}-fpm" &>/dev/null
    systemctl start "${p}-fpm" &>/dev/null

    if is_service_active "${p}-fpm"; then
        log_success "PHP ${ver} installed via APT and php-fpm is running"
    else
        log_warn "PHP ${ver} installed but php-fpm failed to start"
    fi

    "${php_prefix}/bin/php" -v
}

php_setup_config_apt() {
    local ver="$1"
    local php_etc="${PHP_ETC_DIR}/php${ver}"

    ensure_dirs "${LOG_DIR}/php-fpm"

    local ini_file="${php_etc}/fpm/php.ini"
    if [[ -f "$ini_file" ]]; then
        local key
        for key in upload_max_filesize post_max_size memory_limit max_execution_time; do
            case "$key" in
                upload_max_filesize) sed_inplace "$ini_file" "s/^;*\s*upload_max_filesize\s*=.*/upload_max_filesize = 64M/" ;;
                post_max_size)       sed_inplace "$ini_file" "s/^;*\s*post_max_size\s*=.*/post_max_size = 64M/" ;;
                memory_limit)        sed_inplace "$ini_file" "s/^;*\s*memory_limit\s*=.*/memory_limit = 256M/" ;;
                max_execution_time)  sed_inplace "$ini_file" "s/^;*\s*max_execution_time\s*=.*/max_execution_time = 300/" ;;
            esac
        done
    fi

    local cli_ini="${php_etc}/cli/php.ini"
    if [[ -f "$cli_ini" ]]; then
        sed_inplace "$cli_ini" "s/^;*\s*date.timezone\s*=.*/date.timezone = UTC/"
    fi
}

php_install_source() {
    local ver="$1"
    require_os
    install_build_deps

    local php_prefix="${PHP_BASE_DIR}/php${ver}"
    local php_etc="${PHP_ETC_DIR}/php${ver}"
    local php_fpm_port
    php_fpm_port=$(get_php_fpm_port "$ver")
    local php_fpm_sock
    php_fpm_sock=$(get_php_fpm_sock "$ver")

    local src_dir="${TMP_DIR}/php-${ver}"

    log_info "Installing PHP ${ver} from source..."
    ensure_dirs "$TMP_DIR"

    local -a mirrors=(
        "https://www.php.net/distributions/php-${ver}.tar.gz"
        "https://mirrors.aliyun.com/php/php-${ver}.tar.gz"
        "https://mirrors.tuna.tsinghua.edu.cn/php/php-${ver}.tar.gz"
        "https://mirrors.ustc.edu.cn/php/php-${ver}.tar.gz"
    )

    local downloaded=false
    for url in "${mirrors[@]}"; do
        log_info "Trying: ${url}"
        if download_and_extract "$url" "$src_dir" 1; then
            downloaded=true
            break
        fi
        log_warn "Mirror failed, trying next..."
    done

    if [[ "$downloaded" != "true" ]]; then
        log_error "Failed to download PHP ${ver} from all mirrors"
        return 1
    fi

    cd "$src_dir" || return 1

    local -a configure_opts=(
        --prefix="${php_prefix}"
        --with-config-file-path="${php_etc}"
        --with-config-file-scan-dir="${php_etc}/mods-available"
        --enable-fpm
        --with-fpm-user=www-data
        --with-fpm-group=www-data
        --with-fpm-systemd
        --enable-bcmath
        --with-curl
        --with-openssl
        --with-openssl-dir=/usr
        --with-zlib
        --with-zlib-dir=/usr
        --enable-gd
        --with-webp
        --with-jpeg
        --with-xpm
        --with-freetype
        --enable-intl
        --with-icu-dir=/usr
        --enable-mbstring
        --with-onig=/usr
        --with-mysqli=mysqlnd
        --with-pdo-mysql=mysqlnd
        --enable-pcntl
        --enable-sockets
        --enable-soap
        --with-xsl
        --with-libxml
        --enable-simplexml
        --enable-xml
        --enable-dom
        --with-readline
        --enable-ftp
        --with-zip
        --with-bz2
        --with-gmp
        --enable-exif
        --with-gettext
        --enable-opcache
        --enable-fileinfo
        --with-sodium
        --with-password-argon2
        --with-pear
        --enable-phpdbg
        --with-ldap
        --with-ldap-sasl
    )

    log_info "Configuring PHP ${ver}..."
    ./configure "${configure_opts[@]}" 2>&1 | tee "${LOG_DIR}/php-${ver}-configure.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "PHP configure failed. Full log: ${LOG_DIR}/php-${ver}-configure.log"
        cd - || return 1
        return 1
    fi

    log_info "Compiling PHP ${ver} (this will take 10-20 minutes)..."
    make -j"$(nproc)" 2>&1 | tee "${LOG_DIR}/php-${ver}-make.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "PHP compile failed. Full log: ${LOG_DIR}/php-${ver}-make.log"
        cd - || return 1
        return 1
    fi

    make install 2>&1 | tee "${LOG_DIR}/php-${ver}-install.log"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "PHP install failed. Full log: ${LOG_DIR}/php-${ver}-install.log"
        cd - || return 1
        return 1
    fi

    cd - || return 1

    log_info "Setting up PHP ${ver} configuration..."
    php_setup_config "$ver" "$src_dir"

    rm -rf "$src_dir"

    log_info "Installing PECL and common extensions..."
    php_setup_pecl "$ver"

    php_setup_systemd "$ver"

    id www-data &>/dev/null || useradd -r -s /sbin/nologin www-data

    systemctl start "php${ver}-fpm" &>/dev/null
    if is_service_active "php${ver}-fpm"; then
        log_success "PHP ${ver} installed and php-fpm is running on port ${php_fpm_port}"
    else
        log_warn "PHP ${ver} installed but php-fpm failed to start"
    fi

    "${php_prefix}/bin/php" -v
}

php_setup_config() {
    local ver="$1"
    local src_dir="${2:-${TMP_DIR}/php-${ver}}"
    local php_prefix="${PHP_BASE_DIR}/php${ver}"
    local php_etc="${PHP_ETC_DIR}/php${ver}"
    local php_fpm_port
    php_fpm_port=$(get_php_fpm_port "$ver")
    local php_fpm_sock
    php_fpm_sock=$(get_php_fpm_sock "$ver")

    ensure_dirs \
        "${php_etc}" \
        "${php_etc}/mods-available" \
        "${php_etc}/fpm/pool.d" \
        "${RUN_DIR}/php-fpm" \
        "${LOG_DIR}/php${ver}" \
        "${LOG_DIR}/php-fpm"

    local ini_src="${src_dir}/php.ini-production"
    local ini_dest="${php_etc}/php.ini"
    if [[ ! -f "$ini_dest" ]]; then
        if [[ -f "$ini_src" ]]; then
            cp "$ini_src" "$ini_dest"
        else
            render_template "${TEMPLATES_DIR}/php/php.ini.tpl" "$ini_dest" \
                PHP_VERSION="$ver" \
                PHP_EXT_DIR="$(php_get_ext_dir "$ver" 2>/dev/null || echo "${php_prefix}/lib/php/extensions/no-debug-non-zts-*")" \
                PHP_ETC_DIR="${php_etc}" \
                UPLOAD_MAX_SIZE="64M" \
                MEMORY_LIMIT="256M" \
                MAX_EXECUTION_TIME="300" \
                TIMEZONE="UTC"
        fi
    fi

    local fpm_conf="${php_etc}/php-fpm.conf"
    if [[ ! -f "$fpm_conf" ]]; then
        render_template "${TEMPLATES_DIR}/php/php-fpm.conf.tpl" "$fpm_conf" \
            PHP_VER="$ver" \
            PHP_ETC_DIR="${php_etc}" \
            PHP_FPM_PID="${RUN_DIR}/php-fpm/php${ver}-fpm.pid" \
            PHP_FPM_ERROR_LOG="${LOG_DIR}/php-fpm/php${ver}-fpm-error.log" \
            LOG_DIR="${LOG_DIR}"
    fi

    local pool_conf="${php_etc}/fpm/pool.d/www.conf"
    if [[ ! -f "$pool_conf" ]]; then
        render_template "${TEMPLATES_DIR}/php/www.conf.tpl" "$pool_conf" \
            POOL_NAME="www${ver}" \
            PHP_FPM_USER="www-data" \
            PHP_FPM_GROUP="www-data" \
            PHP_FPM_LISTEN="${php_fpm_sock}" \
            PHP_FPM_PORT="${php_fpm_port}" \
            PHP_FPM_PM="dynamic" \
            PHP_FPM_PM_MAX_CHILDREN="50" \
            PHP_FPM_PM_START_SERVERS="5" \
            PHP_FPM_PM_MIN_SPARE="3" \
            PHP_FPM_PM_MAX_SPARE="10" \
            PHP_FPM_PM_MAX_REQUESTS="1000" \
            LOG_DIR="${LOG_DIR}"
    fi
}

php_setup_pecl() {
    local ver="$1"
    local php_prefix="${PHP_BASE_DIR}/php${ver}"

    if [[ -x "${php_prefix}/bin/pecl" ]]; then
        echo "autodetect" | "${php_prefix}/bin/pecl" channel-update pecl.php.net &>/dev/null
    fi
}

php_setup_systemd() {
    local ver="$1"
    local php_prefix="${PHP_BASE_DIR}/php${ver}"
    local php_etc="${PHP_ETC_DIR}/php${ver}"
    local service_file="/etc/systemd/system/php${ver}-fpm.service"

    if [[ ! -f "$service_file" ]]; then
        render_template "${TEMPLATES_DIR}/systemd/php-fpm@.service.tpl" "$service_file" \
            PHP_VER="$ver" \
            PHP_PREFIX="${php_prefix}" \
            PHP_ETC_DIR="${php_etc}" \
            PHP_FPM_PID="${RUN_DIR}/php-fpm/php${ver}-fpm.pid" \
            RUN_DIR="${RUN_DIR}"
        systemctl daemon-reload
        systemctl enable "php${ver}-fpm" &>/dev/null
    fi
}

php_uninstall() {
    local ver="${1:-}"

    if [[ -z "$ver" ]]; then
        local versions
        versions=$(get_php_versions_installed)
        if [[ -z "$versions" ]]; then
            log_warn "No PHP versions installed"
            return 0
        fi
        local -a opts=()
        while IFS= read -r v; do
            local method
            method=$(php_install_method "$v")
            opts+=("PHP ${v} (${method})")
        done <<< "$versions"
        opts+=("Cancel")
        local sel
        sel=$(prompt_select "Select PHP version to uninstall:" "${opts[@]}")
        [[ "$sel" == "Cancel" ]] && return 0
        ver="${sel#PHP }"
        ver="${ver%% *}"
    fi

    if ! php_is_installed "$ver"; then
        log_warn "PHP ${ver} is not installed"
        return 0
    fi

    if ! confirm "Uninstall PHP ${ver}? This will remove all files and extensions."; then
        return 0
    fi

    local method
    method=$(php_install_method "$ver")

    systemctl stop "php${ver}-fpm" &>/dev/null
    systemctl disable "php${ver}-fpm" &>/dev/null

    if [[ "$method" == "apt" ]]; then
        log_info "Removing APT installed PHP ${ver} packages..."
        local -a apt_pkgs=()
        while read -r pkg; do
            apt_pkgs+=("$pkg")
        done < <(dpkg -l "php${ver}*" 2>/dev/null | grep '^ii' | awk '{print $2}')
        if [[ ${#apt_pkgs[@]} -gt 0 ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "${apt_pkgs[@]}" 2>/dev/null
            apt-get autoremove -y -qq 2>/dev/null
        fi
        rm -f /etc/apt/sources.list.d/sury-php.list
    fi

    rm -rf "${PHP_BASE_DIR}/php${ver}"

    if [[ -L "${PHP_ETC_DIR}/php${ver}" ]]; then
        rm -f "${PHP_ETC_DIR}/php${ver}"
    else
        rm -rf "${PHP_ETC_DIR}/php${ver}"
    fi

    rm -f "/etc/systemd/system/php${ver}-fpm.service"
    systemctl daemon-reload

    log_success "PHP ${ver} uninstalled"
}

php_list_versions() {
    echo -e "\n${HEADER_COLOR}=== Installed PHP Versions ===${C_RESET}"
    local versions
    versions=$(get_php_versions_installed)
    if [[ -z "$versions" ]]; then
        echo -e "  ${C_YELLOW}No PHP versions installed${C_RESET}"
        return
    fi
    while IFS= read -r ver; do
        local php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
        local full_ver=""
        if [[ -x "$php_bin" ]]; then
            full_ver=$("$php_bin" -r "echo PHP_VERSION;" 2>/dev/null)
        fi
        local method
        method=$(php_install_method "$ver")
        local fpm_status="stopped"
        is_service_active "php${ver}-fpm" && fpm_status="running"
        printf "  %-10s %-12s %-8s php-fpm: %s\n" "PHP ${ver}" "(${full_ver})" "[${method}]" "$fpm_status"
    done <<< "$versions"
}

php_set_default() {
    local ver="${1:-}"
    if [[ -z "$ver" ]]; then
        php_list_versions
        prompt_input "Enter PHP version to set as default" "" ver
    fi
    if ! php_is_installed "$ver"; then
        log_error "PHP ${ver} is not installed"
        return 1
    fi
    local php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    ln -sf "$php_bin" /usr/local/bin/php
    ln -sf "${PHP_BASE_DIR}/php${ver}/bin/phpize" /usr/local/bin/phpize
    ln -sf "${PHP_BASE_DIR}/php${ver}/bin/php-config" /usr/local/bin/php-config
    ln -sf "${PHP_BASE_DIR}/php${ver}/bin/pear" /usr/local/bin/pear
    ln -sf "${PHP_BASE_DIR}/php${ver}/bin/pecl" /usr/local/bin/pecl
    log_success "PHP ${ver} set as default"
    php -v
}

php_tune_fpm() {
    local ver="$1"
    local pool_conf="${PHP_ETC_DIR}/php${ver}/fpm/pool.d/www.conf"
    if [[ ! -f "$pool_conf" ]]; then
        log_error "PHP-FPM pool config not found for PHP ${ver}"
        return 1
    fi

    echo -e "\n${HEADER_COLOR}PHP-FPM Tuning for PHP ${ver}:${C_RESET}"
    local pm_type
    pm_type=$(prompt_select "Process manager type:" "dynamic (recommended)" "static" "ondemand")

    local max_children start_servers min_spare max_spare
    prompt_input "pm.max_children" "50" max_children
    prompt_input "pm.start_servers" "5" start_servers
    prompt_input "pm.min_spare_servers" "3" min_spare
    prompt_input "pm.max_spare_servers" "10" max_spare

    local pm_val="${pm_type%% *}"
    sed_inplace "$pool_conf" "s/^pm = .*/pm = ${pm_val}/"
    sed_inplace "$pool_conf" "s/^pm.max_children = .*/pm.max_children = ${max_children}/"
    sed_inplace "$pool_conf" "s/^pm.start_servers = .*/pm.start_servers = ${start_servers}/"
    sed_inplace "$pool_conf" "s/^pm.min_spare_servers = .*/pm.min_spare_servers = ${min_spare}/"
    sed_inplace "$pool_conf" "s/^pm.max_spare_servers = .*/pm.max_spare_servers = ${max_spare}/"

    systemctl restart "php${ver}-fpm" &>/dev/null
    log_success "PHP-FPM tuned for PHP ${ver}"
}

php_status() {
    echo -e "\n${HEADER_COLOR}=== PHP Status ===${C_RESET}"
    local versions
    versions=$(get_php_versions_installed)
    if [[ -z "$versions" ]]; then
        print_status "PHP" "not_installed"
        return
    fi
    while IFS= read -r ver; do
        local full_ver
        full_ver=$(php_get_version "$ver")
        local method
        method=$(php_install_method "$ver")
        local fpm_status="stopped"
        is_service_active "php${ver}-fpm" && fpm_status="running"
        local fpm_port
        fpm_port=$(get_php_fpm_port "$ver")
        printf "  PHP %-6s %-12s %-8s FPM: %-10s Port: %s\n" "$ver" "(${full_ver})" "[${method}]" "$fpm_status" "$fpm_port"
    done <<< "$versions"
}

php_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== PHP Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install PHP version"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall PHP version"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} List installed versions"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Set default PHP version"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Start/Stop/Restart php-fpm"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Tune php-fpm settings"
        echo -e "  ${MENU_NUM_COLOR}7)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) php_install ;;
            2) php_uninstall ;;
            3) php_list_versions ;;
            4) php_set_default ;;
            5)
                local ver
                ver=$(php_select_version)
                [[ -z "$ver" ]] && continue
                local action
                action=$(prompt_select "PHP ${ver} FPM action:" "Start" "Stop" "Restart" "Reload")
                case "$action" in
                    Start)   systemctl start "php${ver}-fpm" ;;
                    Stop)    systemctl stop "php${ver}-fpm" ;;
                    Restart) systemctl restart "php${ver}-fpm" ;;
                    Reload)  systemctl reload "php${ver}-fpm" ;;
                esac
                ;;
            6)
                local ver
                ver=$(php_select_version)
                [[ -n "$ver" ]] && php_tune_fpm "$ver"
                ;;
            7) php_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}

php_select_version() {
    local versions
    versions=$(get_php_versions_installed)
    if [[ -z "$versions" ]]; then
        log_warn "No PHP versions installed"
        return 1
    fi
    local -a opts=()
    while IFS= read -r v; do
        opts+=("PHP ${v}")
    done <<< "$versions"
    local sel
    sel=$(prompt_select "Select PHP version:" "${opts[@]}")
    echo "${sel#PHP }"
}
