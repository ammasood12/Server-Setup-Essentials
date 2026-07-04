#!/usr/bin/env bash
#
# Server Setup Essentials - Modular Entry Point
# - Interactive menu with beautiful dashboard
# - Network diagnostics and optimization tools
# - Safe swap management with intelligent detection
# - Timezone configuration
# - Software installation (multi-select)
# - Comprehensive network optimization

export SSE_APP_NAME="SERVER SETUP ESSENTIALS"
export SSE_VERSION="v2.5.7"

set -euo pipefail

# Dynamically resolve absolute path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all modules in the same directory
for module in "$SCRIPT_DIR"/*.sh; do
    if [[ -f "$module" ]]; then
        local_name="$(basename "$module")"
        if [[ "$local_name" =~ ^(benchmark|common|display|hostname|logs|network|packages|swap|timezone)\.sh$ ]]; then
            source "$module"
        fi
    fi
done

###### Quick Setup Orchestration ######

quick_setup_full() {
    section_title "Quick Server Setup"
    echo -e "${BOLD}${GREEN}This will perform the following actions:${RESET}"
    echo "  🔄 Update system packages"
    echo "  ✅ Clean up existing swap files/partitions"
    echo "  ✅ Auto-configure optimal swap (if needed)"
    echo "  ✅ Set timezone to ${SSE_DEFAULT_TIMEZONE}" 
    echo "  ✅ Install essential packages"
    echo "  ✅ Apply network optimization (BBR/BBR2)"
    echo "  ✅ Apply system logs optimization"
    echo -e "${YELLOW}Note: This is recommended for new servers${RESET}"
    echo
    
    read -rp "Proceed with quick setup? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { log_warn "Quick setup cancelled"; return; }
    
    sub_section "Step 1: System Update"
    run_system_update_enhanced
    
    sub_section "Step 2: Swap Configuration"
    cleanup_existing_swap
    local recommended=$(recommended_swap_mb)
    [[ $recommended -gt 0 ]] && setup_swap $recommended || log_ok "No swap configuration needed"
    
    sub_section "Step 3: Timezone Configuration"
    if timedatectl set-timezone "$SSE_DEFAULT_TIMEZONE" 2>/dev/null; then
        log_ok "Timezone set to: $(timedatectl show --property=Timezone --value)"
    elif [[ -f "/usr/share/zoneinfo/${SSE_DEFAULT_TIMEZONE}" ]]; then
        ln -sf "/usr/share/zoneinfo/${SSE_DEFAULT_TIMEZONE}" /etc/localtime
        echo "$SSE_DEFAULT_TIMEZONE" > /etc/timezone
        log_ok "Timezone set to: ${SSE_DEFAULT_TIMEZONE} (OpenRC fallback)"
    else
        log_warn "Failed to set timezone"
    fi
    
    sub_section "Step 4: Package Installation"
    pkg_install "${SSE_BASE_PACKAGES[@]}" && \
        log_ok "Packages installed successfully" || \
        log_warn "Some packages failed to install"
    
    sub_section "Step 5: Network Optimization"
    apply_network_optimization
    
    sub_section "Step 6: System Logs Optimization"
    optimize_system_logs
    
    log_ok "🎉 Quick setup completed successfully!"
    echo -e "${GREEN}Your server is now optimized and ready for use.${RESET}"
    pause
}

quick_setup_partial() {
    section_title "Quick Server Setup (Software+Swap+Network)"
    echo -e "${BOLD}${GREEN}This will perform the following actions:${RESET}"
    echo "  🔄 Update system packages"
    echo "  ✅ Clean up existing swap files/partitions"
    echo "  ✅ Auto-configure optimal swap (if needed)"
    echo "  ✅ Install essential packages"
    echo "  ✅ Apply network optimization (BBR/BBR2)"
    echo -e "${YELLOW}Note: This is recommended for new servers${RESET}"
    echo
    
    read -rp "Proceed with quick setup? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { log_warn "Quick setup cancelled"; return; }
    
    sub_section "Step 1: System Update"
    run_system_update_enhanced
    
    sub_section "Step 2: Swap Configuration"
    cleanup_existing_swap
    local recommended=$(recommended_swap_mb)
    [[ $recommended -gt 0 ]] && setup_swap $recommended || log_ok "No swap configuration needed"
        
    sub_section "Step 3: Package Installation"
    pkg_install "${SSE_BASE_PACKAGES[@]}" && \
        log_ok "Packages installed successfully" || \
        log_warn "Some packages failed to install"
    
    sub_section "Step 4: Network Optimization"
    apply_network_optimization
    
    log_ok "🎉 Quick setup completed successfully!"
    echo -e "${GREEN}Your server is now optimized and ready for use.${RESET}"
    pause
}

update_script() {
    echo -e "${CYAN}Fetching latest updates for Server Setup Essentials...${RESET}"
    local install_url="https://raw.githubusercontent.com/ammasood12/Server-Setup-Essentials/main/install.sh"
    if curl -fsSL "$install_url" | bash; then
        echo -e "${GREEN}Update completed successfully!${RESET}"
    else
        echo -e "${RED}Failed to update. Please check your network connection.${RESET}"
        exit 1
    fi
}

###### Main Menu ######

main_menu() {
    while true; do
        banner
        display_system_status
        echo
        echo -e "${BOLD}${MAGENTA}🏠 MAIN MENU${RESET}"
        echo
        
        local col1_width=25
        local col2_width=25
        
        printf "   ${ORANGE}%-${col1_width}s${RESET}" "1) Quick Setup (Full)"		
        printf "   ${CYAN}%-${col2_width}s${RESET}\n" "6) System Swap Management"        
        
        printf "   ${ORANGE}%-${col1_width}s${RESET}" "2) Quick Setup (Partial)"
        printf "   ${BLUE}%-${col2_width}s${RESET}\n" "7) Network Optimization"
        
        printf "   ${YELLOW}%-${col1_width}s${RESET}" "3) Essential Software"
        printf "   ${PURPLE}%-${col2_width}s${RESET}\n" "8) Logs Optimization"
        
        printf "   ${GREEN}%-${col1_width}s${RESET}" "4) Timezone Configuration"
        printf "   ${MAGENTA}%-${col2_width}s${RESET}\n" "9) Benchmark & Media Tools"
                
        printf "   ${GREEN}%-${col1_width}s${RESET}" "5) Change Server Hostname"
        printf "   ${CYAN}%-${col2_width}s${RESET}\n" "10) System Update & Upgrade"
        
        printf "   ${RED}%-${col1_width}s${RESET}" "0) Exit"
        printf "   ${YELLOW}%-${col2_width}s${RESET}\n" "11) Update Script & Restart"
        
        echo
        read -rp "   Choose option [0-11]: " choice
        case $choice in
            1) quick_setup_full ;;
            2) quick_setup_partial ;;
            3) install_packages ;;
            4) configure_timezone ;;
            5) configure_hostname ;;
            6) swap_management_menu ;;
            7) network_tools_menu ;;
            8) logs_optimization_menu ;;
            9) benchmark_menu ;;
            10) run_system_update_enhanced ;;
            11)
                update_script
                echo -e "${GREEN}Restarting Server Setup Essentials...${RESET}"
                sleep 2
                exec sse
                ;;
            0)
                echo
                log_ok "   Thank you for using Server Setup Essentials! 👋"
                echo -e "${GREEN}Log file: ${SSE_LOG_FILE}${RESET}"
                exit 0
                ;;
            *) log_warn "Invalid choice"; pause ;;
        esac
    done
}

###### Core Execution ######

main() {
    # Check for CLI arguments first
    if [[ $# -gt 0 ]]; then
        case "$1" in
            update)
                update_script
                exit 0
                ;;
            version|--version|-v)
                echo -e "${CYAN}Server Setup Essentials ${SSE_VERSION}${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown argument: $1${RESET}"
                echo "Usage: sse [update|version]"
                exit 1
                ;;
        esac
    fi

    require_root
    

    install_script_dependencies
    trap 'echo; log_error "Script interrupted"; exit 1' INT TERM
    
    echo "=== Server Setup Essentials $SSE_VERSION - $(date) ===" > "$SSE_LOG_FILE"
    
    if [[ "$SSE_OS_TYPE" == "unknown" ]]; then
        log_warn "This script is optimized for Debian/Ubuntu, CentOS/RHEL, and Alpine based systems"
        read -rp "Continue anyway? (y/N): " proceed
        [[ $proceed =~ ^[Yy]$ ]] || exit 1
    fi
    
    log_info "Detected OS: $SSE_OS_TYPE, Package Manager: $SSE_PKG_MANAGER"

    sse_init_session_cache
    main_menu
}

main "$@"
