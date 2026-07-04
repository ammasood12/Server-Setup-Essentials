#!/usr/bin/env bash
#
# packages.sh - Package management and installation

install_packages() {
    section_title "Package Installation"
    echo
    echo "   1) Essential tools (curl, wget, nano, htop, vnstat)"
    echo "   2) Development tools (git, unzip, screen)"
    echo "   3) Network tools (speedtest-cli, traceroute, ethtool, net-tools)"
    echo "   4) System Update & Upgrade"
    echo "   5) All recommended packages"
    echo "   6) Custom selection"
    echo "   0) Cancel"
    echo
    
    read -rp "   Choose option [0-6]: " pkg_choice 
    
    local packages=()
    
    case $pkg_choice in
        1) packages=("curl" "wget" "nano" "htop" "vnstat") ;;
        2) packages=("git" "unzip" "screen") ;;
        3) 
            if [[ "$SSE_OS_TYPE" == "debian" ]]; then
                packages=("speedtest-cli" "traceroute" "net-tools" "dnsutils")
            else
                packages=("speedtest" "traceroute" "net-tools" "bind-utils")
            fi
            ;;
        4) 
            run_system_update_enhanced
            return
            ;;
        5) 
            packages=("${SSE_BASE_PACKAGES[@]}")
            if [[ "$SSE_OS_TYPE" == "centos" ]] && [[ ! " ${packages[*]} " =~ " epel-release " ]]; then
                packages+=("epel-release")
            fi
            ;;
        6) 
            echo "Enter package names separated by spaces:"
            read -r -a packages
            ;;
        0) 
            log_warn "Package installation cancelled"
            return
            ;;
        *) 
            log_warn "Invalid choice"
            return
            ;;
    esac
    
    if [[ ${#packages[@]} -eq 0 ]]; then 
        log_warn "No packages selected"
        return
    fi
    
    echo -e "Packages to install: ${CYAN}${packages[*]}${RESET}"
    read -rp "Proceed with installation? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { log_warn "Installation cancelled"; return; }
    
    pkg_update
    pkg_install "${packages[@]}" && log_ok "Packages installed successfully" || log_error "Some packages failed to install"
    pause
}

run_system_update_enhanced() {
    section_title "System Update & Upgrade"
    
    echo -e "${YELLOW}This will perform the following actions:${RESET}"
    echo "  🔄 Update package lists"
    echo "  ⬆️  Upgrade installed packages"
    echo "  🧹 Clean up unnecessary packages"
    echo
    
    read -rp "   Proceed with system update? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { log_warn "Update cancelled"; return 1; }
    
    sub_section "Step 1: Updating Package Lists"
    pkg_update
    
    sub_section "Step 2: Upgrading Packages"
    echo -e "${YELLOW}Note: This may take several minutes...${RESET}"
    pkg_upgrade
    
    sub_section "Step 3: Cleaning Up"
    pkg_autoremove
    
    if [[ "$SSE_OS_TYPE" == "centos" ]]; then
        if [[ -f /var/run/reboot-required ]] || needs-restarting -r 2>/dev/null | grep -q "Reboot is required"; then
            log_warn "⚠️  System reboot is recommended!"
        fi
    else
        if [[ -f /var/run/reboot-required ]]; then
            log_warn "⚠️  System reboot is required!"
        fi
    fi
    
    log_ok "System update completed successfully"
    pause
}
