#!/usr/bin/env bash
#
# Pig-NMP - Download Utilities
#

_DETECT_DOWNLOADER=""

_detect_downloader() {
    if [[ -z "$_DETECT_DOWNLOADER" ]]; then
        if command -v curl &>/dev/null; then
            _DETECT_DOWNLOADER="curl"
        elif command -v wget &>/dev/null; then
            _DETECT_DOWNLOADER="wget"
        else
            log_info "Installing curl..."
            install_deps curl
            _DETECT_DOWNLOADER="curl"
        fi
    fi
    echo "$_DETECT_DOWNLOADER"
}

download_file() {
    local url="$1" output="$2" retry="${3:-3}"
    _detect_downloader
    local dl="$_DETECT_DOWNLOADER"
    local attempt=1

    while (( attempt <= retry )); do
        case "$dl" in
            curl)
                if curl -fsSL --connect-timeout 30 --retry 2 -o "$output" "$url" 2>/dev/null; then
                    [[ -s "$output" ]] && return 0
                fi
                ;;
            wget)
                if wget -q --connect-timeout=30 -O "$output" "$url" 2>/dev/null; then
                    [[ -s "$output" ]] && return 0
                fi
                ;;
        esac
        log_warn "Download attempt $attempt/$retry failed: $url"
        ((attempt++))
        sleep 2
    done
    log_error "Failed to download: $url"
    return 1
}

download_with_mirror() {
    local url="$1" output="$2" retry="${3:-3}"
    if [[ "${MIRROR_CN}" == "true" ]]; then
        local mirrored
        mirrored=$(get_mirror_url "$url" 2>/dev/null)
        if [[ -n "$mirrored" && "$mirrored" != "$url" ]]; then
            log_info "Trying mirror: $mirrored"
            download_file "$mirrored" "$output" 1 && return 0
            log_warn "Mirror failed, trying original..."
        fi
    fi
    download_file "$url" "$output" "$retry"
}

extract_archive() {
    local archive="$1" dest_dir="${2:-.}"
    ensure_dirs "$dest_dir"
    case "$archive" in
        *.tar.gz|*.tgz)   tar -xzf "$archive" -C "$dest_dir" ;;
        *.tar.xz)         tar -xJf "$archive" -C "$dest_dir" ;;
        *.tar.bz2)        tar -xjf "$archive" -C "$dest_dir" ;;
        *.zip)             unzip -qo "$archive" -d "$dest_dir" ;;
        *)                 log_error "Unsupported archive: $archive"; return 1 ;;
    esac
}

verify_checksum() {
    local file="$1" expected="$2" type="${3:-sha256}"
    local actual
    case "$type" in
        sha256) actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}') ;;
        sha1)   actual=$(sha1sum "$file" 2>/dev/null | awk '{print $1}') ;;
        md5)    actual=$(md5sum "$file" 2>/dev/null | awk '{print $1}') ;;
        *)      log_error "Unsupported checksum type: $type"; return 1 ;;
    esac
    [[ "$actual" == "$expected" ]]
}

get_remote_version() {
    local url="$1" regex="${2:-}" tmp_file
    tmp_file=$(mktemp)
    if download_file "$url" "$tmp_file" 1; then
        if [[ -n "$regex" ]]; then
            grep -oP "$regex" "$tmp_file" | head -1
        else
            cat "$tmp_file"
        fi
        rm -f "$tmp_file"
        return 0
    fi
    rm -f "$tmp_file"
    return 1
}

download_and_extract() {
    local url="$1" dest_dir="$2" strip="${3:-0}"
    local tmp_file
    tmp_file=$(mktemp -d)/download.tmp
    download_with_mirror "$url" "$tmp_file" || { rm -rf "$tmp_file"; return 1; }
    ensure_dirs "$dest_dir"
    extract_archive "$tmp_file" "$dest_dir"
    local ret=$?
    rm -f "$tmp_file"
    if [[ $ret -eq 0 && $strip -gt 0 ]]; then
        local extracted_dir
        extracted_dir=$(find "$dest_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
        if [[ -n "$extracted_dir" && "$extracted_dir" != "$dest_dir" ]]; then
            shopt -s dotglob
            mv "$extracted_dir"/* "$dest_dir/" 2>/dev/null
            shopt -u dotglob
            rmdir "$extracted_dir" 2>/dev/null
        fi
    fi
    return $ret
}
