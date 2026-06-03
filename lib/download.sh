#!/usr/bin/env bash
#
# Pig-NMP - Download Utility Functions
#

source "${LIB_DIR}/common.sh"

WGET_CMD=""
CURL_CMD=""

_detect_downloader() {
    if command -v wget &>/dev/null; then
        WGET_CMD="wget"
    fi
    if command -v curl &>/dev/null; then
        CURL_CMD="curl"
    fi
    if [[ -z "$WGET_CMD" ]] && [[ -z "$CURL_CMD" ]]; then
        apt-get update -qq && apt-get install -y -qq curl wget
        WGET_CMD="wget"
        CURL_CMD="curl"
    fi
}

download_file() {
    local url="$1"
    local output="$2"
    local retry="${3:-3}"
    _detect_downloader

    log_info "Downloading: $(basename "$output")"
    echo -e "  ${C_CYAN}URL: ${url}${C_RESET}" >&2

    local attempt=0
    while [[ $attempt -lt $retry ]]; do
        attempt=$((attempt + 1))
        if [[ -n "$CURL_CMD" ]]; then
            if curl -fSL --connect-timeout 30 --max-time 1200 --retry 2 --retry-delay 5 \
                -o "$output" "$url" 2>/dev/null; then
                if [[ -f "$output" ]] && [[ $(stat -c%s "$output" 2>/dev/null || echo 0) -gt 10240 ]]; then
                    log_success "Downloaded: $(basename "$output")"
                    return 0
                fi
            fi
        elif [[ -n "$WGET_CMD" ]]; then
            if wget --quiet --timeout=30 --tries=2 --waitretry=5 -O "$output" "$url" 2>/dev/null; then
                if [[ -f "$output" ]] && [[ $(stat -c%s "$output" 2>/dev/null || echo 0) -gt 10240 ]]; then
                    log_success "Downloaded: $(basename "$output")"
                    return 0
                fi
            fi
        fi
        log_warn "Download attempt $attempt/$retry failed: $(basename "$output")"
        rm -f "$output" 2>/dev/null
        sleep 3
    done

    log_error "Failed to download after $retry attempts: $url"
    return 1
}

download_with_mirror() {
    local url="$1"
    local output="$2"
    local mirrors_conf="${CONF_DIR}/mirrors.conf"

    if [[ -f "$mirrors_conf" ]] && [[ "$MIRROR_CN" == "true" ]]; then
        source "$mirrors_conf"
        local mirror_url
        mirror_url=$(get_mirror_url "$url" 2>/dev/null)
        if [[ -n "$mirror_url" ]]; then
            log_info "Using mirror: $mirror_url"
            if download_file "$mirror_url" "$output" 1; then
                return 0
            fi
            log_warn "Mirror failed, falling back to official source"
        fi
    fi

    download_file "$url" "$output"
}

extract_archive() {
    local archive="$1"
    local dest="${2:-.}"
    local strip="${3:-1}"

    case "$archive" in
        *.tar.gz|*.tgz)
            tar -xzf "$archive" -C "$dest" --strip-components="$strip"
            ;;
        *.tar.xz)
            tar -xJf "$archive" -C "$dest" --strip-components="$strip"
            ;;
        *.tar.bz2)
            tar -xjf "$archive" -C "$dest" --strip-components="$strip"
            ;;
        *.zip)
            if [[ "$strip" -gt 0 ]]; then
                local tmp_dir
                tmp_dir=$(mktemp -d)
                unzip -q -o "$archive" -d "$tmp_dir"
                local inner
                inner=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
                if [[ -n "$inner" ]]; then
                    cp -a "$inner"/. "$dest"/
                fi
                rm -rf "$tmp_dir"
            else
                unzip -q -o "$archive" -d "$dest"
            fi
            ;;
        *)
            log_error "Unknown archive format: $archive"
            return 1
            ;;
    esac
}

verify_checksum() {
    local file="$1"
    local expected="$2"
    local algo="${3:-sha256}"
    local actual

    if ! is_installed "${algo}sum"; then
        log_warn "${algo}sum not found, skipping checksum verification"
        return 0
    fi

    actual=$("${algo}sum" "$file" | awk '{print $1}')
    if [[ "$actual" == "$expected" ]]; then
        log_success "Checksum verified: $(basename "$file")"
        return 0
    else
        log_error "Checksum mismatch for $(basename "$file")"
        log_error "Expected: $expected"
        log_error "Actual:   $actual"
        return 1
    fi
}

get_remote_version() {
    local url="$1"
    local regex="${2:-}"
    local content
    _detect_downloader

    if [[ -n "$CURL_CMD" ]]; then
        content=$(curl -fSL --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
    elif [[ -n "$WGET_CMD" ]]; then
        content=$(wget -qO- --timeout=10 "$url" 2>/dev/null)
    fi

    if [[ -n "$regex" ]] && [[ -n "$content" ]]; then
        echo "$content" | grep -oP "$regex" | head -1
    else
        echo "$content"
    fi
}

download_and_extract() {
    local url="$1"
    local dest="$2"
    local strip="${3:-1}"
    local tmp_file

    ensure_dirs "$TMP_DIR" "$dest"
    tmp_file="${TMP_DIR}/$(basename "$url")"

    if ! download_with_mirror "$url" "$tmp_file"; then
        return 1
    fi

    log_info "Extracting: $(basename "$tmp_file")"
    if ! extract_archive "$tmp_file" "$dest" "$strip"; then
        log_error "Extraction failed: $(basename "$tmp_file")"
        return 1
    fi

    rm -f "$tmp_file"
    return 0
}

pecl_install() {
    local ext="$1"
    local php_ver="$2"
    local php_prefix="${PHP_BASE_DIR}/php${php_ver}"
    local phpize="${php_prefix}/bin/phpize"
    local php_config="${php_prefix}/bin/php-config"

    if [[ ! -x "$phpize" ]]; then
        log_error "phpize not found for PHP ${php_ver}"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir" || return 1

    log_info "Downloading PECL extension: ${ext}"
    if ! "${php_prefix}/bin/pecl" download "$ext" &>/dev/null; then
        log_error "Failed to download PECL extension: ${ext}"
        cd - || return 1
        rm -rf "$tmp_dir"
        return 1
    fi

    local ext_dir
    ext_dir=$(find . -maxdepth 1 -type d -name "${ext}*" | head -1)
    if [[ -z "$ext_dir" ]]; then
        log_error "Cannot find extracted extension directory"
        cd - || return 1
        rm -rf "$tmp_dir"
        return 1
    fi

    cd "$ext_dir" || return 1

    log_info "Compiling ${ext} for PHP ${php_ver}"
    "$phpize" &>/dev/null && \
    ./configure --with-php-config="$php_config" &>/dev/null && \
    make -j"$(nproc)" &>/dev/null && \
    make install &>/dev/null

    local ret=$?
    cd - || return 1
    rm -rf "$tmp_dir"

    if [[ $ret -eq 0 ]]; then
        log_success "PECL extension ${ext} compiled for PHP ${php_ver}"
    else
        log_error "Failed to compile PECL extension: ${ext}"
    fi
    return $ret
}
