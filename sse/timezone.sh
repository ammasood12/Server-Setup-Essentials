#!/usr/bin/env bash
#
# timezone.sh - Timezone configuration

configure_timezone() {
    section_title "Timezone Configuration"

    local current_tz
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")
    echo
    echo -e "   Current timezone: ${CYAN}${current_tz}${RESET}"
    
    local col1_width=20
    local col2_width=10
    
    echo -e "   ${YELLOW}Cloud billing reset times:${RESET}"
    
    printf "   ${CYAN}%-${col1_width}s${RESET}" "   UTC"
    printf "   ${MAGENTA}%-${col2_width}s${RESET}\n" "→ DigitalOcean, UpCloud"
    printf "   ${CYAN}%-${col1_width}s${RESET}" "   Etc/GMT+5"
    printf "   ${MAGENTA}%-${col2_width}s${RESET}\n" "→ Linode"
    printf "   ${CYAN}%-${col1_width}s${RESET}" "   Etc/GMT+16"
    printf "   ${MAGENTA}%-${col2_width}s${RESET}\n" "→ LightNode"
    printf "   ${CYAN}%-${col1_width}s${RESET}" "   Default: etc/UTC"
    printf "   ${MAGENTA}%-${col2_width}s${RESET}\n" "→ UltraHost"   
    printf "   ${CYAN}%-${col1_width}s${RESET}" "   Other Timezones"
    printf "   ${MAGENTA}%-${col2_width}s${RESET}\n" "Asia/Tokyo, Asia/Singapore, Asia/Karachi"   
    
    echo
    echo "   1) etc/UTC"
    echo "   2) Etc/GMT+5"
    echo "   3) Etc/GMT+16"
    echo "   4) Asia/Shanghai"
    echo "   5) America/New_York"
    echo "   6) UTC"
    echo "   7) Custom input"
    echo "   0) Cancel"
    echo

    read -rp "   Choose option [0-7]: " tz_choice

    local new_tz=""
    case "$tz_choice" in
        1) new_tz="etc/UTC" ;;
        2) new_tz="Etc/GMT+5" ;;
        3) new_tz="Etc/GMT+16" ;;
        4) new_tz="Asia/Shanghai" ;;
        5) new_tz="America/New_York" ;;
        6) new_tz="UTC" ;;
        7) 
            read -rp "Enter custom timezone (e.g., Europe/Berlin): " new_tz
            if [[ -z "$new_tz" ]]; then
                log_warn "No timezone entered. Cancelled."
                return
            fi 
            ;;
        0) 
            log_warn "Timezone change cancelled."
            return 
            ;;
        *) 
            log_warn "Invalid choice."
            return 
            ;;
    esac

    # Validate timezone against /usr/share/zoneinfo/
    if [[ ! -f "/usr/share/zoneinfo/${new_tz}" ]] && [[ "$new_tz" != "UTC" ]] && [[ "$new_tz" != "etc/UTC" ]]; then
        # Some generic strings might map slightly differently, but generally this check is robust
        # for standard IANA timezones.
        log_error "Invalid timezone: ${new_tz}. Not found in /usr/share/zoneinfo/."
        return
    fi

    # Apply timezone
    if timedatectl set-timezone "$new_tz" 2>/dev/null; then
        log_ok "Timezone successfully set to: ${CYAN}$(timedatectl show --property=Timezone --value)${RESET}"
    else
        log_error "Failed to set timezone: $new_tz"
    fi

    pause
}
