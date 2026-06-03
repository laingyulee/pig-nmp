#!/usr/bin/env bash
#
# Pig-NMP - Firewall (UFW) Module
#

firewall_is_installed() {
    is_installed ufw
}

firewall_is_active() {
    ufw status 2>/dev/null | grep -q "Status: active"
}

firewall_install() {
    if firewall_is_installed; then
        log_info "UFW is already installed"
        return 0
    fi

    log_info "Installing UFW..."
    apt_install ufw

    ufw allow 22/tcp &>/dev/null
    ufw default deny incoming &>/dev/null
    ufw default allow outgoing &>/dev/null

    log_success "UFW installed (default: deny incoming, allow outgoing, SSH allowed)"
}

firewall_enable() {
    if ! firewall_is_installed; then
        firewall_install
    fi

    if firewall_is_active; then
        log_info "UFW is already active"
        return 0
    fi

    echo -e "\n${C_YELLOW}WARNING: Enabling UFW may lock you out if SSH port is not allowed!${C_RESET}"
    if confirm "Make sure SSH (port 22) is allowed. Continue?" "y"; then
        ufw allow 22/tcp &>/dev/null
        echo "y" | ufw enable &>/dev/null
        log_success "UFW enabled"
    fi
}

firewall_disable() {
    if ! firewall_is_active; then
        log_info "UFW is not active"
        return 0
    fi

    if confirm "Disable UFW firewall?"; then
        ufw disable &>/dev/null
        log_success "UFW disabled"
    fi
}

firewall_preset() {
    local profile="$1"

    if [[ -z "$profile" ]]; then
        echo -e "\n${HEADER_COLOR}Select firewall security profile:${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Development - Open common ports (22,80,443,21,3306,6379,11211)"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Production - Web only (22,80,443)"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Strict - Web only + SSH restricted"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Custom - Choose ports manually"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice
        case "$choice" in
            1) profile="dev" ;;
            2) profile="prod" ;;
            3) profile="strict" ;;
            4) profile="custom" ;;
            *) return 1 ;;
        esac
    fi

    if ! firewall_is_installed; then
        firewall_install
    fi

    echo "y" | ufw reset &>/dev/null

    case "$profile" in
        dev)
            ufw allow 22/tcp &>/dev/null
            ufw allow 80/tcp &>/dev/null
            ufw allow 443/tcp &>/dev/null
            ufw allow 21/tcp &>/dev/null
            ufw allow 40000:40100/tcp &>/dev/null
            ufw allow 3306/tcp &>/dev/null
            ufw allow 6379/tcp &>/dev/null
            ufw allow 11211/tcp &>/dev/null
            log_success "Development profile applied"
            ;;
        prod)
            ufw allow 22/tcp &>/dev/null
            ufw allow 80/tcp &>/dev/null
            ufw allow 443/tcp &>/dev/null
            ufw allow 40000:40100/tcp &>/dev/null
            log_success "Production profile applied"
            ;;
        strict)
            local ssh_ip
            prompt_input "Restrict SSH to IP (leave empty for all)" "" ssh_ip
            if [[ -n "$ssh_ip" ]]; then
                ufw allow from "$ssh_ip" to any port 22 &>/dev/null
            else
                ufw allow 22/tcp &>/dev/null
            fi
            ufw allow 80/tcp &>/dev/null
            ufw allow 443/tcp &>/dev/null
            log_success "Strict profile applied"
            ;;
        custom)
            firewall_custom_rules
            return
            ;;
    esac

    echo "y" | ufw enable &>/dev/null
    firewall_status
}

firewall_custom_rules() {
    echo -e "\n${HEADER_COLOR}=== Custom Firewall Rules ===${C_RESET}"
    echo -e "Enter rules one at a time. Format: port/protocol (e.g., 80/tcp, 443/tcp, 40000:40100/tcp)"
    echo -e "Type 'done' when finished, 'reset' to start over.\n"

    while true; do
        local rule
        read -rp "$(echo -e "${C_CYAN}Add rule (port/protocol):${C_RESET} ")" rule
        case "$rule" in
            done) break ;;
            reset)
                echo "y" | ufw reset &>/dev/null
                log_info "Rules reset"
                ;;
            *)
                if [[ "$rule" =~ ^[0-9] ]]; then
                    ufw allow "$rule" &>/dev/null
                    log_info "Added rule: $rule"
                else
                    log_warn "Invalid format. Use: port/protocol (e.g., 8080/tcp)"
                fi
                ;;
        esac
    done

    echo "y" | ufw enable &>/dev/null
}

firewall_allow_port() {
    local port="$1"
    local proto="${2:-tcp}"

    if [[ -z "$port" ]]; then
        prompt_input "Port number (or range, e.g., 40000:40100)" "" port
    fi
    [[ -z "$port" ]] && return 1

    if ! firewall_is_installed; then
        firewall_install
    fi

    ufw allow "${port}/${proto}" &>/dev/null
    log_success "Allowed ${port}/${proto}"
}

firewall_deny_port() {
    local port="$1"
    local proto="${2:-tcp}"

    if [[ -z "$port" ]]; then
        prompt_input "Port number to deny" "" port
    fi
    [[ -z "$port" ]] && return 1

    ufw deny "${port}/${proto}" &>/dev/null
    log_success "Denied ${port}/${proto}"
}

firewall_allow_service() {
    local service="$1"

    if [[ -z "$service" ]]; then
        echo -e "\n${HEADER_COLOR}Quick allow service:${C_RESET}"
        local sel
        sel=$(prompt_select "Select service:" "SSH (22)" "HTTP (80)" "HTTPS (443)" "FTP (21)" "MySQL (3306)" "Redis (6379)" "Memcached (11211)" "FTP Passive (40000-40100)")
        case "$sel" in
            SSH*)         service="22/tcp" ;;
            HTTP*)        service="80/tcp" ;;
            HTTPS*)       service="443/tcp" ;;
            FTP*)         service="21/tcp" ;;
            MySQL*)       service="3306/tcp" ;;
            Redis*)       service="6379/tcp" ;;
            Memcached*)   service="11211/tcp" ;;
            FTP\ Passive*) service="40000:40100/tcp" ;;
        esac
    fi

    if ! firewall_is_installed; then
        firewall_install
    fi

    ufw allow "$service" &>/dev/null
    log_success "Allowed ${service}"
}

firewall_auto_configure() {
    if ! firewall_is_installed; then
        firewall_install
    fi

    log_info "Auto-configuring firewall for installed services..."

    ufw allow 22/tcp &>/dev/null
    ufw allow 80/tcp &>/dev/null
    ufw allow 443/tcp &>/dev/null

    if nginx_is_installed || is_installed nginx; then
        ufw allow 80/tcp &>/dev/null
        ufw allow 443/tcp &>/dev/null
    fi

    if ftp_is_installed; then
        ufw allow 21/tcp &>/dev/null
        ufw allow 40000:40100/tcp &>/dev/null
    fi

    if mysql_is_installed; then
        ufw deny 3306/tcp &>/dev/null
        log_info "MySQL port 3306 blocked (use SSH tunnel for remote access)"
    fi

    if redis_is_installed; then
        ufw deny 6379/tcp &>/dev/null
        log_info "Redis port 6379 blocked (should only listen on localhost)"
    fi

    if memcached_is_installed; then
        ufw deny 11211/tcp &>/dev/null
        log_info "Memcached port 11211 blocked (should only listen on localhost)"
    fi

    log_success "Firewall auto-configured"
}

firewall_status() {
    echo -e "\n${HEADER_COLOR}=== Firewall Status ===${C_RESET}"
    if ! firewall_is_installed; then
        print_status "UFW" "not_installed"
        return
    fi

    ufw status verbose 2>/dev/null
}

firewall_uninstall() {
    if ! firewall_is_installed; then
        log_warn "UFW is not installed"
        return 0
    fi

    if ! confirm "Uninstall UFW? This will disable the firewall."; then
        return 0
    fi

    ufw disable &>/dev/null
    apt_remove ufw
    log_success "UFW uninstalled"
}

firewall_menu() {
    while true; do
        echo -e "\n${HEADER_COLOR}=== Firewall (UFW) Management ===${C_RESET}"
        echo -e "  ${MENU_NUM_COLOR}1)${C_RESET} Install/Enable UFW"
        echo -e "  ${MENU_NUM_COLOR}2)${C_RESET} Disable UFW"
        echo -e "  ${MENU_NUM_COLOR}3)${C_RESET} Apply security profile"
        echo -e "  ${MENU_NUM_COLOR}4)${C_RESET} Allow port/service"
        echo -e "  ${MENU_NUM_COLOR}5)${C_RESET} Deny port"
        echo -e "  ${MENU_NUM_COLOR}6)${C_RESET} Auto-configure for installed services"
        echo -e "  ${MENU_NUM_COLOR}7)${C_RESET} Status"
        echo -e "  ${MENU_NUM_COLOR}8)${C_RESET} Uninstall UFW"
        echo -e "  ${MENU_NUM_COLOR}0)${C_RESET} Back"
        echo ""

        local choice
        read -rp "$(echo -e "${C_CYAN}Enter choice:${C_RESET} ")" choice

        case "$choice" in
            1) firewall_enable ;;
            2) firewall_disable ;;
            3) firewall_preset ;;
            4) firewall_allow_service ;;
            5) firewall_deny_port ;;
            6) firewall_auto_configure ;;
            7) firewall_status ;;
            8) firewall_uninstall ;;
            0) return 0 ;;
            *) log_warn "Invalid choice" ;;
        esac
    done
}
