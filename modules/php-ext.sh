#!/usr/bin/env bash
#
# Pig-NMP - PHP Extension Module
#

PHP_EXT_AVAILABLE=(
    "pdo:PDO database abstraction (usually built-in)"
    "pdo_mysql:PDO MySQL driver"
    "pdo_pgsql:PDO PostgreSQL driver"
    "pdo_sqlite:PDO SQLite driver"
    "mysqli:MySQL improved extension"
    "mbstring:Multi-byte string handling"
    "curl:cURL transfer library"
    "fileinfo:File type detection (usually built-in)"
    "xml:XML parsing"
    "xmlwriter:XML writing"
    "xmlreader:XML reading"
    "zip:ZIP archive support"
    "bcmath:Binary calculator"
    "gd:GD image processing"
    "intl:Internationalization"
    "soap:SOAP protocol"
    "opcache:OPcache (usually built-in)"
    "imagick:Image processing (requires ImageMagick)"
    "redis:Redis client"
    "xdebug:Debug/profiler"
)

php_ext_is_installed() {
    local ext="$1" ver="$2" php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    [[ -x "$php_bin" ]] && "$php_bin" -m 2>/dev/null | grep -qi "^${ext}$"
}

php_ext_list_available() {
    echo -e "\n${HEADER_COLOR}=== Available PHP Extensions ===${C_RESET}"
    local i=1
    for entry in "${PHP_EXT_AVAILABLE[@]}"; do
        local name="${entry%%:*}" desc="${entry#*:}"
        printf "  ${MENU_NUM_COLOR}%2d)${C_RESET} %-15s %s\n" "$i" "$name" "$desc"
        i=$((i + 1))
    done
}

php_ext_list_installed() {
    local ver="$1" php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    [[ ! -x "$php_bin" ]] && { log_error "PHP ${ver} is not installed"; return 1; }
    echo -e "\n${HEADER_COLOR}=== Installed Extensions for PHP ${ver} ===${C_RESET}"
    "$php_bin" -m 2>/dev/null | sort | while read -r ext; do
        echo -e "  ${C_GREEN}●${C_RESET} ${ext}"
    done
}

php_ext_install() {
    local ext="$1" ver="$2"
    [[ -z "$ver" ]] && { ver=$(php_select_version); [[ -z "$ver" ]] && return 1; }
    php_is_installed "$ver" || { log_error "PHP ${ver} is not installed"; return 1; }

    if [[ -z "$ext" ]]; then
        php_ext_list_available
        prompt_input "Extension name" "" ext
        [[ -z "$ext" ]] && return 1
    fi
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    if php_ext_is_installed "$ext" "$ver"; then
        log_info "Extension '${ext}' is already enabled for PHP ${ver}"
        systemctl restart "php${ver}-fpm" &>/dev/null
        return 0
    fi

    log_info "Installing PHP extension '${ext}' for PHP ${ver}..."
    local method=$(php_install_method "$ver")

    case "$ext" in
        imagick)
            install_deps libmagickwand-dev libmagickcore-dev imagemagick
            php_ext_install_pecl "imagick" "$ver"
            php_ext_enable "imagick" "$ver"
            ;;
        redis)
            php_ext_install_pecl "redis" "$ver"
            php_ext_enable "redis" "$ver"
            ;;
        xdebug)
            php_ext_install_pecl "xdebug" "$ver"
            php_ext_enable_zend "xdebug" "$ver"
            ;;
        gd)
            install_deps libgd-dev libjpeg-dev libpng-dev libwebp-dev libfreetype6-dev
            php_ext_install_from_source_gd "$ver"
            php_ext_enable "gd" "$ver"
            ;;
        intl)
            install_deps libicu-dev
            php_ext_install_from_source_intl "$ver"
            php_ext_enable "intl" "$ver"
            ;;
        pdo|mysqli|mbstring|curl|fileinfo|xml|xmlwriter|xmlreader|zip|bcmath|soap|pgsql|sqlite3|bz2|gmp|exif|gettext|sockets|pcntl|sodium|opcache)
            if php_ext_is_installed "$ext" "$ver"; then
                log_info "Extension '${ext}' is already enabled"
                systemctl restart "php${ver}-fpm" &>/dev/null
                return 0
            fi
            if [[ "$method" == "apt" ]]; then
                local pkg="php${ver}-${ext}"
                apt-cache show "$pkg" &>/dev/null && install_deps "$pkg"
            else
                log_info "Extension '${ext}' is usually built-in for source-compiled PHP"
            fi
            ;;
        pdo_mysql|pdo_pgsql|pdo_sqlite)
            local base_ext="${ext#pdo_}"
            if [[ "$method" == "apt" ]]; then
                local pkg="php${ver}-${base_ext}"
                apt-cache show "$pkg" &>/dev/null && install_deps "$pkg"
            fi
            ;;
        *)
            log_info "Trying to install '${ext}' via PECL..."
            php_ext_install_pecl "$ext" "$ver"
            php_ext_enable "$ext" "$ver"
            ;;
    esac

    if php_ext_is_installed "$ext" "$ver"; then
        log_success "Extension '${ext}' installed for PHP ${ver}"
        systemctl restart "php${ver}-fpm" &>/dev/null
    else
        log_error "Failed to install extension '${ext}' for PHP ${ver}"
    fi
}

php_ext_install_pecl() {
    local ext="$1" ver="$2"
    local php_prefix="${PHP_BASE_DIR}/php${ver}"
    local phpize="${php_prefix}/bin/phpize"
    local php_config="${php_prefix}/bin/php-config"

    [[ ! -x "$phpize" ]] && { log_error "phpize not found for PHP ${ver}"; return 1; }

    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return 1

    log_info "Downloading PECL extension: ${ext}"
    "${php_prefix}/bin/pecl" download "$ext" &>/dev/null || {
        log_error "Failed to download PECL extension: ${ext}"
        cd -; rm -rf "$tmp_dir"; return 1
    }

    local ext_dir=$(find . -maxdepth 1 -type d -iname "${ext}*" | head -1)
    [[ -z "$ext_dir" ]] && { log_error "Cannot find extracted extension directory"; cd -; rm -rf "$tmp_dir"; return 1; }

    cd "$ext_dir" || return 1
    log_info "Compiling ${ext} for PHP ${ver}..."
    "$phpize" &>/dev/null && \
    ./configure --with-php-config="$php_config" &>/dev/null && \
    make -j"$(nproc)" &>/dev/null && \
    make install &>/dev/null
    local ret=$?
    cd - || return 1
    rm -rf "$tmp_dir"

    [[ $ret -ne 0 ]] && log_error "Failed to compile PECL extension: ${ext}"
    return $ret
}

php_ext_install_from_source_gd() {
    local ver="$1"
    local php_prefix="${PHP_BASE_DIR}/php${ver}"
    local php_config="${php_prefix}/bin/php-config"
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return 1

    download_file "https://www.php.net/distributions/php-${ver}.tar.gz" "${tmp_dir}/php-${ver}.tar.gz" || {
        cd -; rm -rf "$tmp_dir"; return 1
    }
    tar -xzf "php-${ver}.tar.gz" 2>/dev/null
    cd "php-${ver}/ext/gd" || { cd -; rm -rf "$tmp_dir"; return 1; }

    "${php_prefix}/bin/phpize" &>/dev/null && \
    ./configure --with-php-config="$php_config" --with-freetype --with-jpeg --with-webp --with-xpm &>/dev/null && \
    make -j"$(nproc)" &>/dev/null && \
    make install &>/dev/null
    local ret=$?
    cd - || return 1
    rm -rf "$tmp_dir"
    return $ret
}

php_ext_install_from_source_intl() {
    local ver="$1"
    local php_prefix="${PHP_BASE_DIR}/php${ver}"
    local php_config="${php_prefix}/bin/php-config"
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return 1

    download_file "https://www.php.net/distributions/php-${ver}.tar.gz" "${tmp_dir}/php-${ver}.tar.gz" || {
        cd -; rm -rf "$tmp_dir"; return 1
    }
    tar -xzf "php-${ver}.tar.gz" 2>/dev/null
    cd "php-${ver}/ext/intl" || { cd -; rm -rf "$tmp_dir"; return 1; }

    "${php_prefix}/bin/phpize" &>/dev/null && \
    ./configure --with-php-config="$php_config" &>/dev/null && \
    make -j"$(nproc)" &>/dev/null && \
    make install &>/dev/null
    local ret=$?
    cd - || return 1
    rm -rf "$tmp_dir"
    return $ret
}

php_ext_enable() {
    local ext="$1" ver="$2"
    local php_etc="${PHP_ETC_DIR}/php${ver}"
    local mods_dir="${php_etc}/mods-available"
    ensure_dirs "$mods_dir"

    local conf_file="${mods_dir}/${ext}.ini"
    [[ ! -f "$conf_file" ]] && echo "extension=${ext}.so" > "$conf_file"

    local method=$(php_install_method "$ver" 2>/dev/null)
    if [[ "$method" == "apt" ]]; then
        local sapi
        for sapi in fpm cli; do
            local conf_d="/etc/php/${ver}/${sapi}/conf.d"
            ensure_dirs "$conf_d"
            [[ -e "${conf_d}/$(ls "${conf_d}" 2>/dev/null | grep -oP '\d+(?=-'"${ext}"')' | head -1)-${ext}.ini" ]] && continue
            ln -sf "$conf_file" "${conf_d}/20-${ext}.ini"
        done
    else
        local ini_file=$(php_get_ini_path "$ver")
        [[ -f "$ini_file" ]] && grep -q "extension=${ext}" "$ini_file" 2>/dev/null || echo "extension=${ext}.so" >> "$ini_file"
    fi
}

php_ext_enable_zend() {
    local ext="$1" ver="$2"
    local php_etc="${PHP_ETC_DIR}/php${ver}"
    local method=$(php_install_method "$ver" 2>/dev/null)

    if [[ "$method" == "apt" ]]; then
        local mods_dir="${php_etc}/mods-available"
        ensure_dirs "$mods_dir"
        echo "zend_extension=${ext}.so" > "${mods_dir}/${ext}.ini"
        local sapi
        for sapi in fpm cli; do
            local conf_d="/etc/php/${ver}/${sapi}/conf.d"
            ensure_dirs "$conf_d"
            ln -sf "${mods_dir}/${ext}.ini" "${conf_d}/00-${ext}.ini"
        done
    else
        local ini_file=$(php_get_ini_path "$ver")
        [[ -f "$ini_file" ]] && grep -q "zend_extension.*${ext}" "$ini_file" 2>/dev/null || \
            sed_inplace "$ini_file" "1i zend_extension=${ext}.so"
    fi
}

php_ext_disable() {
    local ext="$1" ver="$2"
    local php_etc="${PHP_ETC_DIR}/php${ver}"

    rm -f "${php_etc}/mods-available/${ext}.ini"

    local method=$(php_install_method "$ver" 2>/dev/null)
    if [[ "$method" == "apt" ]]; then
        local sapi
        for sapi in fpm cli; do
            rm -f "/etc/php/${ver}/${sapi}/conf.d/"*"-${ext}.ini"
        done
    fi

    local ini_file=$(php_get_ini_path "$ver")
    [[ -f "$ini_file" ]] && sed_inplace "$ini_file" "/extension=${ext}/d" "/zend_extension.*${ext}/d"

    log_success "Extension '${ext}' disabled for PHP ${ver}"
    systemctl restart "php${ver}-fpm" &>/dev/null
}

php_ext_diagnose() {
    local ver="${1:-}"
    [[ -z "$ver" ]] && { ver=$(php_select_version); [[ -z "$ver" ]] && return 1; }
    php_is_installed "$ver" || { log_error "PHP ${ver} is not installed"; return 1; }

    local php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    local method=$(php_install_method "$ver")

    echo -e "\n${HEADER_COLOR}=== PHP ${ver} Extension Diagnostics ===${C_RESET}"

    echo -e "\n  ${C_BOLD}PHP Binary:${C_RESET}"
    echo -e "    Path:     ${php_bin}"
    [[ -L "$php_bin" ]] && echo -e "    Target:   $(readlink -f "$php_bin")"
    echo -e "    Version:  $("$php_bin" -v 2>/dev/null | head -1)"
    echo -e "    Method:   ${method}"

    echo -e "\n  ${C_BOLD}FPM Service:${C_RESET}"
    is_service_active "php${ver}-fpm" && echo -e "    Status: ${C_GREEN}running${C_RESET}" || echo -e "    Status: ${C_RED}stopped${C_RESET}"

    echo -e "\n  ${C_BOLD}Checking required extensions:${C_RESET}"
    local -a required_exts=(pdo pdo_mysql mysqli mbstring curl fileinfo xml zip)
    for ext in "${required_exts[@]}"; do
        local cli_loaded="no" fpm_loaded="no"
        php_ext_is_installed "$ext" "$ver" && cli_loaded="${C_GREEN}yes${C_RESET}" || cli_loaded="${C_RED}no${C_RESET}"

        if [[ "$method" == "apt" ]]; then
            local fpm_conf_d="/etc/php/${ver}/fpm/conf.d"
            if [[ -d "$fpm_conf_d" ]] && ls "$fpm_conf_d"/*"${ext}"* &>/dev/null 2>&1; then
                fpm_loaded="${C_GREEN}yes${C_RESET}"
            else
                fpm_loaded="${C_RED}no${C_RESET}"
            fi
        else
            fpm_loaded="(source - same as CLI)"
        fi
        printf "    %-15s CLI: %-20b FPM: %b\n" "$ext" "$cli_loaded" "$fpm_loaded"
    done

    echo -e "\n  ${C_BOLD}Quick Fix:${C_RESET} Run ${C_CYAN}systemctl restart php${ver}-fpm${C_RESET} to reload extensions\n"
}

php_ext_batch_install() {
    local ver="${1:-}"
    [[ -z "$ver" ]] && { ver=$(php_select_version); [[ -z "$ver" ]] && return 1; }
    php_is_installed "$ver" || { log_error "PHP ${ver} is not installed"; return 1; }

    echo -e "\n${HEADER_COLOR}=== Batch Install Common Extensions for PHP ${ver} ===${C_RESET}"
    local -a common_exts=(imagick redis)
    for ext in "${common_exts[@]}"; do
        php_ext_is_installed "$ext" "$ver" && log_info "${ext}: already installed, skipping" || php_ext_install "$ext" "$ver"
    done
}

php_ext_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== PHP Extension Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install extension"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall/Disable extension"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} List installed extensions"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} List available extensions"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Batch install common extensions"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Diagnose extensions (check FPM loading)"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice
        case "$choice" in
            1)
                local ver=$(php_select_version)
                [[ -z "$ver" ]] && continue
                local ext
                php_ext_list_available
                prompt_input "Extension name" "" ext
                [[ -n "$ext" ]] && php_ext_install "$ext" "$ver"
                ;;
            2)
                local ver=$(php_select_version)
                [[ -z "$ver" ]] && continue
                php_ext_list_installed "$ver"
                local ext
                prompt_input "Extension to disable" "" ext
                [[ -n "$ext" ]] && php_ext_disable "$ext" "$ver"
                ;;
            3)
                local ver=$(php_select_version)
                [[ -n "$ver" ]] && php_ext_list_installed "$ver"
                ;;
            4) php_ext_list_available ;;
            5)
                local ver=$(php_select_version)
                [[ -n "$ver" ]] && php_ext_batch_install "$ver"
                ;;
            6)
                local ver=$(php_select_version)
                [[ -n "$ver" ]] && php_ext_diagnose "$ver"
                ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
