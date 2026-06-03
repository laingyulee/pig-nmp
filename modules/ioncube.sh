#!/usr/bin/env bash
#
# Pig-NMP - ionCube Loader Module
#

source "${CONF_DIR}/versions.conf"

ioncube_is_installed() {
    local ver="$1"
    if [[ -n "$ver" ]]; then
        local php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
        if [[ -x "$php_bin" ]]; then
            "$php_bin" -v 2>/dev/null | grep -qi "ionCube"
        fi
    else
        local versions
        versions=$(get_php_versions_installed)
        if [[ -n "$versions" ]]; then
            while IFS= read -r v; do
                if ioncube_is_installed "$v"; then
                    return 0
                fi
            done <<< "$versions"
        fi
        return 1
    fi
}

ioncube_install() {
    local ver="${1:-}"

    if [[ -z "$ver" ]]; then
        local versions
        versions=$(get_php_versions_installed)
        if [[ -z "$versions" ]]; then
            log_error "No PHP versions installed. Please install PHP first."
            return 1
        fi
        local -a opts=()
        while IFS= read -r v; do
            if ioncube_is_installed "$v"; then
                opts+=("PHP ${v} (already installed)")
            else
                opts+=("PHP ${v}")
            fi
        done <<< "$versions"
        local sel
        sel=$(prompt_select "Select PHP version for ionCube:" "${opts[@]}")
        ver="${sel#PHP }"
        ver="${ver%% *}"
    fi

    if ! php_is_installed "$ver"; then
        log_error "PHP ${ver} is not installed"
        return 1
    fi

    if ioncube_is_installed "$ver"; then
        log_warn "ionCube is already installed for PHP ${ver}"
        if ! confirm "Reinstall?"; then
            return 0
        fi
        ioncube_uninstall "$ver"
    fi

    log_info "Installing ionCube Loader for PHP ${ver}..."

    ensure_dirs "$TMP_DIR" "$IONCUBE_DIR"

    local url="$IONCUBE_DOWNLOAD_URL"
    local archive="${TMP_DIR}/ioncube_loaders.tar.gz"

    if ! download_file "$url" "$archive"; then
        log_error "Failed to download ionCube Loaders"
        return 1
    fi

    tar -xzf "$archive" -C "${INSTALL_PREFIX}/" 2>/dev/null
    rm -f "$archive"

    local loader_dir="${INSTALL_PREFIX}/ioncube"
    if [[ ! -d "$loader_dir" ]]; then
        log_error "ionCube extraction failed"
        return 1
    fi

    local loader_file="${loader_dir}/ioncube_loader_lin_${ver}.so"

    if [[ ! -f "$loader_file" ]]; then
        log_error "ionCube loader not found for PHP ${ver}"
        log_error "Available loaders:"
        ls -1 "${loader_dir}"/ioncube_loader_lin_*.so 2>/dev/null | while read f; do
            echo "  $(basename "$f")"
        done
        return 1
    fi

    local ext_dir
    ext_dir=$(php_get_ext_dir "$ver")
    if [[ -z "$ext_dir" ]] || [[ ! -d "$ext_dir" ]]; then
        ext_dir="${PHP_BASE_DIR}/php${ver}/lib/php/extensions/no-debug-non-zts-*"
        ext_dir=$(ls -d "$ext_dir" 2>/dev/null | head -1)
    fi

    if [[ -z "$ext_dir" ]] || [[ ! -d "$ext_dir" ]]; then
        log_error "Cannot find PHP extension directory for PHP ${ver}"
        return 1
    fi

    cp -a "$loader_file" "${ext_dir}/"
    chmod 755 "${ext_dir}/$(basename "$loader_file")"

    log_info "Configuring php.ini for PHP ${ver}..."
    local ini_file
    ini_file=$(php_get_ini_path "$ver")
    if [[ ! -f "$ini_file" ]]; then
        ini_file="${PHP_ETC_DIR}/php${ver}/php.ini"
    fi

    if [[ -f "$ini_file" ]]; then
        if grep -q "zend_extension.*ioncube" "$ini_file" 2>/dev/null; then
            log_info "ionCube zend_extension already in php.ini"
        else
            local loader_path="${ext_dir}/$(basename "$loader_file")"
            local tmp_ini="${ini_file}.tmp"
            {
                echo ""
                echo "[ionCube Loader]"
                echo "zend_extension=${loader_path}"
                cat "$ini_file"
            } > "$tmp_ini"
            mv "$tmp_ini" "$ini_file"

            log_info "Added ionCube to the beginning of php.ini (must be first zend_extension)"
        fi
    fi

    systemctl restart "php${ver}-fpm" &>/dev/null

    local php_bin="${PHP_BASE_DIR}/php${ver}/bin/php"
    if "$php_bin" -v 2>/dev/null | grep -qi "ionCube"; then
        log_success "ionCube Loader installed for PHP ${ver}"
        "$php_bin" -v | head -1
    else
        log_error "ionCube installation verification failed"
        log_error "Check ${ini_file} for the zend_extension line"
        return 1
    fi
}

ioncube_uninstall() {
    local ver="$1"
    if [[ -z "$ver" ]]; then
        ver=$(php_select_version)
        [[ -z "$ver" ]] && return 1
    fi

    if ! ioncube_is_installed "$ver"; then
        log_warn "ionCube is not installed for PHP ${ver}"
        return 0
    fi

    if ! confirm "Uninstall ionCube for PHP ${ver}?"; then
        return 0
    fi

    local ini_file
    ini_file=$(php_get_ini_path "$ver")
    [[ ! -f "$ini_file" ]] && ini_file="${PHP_ETC_DIR}/php${ver}/php.ini"

    if [[ -f "$ini_file" ]]; then
        sed_inplace "$ini_file" "/ioncube_loader_lin/d"
        sed_inplace "$ini_file" "/\[ionCube Loader\]/d"
        sed_inplace "$ini_file" "/^$/N;/^\n$/d"
    fi

    local ext_dir
    ext_dir=$(php_get_ext_dir "$ver")
    rm -f "${ext_dir}"/ioncube_loader_lin_*.so 2>/dev/null

    systemctl restart "php${ver}-fpm" &>/dev/null

    if ! ioncube_is_installed "$ver"; then
        log_success "ionCube uninstalled for PHP ${ver}"
    else
        log_error "Failed to uninstall ionCube for PHP ${ver}"
    fi
}

ioncube_status() {
    echo -e "\n${HEADER_COLOR}=== ionCube Loader Status ===${C_RESET}"
    local versions
    versions=$(get_php_versions_installed)
    if [[ -z "$versions" ]]; then
        print_status "ionCube" "not_installed (no PHP)"
        return
    fi
    while IFS= read -r ver; do
        local status="not installed"
        ioncube_is_installed "$ver" && status="installed"
        printf "  PHP %-6s ionCube: %s\n" "$ver" "$status"
    done <<< "$versions"
}

ioncube_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== ionCube Loader Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install ionCube"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Uninstall ionCube"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) ioncube_install ;;
            2) ioncube_uninstall ;;
            3) ioncube_status ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
