#!/usr/bin/env bash
#
# hostname.sh - Server hostname configuration

configure_hostname() {
    section_title "Change Server Hostname"

    local current_hostname new_hostname
    
    current_hostname=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "Unknown")
    
    echo
    echo -e "   Current Hostname: ${CYAN}${current_hostname}${RESET}"
    echo

    read -rp "   Enter new hostname: " new_hostname
    
    if [[ -z "$new_hostname" ]]; then
        log_warn "No hostname entered. Cancelled."
        return
    fi
    
    if [[ ! "$new_hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || [[ ${#new_hostname} -gt 63 ]]; then
        log_error "Invalid hostname format. Hostname must be 1-63 characters, alphanumeric with hyphens only, and cannot start or end with hyphen."
        return
    fi
    
    echo
    echo -e "   You are about to change hostname from: ${CYAN}${current_hostname}${RESET}"
    echo -e "   To: ${CYAN}${new_hostname}${RESET}"
    echo
    read -rp "   Confirm hostname change? (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Hostname change cancelled by user."
        return
    fi
    
    if hostnamectl set-hostname "$new_hostname" 2>/dev/null; then
        echo "$new_hostname" | tee /etc/hostname >/dev/null 2>&1
        
        if grep -q "127.0.1.1" /etc/hosts 2>/dev/null; then
            sed -i "s/127.0.1.1.*$/127.0.1.1\t$new_hostname/" /etc/hosts 2>/dev/null
        fi
        
        log_ok "Hostname successfully changed to: ${CYAN}$new_hostname${RESET}"
        log_info "Note: Full hostname change may require a reboot to take effect everywhere."
        
        echo
        echo -e "   New Hostname: ${CYAN}$(hostname)${RESET}"
    else
        log_error "Failed to set hostname: $new_hostname"
        log_info "You may need to run this script with appropriate privileges."
    fi

    pause
}
