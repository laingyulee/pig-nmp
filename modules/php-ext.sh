#!/usr/bin/env bash
#
# Pig-NMP - PHP Extension Module
#

PHP_EXT_AVAILABLE=(
    "imagick:Image processing (requires ImageMagick)"
    "redis:Redis client"
    "memcached:Memcached client (requires libmemcached-dev)"
    "gd:GD image processing"
    "intl:Internationalization"
    "mongodb:MongoDB client"
    "swoole:Async/coroutine framework"
    "mcrypt:MCrypt encryption (deprecated, use OpenSSL)"
    "yaml:YAML parser"
    "xdebug:Debug/profiler"
    "grpc:gRPC framework"
    "protobuf:Protocol Buffers"
    "opcache:OPcache (usually built-in)"
    "excimer:Profiling timer"
    "rdkafka:Kafka client"
    "amqp:AMQP protocol"
    "ssh2:SSH2"
    "pcov:Code coverage"
    "luasandbox:Lua sandbox"
)

php_ext_is_installed() {
    local ext="$1"
    local ver="$2"
    local php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    if [[ -x "$php_bin" ]]; then
        "$php_bin" -m 2>/dev/null | grep -qi "^${ext}$"
    fi
}

php_ext_list_available() {
    echo -e "\n${HEADER_COLOR}=== Available PHP Extensions ===${C_RESET}"
    local i=1
    for entry in "${PHP_EXT_AVAILABLE[@]}"; do
        local name="${entry%%:*}"
        local desc="${entry#*:}"
        printf "  ${MENU_NUM_COLOR}%2d)${C_RESET} %-15s %s\n" "$i" "$name" "$desc"
        i=$((i + 1))
    done
}

php_ext_list_installed() {
    local ver="$1"
    local php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    if [[ ! -x "$php_bin" ]]; then
        log_error "PHP ${ver} is not installed"
        return 1
    fi

    echo -e "\n${HEADER_COLOR}=== Installed Extensions for PHP ${ver} ===${C_RESET}"
    "$php_bin" -m 2>/dev/null | sort | while read -r ext; do
        echo -e "  ${C_GREEN}●${C_RESET} ${ext}"
    done
}

php_ext_install() {
    local ext="$1"
    local ver="$2"

    if [[ -z "$ver" ]]; then
        ver=$(php_select_version)
        [[ -z "$ver" ]] && return 1
    fi

    if ! php_is_installed "$ver"; then
        log_error "PHP ${ver} is not installed"
        return 1
    fi

    if [[ -z "$ext" ]]; then
        php_ext_list_available
        prompt_input "Extension name" "" ext
        [[ -z "$ext" ]] && return 1
    fi

    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    if php_ext_is_installed "$ext" "$ver"; then
        log_warn "Extension '${ext}' is already installed for PHP ${ver}"
        if ! confirm "Reinstall?"; then
            return 0
        fi
    fi

    log_info "Installing PHP extension '${ext}' for PHP ${ver}..."

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
        memcached)
            install_deps libmemcached-dev zlib1g-dev
            php_ext_install_pecl "memcached" "$ver"
            php_ext_enable "memcached" "$ver"
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
        mongodb)
            install_deps libssl-dev
            php_ext_install_pecl "mongodb" "$ver"
            php_ext_enable "mongodb" "$ver"
            ;;
        swoole)
            install_deps libssl-dev
            php_ext_install_pecl "swoole" "$ver"
            php_ext_enable "swoole" "$ver"
            ;;
        mcrypt)
            install_deps libmcrypt-dev
            php_ext_install_pecl "mcrypt" "$ver"
            php_ext_enable "mcrypt" "$ver"
            ;;
        yaml)
            install_deps libyaml-dev
            php_ext_install_pecl "yaml" "$ver"
            php_ext_enable "yaml" "$ver"
            ;;
        xdebug)
            php_ext_install_pecl "xdebug" "$ver"
            php_ext_enable_zend "xdebug" "$ver"
            ;;
        grpc)
            php_ext_install_pecl "grpc" "$ver"
            php_ext_enable "grpc" "$ver"
            ;;
        protobuf)
            php_ext_install_pecl "protobuf" "$ver"
            php_ext_enable "protobuf" "$ver"
            ;;
        excimer)
            php_ext_install_pecl "excimer" "$ver"
            php_ext_enable "excimer" "$ver"
            ;;
        rdkafka)
            install_deps librdkafka-dev
            php_ext_install_pecl "rdkafka" "$ver"
            php_ext_enable "rdkafka" "$ver"
            ;;
        amqp)
            install_deps librabbitmq-dev
            php_ext_install_pecl "amqp" "$ver"
            php_ext_enable "amqp" "$ver"
            ;;
        ssh2)
            install_deps libssh2-1-dev
            php_ext_install_pecl "ssh2" "$ver"
            php_ext_enable "ssh2" "$ver"
            ;;
        pcov)
            php_ext_install_pecl "pcov" "$ver"
            php_ext_enable "pcov" "$ver"
            ;;
        luasandbox)
            php_ext_install_pecl "Luasandbox" "$ver"
            php_ext_enable "luasandbox" "$ver"
            ;;
        opcache)
            log_info "OPcache is usually built-in. Enabling..."
            php_ext_enable "opcache" "$ver"
            ;;
        fileinfo)
            log_info "fileinfo is usually built-in during PHP compilation"
            log_info "If not available, you may need to recompile PHP with --enable-fileinfo"
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
    local ext="$1"
    local ver="$2"
    local php_prefix="${PHP_BASE_DIR}/php${ver}"
    local phpize="${php_prefix}/bin/phpize"
    local php_config="${php_prefix}/bin/php-config"

    if [[ ! -x "$phpize" ]]; then
        log_error "phpize not found for PHP ${ver}"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return 1

    log_info "Downloading PECL extension: ${ext}"
    "${php_prefix}/bin/pecl" download "$ext" &>/dev/null || {
        log_error "Failed to download PECL extension: ${ext}"
        cd - || return 1
        rm -rf "$tmp_dir"
        return 1
    }

    local ext_dir
    ext_dir=$(find . -maxdepth 1 -type d -iname "${ext}*" | head -1)
    if [[ -z "$ext_dir" ]]; then
        log_error "Cannot find extracted extension directory"
        cd - || return 1
        rm -rf "$tmp_dir"
        return 1
    fi

    cd "$ext_dir" || return 1

    log_info "Compiling ${ext} for PHP ${ver}..."
    "$phpize" &>/dev/null && \
    ./configure --with-php-config="$php_config" &>/dev/null && \
    make -j"$(nproc)" &>/dev/null && \
    make install &>/dev/null

    local ret=$?
    cd - || return 1
    rm -rf "$tmp_dir"

    if [[ $ret -ne 0 ]]; then
        log_error "Failed to compile PECL extension: ${ext}"
    fi
    return $ret
}

php_ext_install_from_source_gd() {
    local ver="$1"
    local php_prefix="${PHP_BASE_DIR}/php${ver}"
    local php_config="${php_prefix}/bin/php-config"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return 1

    log_info "Downloading PHP ${ver} source for GD extension..."
    local url="https://www.php.net/distributions/php-${ver}.tar.gz"
    if ! download_file "$url" "${tmp_dir}/php-${ver}.tar.gz"; then
        cd - || return 1
        rm -rf "$tmp_dir"
        return 1
    fi

    tar -xzf "php-${ver}.tar.gz" 2>/dev/null
    cd "php-${ver}/ext/gd" || { cd - || return 1; rm -rf "$tmp_dir"; return 1; }

    "${php_prefix}/bin/phpize" &>/dev/null && \
    ./configure --with-php-config="$php_config" \
        --with-freetype \
        --with-jpeg \
        --with-webp \
        --with-xpm &>/dev/null && \
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
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return 1

    local url="https://www.php.net/distributions/php-${ver}.tar.gz"
    if ! download_file "$url" "${tmp_dir}/php-${ver}.tar.gz"; then
        cd - || return 1
        rm -rf "$tmp_dir"
        return 1
    fi

    tar -xzf "php-${ver}.tar.gz" 2>/dev/null
    cd "php-${ver}/ext/intl" || { cd - || return 1; rm -rf "$tmp_dir"; return 1; }

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
    local ext="$1"
    local ver="$2"
    local php_etc="${PHP_ETC_DIR}/php${ver}"
    local mods_dir="${php_etc}/mods-available"
    local ext_dir
    ext_dir=$(php_get_ext_dir "$ver")

    ensure_dirs "$mods_dir"

    local conf_file="${mods_dir}/${ext}.ini"
    if [[ ! -f "$conf_file" ]]; then
        cat > "$conf_file" << EOF
extension=${ext}.so
EOF
    fi

    local method
    method=$(php_install_method "$ver" 2>/dev/null)
    if [[ "$method" == "apt" ]]; then
        # APT PHP uses mods-available + conf.d symlinks per SAPI
        local sapi
        for sapi in fpm cli; do
            local conf_d="/etc/php/${ver}/${sapi}/conf.d"
            ensure_dirs "$conf_d"
            local priority=20
            [[ -e "${conf_d}/$(ls "${conf_d}" 2>/dev/null | grep -oP '\d+(?=-'"${ext}"')' | head -1)-${ext}.ini" ]] && continue
            ln -sf "$conf_file" "${conf_d}/${priority}-${ext}.ini"
        done
    else
        # Source PHP loads php.ini directly
        local ini_file
        ini_file=$(php_get_ini_path "$ver")
        if [[ -f "$ini_file" ]]; then
            if ! grep -q "extension=${ext}" "$ini_file" 2>/dev/null; then
                echo "extension=${ext}.so" >> "$ini_file"
            fi
        fi
    fi
}

php_ext_enable_zend() {
    local ext="$1"
    local ver="$2"
    local php_etc="${PHP_ETC_DIR}/php${ver}"
    local ext_dir
    ext_dir=$(php_get_ext_dir "$ver")

    local method
    method=$(php_install_method "$ver" 2>/dev/null)
    if [[ "$method" == "apt" ]]; then
        # Use mods-available for zend extensions too
        local mods_dir="${php_etc}/mods-available"
        ensure_dirs "$mods_dir"
        local conf_file="${mods_dir}/${ext}.ini"
        cat > "$conf_file" << EOF
zend_extension=${ext}.so
EOF
        local sapi
        for sapi in fpm cli; do
            local conf_d="/etc/php/${ver}/${sapi}/conf.d"
            ensure_dirs "$conf_d"
            ln -sf "$conf_file" "${conf_d}/00-${ext}.ini"
        done
    else
        local ini_file
        ini_file=$(php_get_ini_path "$ver")
        if [[ -f "$ini_file" ]]; then
            if ! grep -q "zend_extension.*${ext}" "$ini_file" 2>/dev/null; then
                sed_inplace "$ini_file" "1i zend_extension=${ext}.so"
            fi
        fi
    fi
}

php_ext_disable() {
    local ext="$1"
    local ver="$2"
    local php_etc="${PHP_ETC_DIR}/php${ver}"
    local mods_dir="${php_etc}/mods-available"

    rm -f "${mods_dir}/${ext}.ini"

    local method
    method=$(php_install_method "$ver" 2>/dev/null)
    if [[ "$method" == "apt" ]]; then
        # APT PHP loads extensions via conf.d symlinks; remove them for all SAPIs.
        local sapi
        for sapi in fpm cli; do
            local conf_d="/etc/php/${ver}/${sapi}/conf.d"
            rm -f "${conf_d}/"*"-${ext}.ini"
        done
    fi

    local ini_file
    ini_file=$(php_get_ini_path "$ver")
    if [[ -f "$ini_file" ]]; then
        sed_inplace "$ini_file" "/extension=${ext}/d"
        sed_inplace "$ini_file" "/zend_extension.*${ext}/d"
    fi

    log_success "Extension '${ext}' disabled for PHP ${ver}"
    systemctl restart "php${ver}-fpm" &>/dev/null
}

php_ext_batch_install() {
    local ver="$1"
    if [[ -z "$ver" ]]; then
        ver=$(php_select_version)
        [[ -z "$ver" ]] && return 1
    fi

    if ! php_is_installed "$ver"; then
        log_error "PHP ${ver} is not installed"
        return 1
    fi

    echo -e "\n${HEADER_COLOR}=== Batch Install Common Extensions for PHP ${ver} ===${C_RESET}"
    local -a common_exts=(imagick redis memcached mongodb swoole yaml)
    for ext in "${common_exts[@]}"; do
        if php_ext_is_installed "$ext" "$ver"; then
            log_info "${ext}: already installed, skipping"
        else
            php_ext_install "$ext" "$ver"
        fi
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
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1)
                local ver
                ver=$(php_select_version)
                [[ -z "$ver" ]] && continue
                local ext
                php_ext_list_available
                prompt_input "Extension name" "" ext
                [[ -n "$ext" ]] && php_ext_install "$ext" "$ver"
                ;;
            2)
                local ver
                ver=$(php_select_version)
                [[ -z "$ver" ]] && continue
                php_ext_list_installed "$ver"
                local ext
                prompt_input "Extension to disable" "" ext
                [[ -n "$ext" ]] && php_ext_disable "$ext" "$ver"
                ;;
            3)
                local ver
                ver=$(php_select_version)
                [[ -n "$ver" ]] && php_ext_list_installed "$ver"
                ;;
            4) php_ext_list_available ;;
            5)
                local ver
                ver=$(php_select_version)
                [[ -n "$ver" ]] && php_ext_batch_install "$ver"
                ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
