#!/usr/bin/env bash
#
# logs.sh - System logs optimization

logs_optimization_menu() {
    section_title "System Logs Optimization"
    
    if [[ "$SSE_OS_TYPE" == "alpine" ]]; then
        echo -e "${RED}${BOLD}⚠️  Logs Optimization is not available in Alpine Linux${RESET}"
        echo -e "${YELLOW}Alpine uses BusyBox syslogd instead of systemd-journald${RESET}"
        echo -e "${YELLOW}Alternative approaches for Alpine:${RESET}"
        echo "   • Configure syslogd: /etc/conf.d/syslog"
        echo "   • Use logrotate with busybox"
        echo "   • Manual log management with cron jobs"
        echo
        read -rp "Press Enter to continue..." _
        return
    fi

    echo "   (Modify journald.conf.d)"
    echo
    echo "   1) Basic Journal Optimization (Recommended)"
    echo "   2) Custom Journal Limits"
    echo "   3) Vacuum Logs Only"
    echo "   4) View Current Log Usage"
    echo "   5) Remove All Optimization"
    echo "   0) Back to Main Menu"
    echo
    
    read -rp "   Choose option [0-5]: " choice
    
    case $choice in
        1) optimize_system_logs ;;
        2) set_custom_journal_limits ;;
        3) vacuum_logs_only ;;
        4) view_log_usage ;;
        5) remove_log_optimization ;;
        0) return ;;
        *) log_warn "Invalid choice" ;;
    esac
    pause
}

optimize_system_logs() {
    section_title "System Logs Optimization"
    
    echo -e "${BOLD}${GREEN}This will optimize system journal logs and rotation:${RESET}"
    echo "  ✅ Configure journald limits (SystemMaxUse=300M, RuntimeMaxUse=30M)"
    echo "  ✅ Vacuum existing journal logs"
    echo "  ✅ Restart journald service"
    echo
    
    read -rp "Proceed with system logs optimization? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || {
        log_warn "Logs optimization cancelled"
        return
    }
    
    sub_section "Step 1: Installing Required Packages"
    log_info "Installing log optimization tools..."
    if pkg_update && pkg_install "${SSE_LOG_OPTIMIZATION_PACKAGES[@]}"; then
        log_ok "Log optimization tools installed successfully"
    else
        log_error "Failed to install some packages"
        return 1
    fi
    
    sub_section "Step 2: Configuring Journald Limits"
    log_info "Configuring journald system limits..."
    
    local journald_conf_dir="/etc/systemd/journald.conf.d"
    local journald_conf="${journald_conf_dir}/99-vps-limits.conf"
    
    mkdir -p "$journald_conf_dir"
    
    if [[ -f "$journald_conf" ]]; then
        backup_file "$journald_conf"
    fi
    
    cat <<EOF > "$journald_conf"
# ======================================================================
# systemd-journald Configuration (Optimized for VPS 1–4 GB RAM)
# ======================================================================
[Journal]
Storage=persistent
Compress=yes
Seal=yes

RateLimitIntervalSec=30s
RateLimitBurst=10000

SystemMaxUse=300M
SystemKeepFree=50M
SystemMaxFileSize=10M

RuntimeMaxUse=30M
RuntimeMaxFileSize=5M

MaxRetentionSec=1month
MaxFileSec=1month

ForwardToSyslog=no
ForwardToKMsg=no
ForwardToConsole=no
ForwardToWall=no

MaxLevelStore=info
MaxLevelSyslog=warning
MaxLevelKMsg=notice
MaxLevelConsole=notice
MaxLevelWall=emerg
EOF

    log_ok "Journald configuration applied successfully"
    
    sub_section "Step 3: Restarting Journald Service"
    log_info "Restarting systemd-journald service..."
    if systemctl restart systemd-journald; then
        log_ok "Journald service restarted successfully"
    else
        log_warn "Failed to restart journald service"
    fi
    
    sub_section "Step 4: Cleaning Up Existing Journals"
    log_info "Vacuuming journal logs..."
    
    if journalctl --vacuum-size=300M 2>/dev/null; then
        log_ok "Journal logs vacuumed to 300MB limit"
    else
        log_warn "Failed to vacuum journal by size"
    fi
    
    if journalctl --vacuum-time=15days 2>/dev/null; then
        log_ok "Journal logs older than 15 days removed"
    else
        log_warn "Failed to vacuum journal by time"
    fi
    
    sub_section "Step 5: Optimizing Service Logs"
    local services=("nginx" "apache2" "mysql" "mariadb" "V2bX" "xray" "v2ray")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Optimizing logs for service: $service"
            
            journalctl --unit="$service" --vacuum-time=15days 2>/dev/null && \
            log_ok "Cleaned older than 15 days logs for $service" || \
            log_warn "No logs found for $service"
            
            systemctl restart "$service" 2>/dev/null && \
            log_ok "Restarted $service" || \
            log_warn "Could not restart $service"
        fi
    done
    
    sub_section "Step 6: Verification"
    log_info "Current journal usage:"
    journalctl --disk-usage
    
    echo
    log_ok "🎉 System logs optimization completed successfully!"
    echo -e "${GREEN}Journal logs are now optimized with proper limits and cleanup.${RESET}"
}

set_custom_journal_limits() {
    section_title "Custom Journal Limits"
    
    echo -e "${YELLOW}Enter custom journal limits (leave empty for default):${RESET}"
    read -rp "SystemMaxUse (default: 150M): " system_max
    read -rp "RuntimeMaxUse (default: 30M): " runtime_max
    read -rp "SystemMaxFileSize (default: 5M): " file_size
    read -rp "MaxRetentionSec (default: 1month): " retention
    
    system_max=${system_max:-"150M"}
    runtime_max=${runtime_max:-"30M"}
    file_size=${file_size:-"5M"}
    retention=${retention:-"1month"}
    
    log_info "Applying custom journal limits..."
    
    local journald_conf_dir="/etc/systemd/journald.conf.d"
    local journald_conf="${journald_conf_dir}/99-vps-limits.conf"
    
    mkdir -p "$journald_conf_dir"
    
    if [[ -f "$journald_conf" ]]; then
        backup_file "$journald_conf"
    fi
    
    cat <<EOF > "$journald_conf"
[Journal]
SystemMaxUse=${system_max}
RuntimeMaxUse=${runtime_max}
SystemMaxFileSize=${file_size}
MaxRetentionSec=${retention}
EOF

    systemctl restart systemd-journald
    log_ok "Custom journal limits applied successfully"
}

vacuum_logs_only() {
    section_title "Vacuum System Logs"
    
    echo -e "${GREEN}Current Journal Disk Usage:${RESET}"
    local before_usage=$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]\+[A-Z]' | head -1)
    local before_size=$(du -sh /var/log/journal 2>/dev/null | awk '{print $1}' || echo "0")
    
    printf "  ${CYAN}%-25s${RESET} ${YELLOW}%8s${RESET}\n" "Journal files:" "$before_usage"
    printf "  ${CYAN}%-25s${RESET} ${YELLOW}%8s${RESET}\n" "Disk usage:" "$before_size"
    echo
    
    echo -e "${YELLOW}Select vacuum option:${RESET}"
    echo "1) Vacuum to 50M size limit"
    echo "2) Vacuum logs older than 7 days"
    echo "3) Vacuum both size and time"
    echo "4) Custom vacuum parameters"
    echo "0) Cancel"
    echo
    
    read -rp "Choose option [1-5]: " vacuum_choice
    
    case $vacuum_choice in
        1)
            echo -e "\n${CYAN}Vacuuming logs to 50MB size limit...${RESET}"
            if journalctl --vacuum-size=50M 2>/dev/null; then
                show_vacuum_results "$before_usage" "$before_size"
                log_ok "Logs vacuumed to 50MB limit"
            else
                log_error "Failed to vacuum logs"
            fi
            ;;
        2)
            echo -e "\n${CYAN}Vacuuming logs older than 7 days...${RESET}"
            if journalctl --vacuum-time=7days 2>/dev/null; then
                show_vacuum_results "$before_usage" "$before_size"
                log_ok "Logs older than 7 days removed"
            else
                log_error "Failed to vacuum logs"
            fi
            ;;
        3)
            echo -e "\n${CYAN}Vacuuming logs by size and time...${RESET}"
            if journalctl --vacuum-size=50M --vacuum-time=7days 2>/dev/null; then
                show_vacuum_results "$before_usage" "$before_size"
                log_ok "Logs vacuumed by both size and time"
            else
                log_error "Failed to vacuum logs"
            fi
            ;;
        4)
            custom_vacuum_parameters "$before_usage" "$before_size"
            ;;
        0)
            log_warn "Vacuum operation cancelled"
            ;;
        *)
            log_warn "Invalid choice"
            ;;
    esac
}

show_vacuum_results() {
    local before_usage="$1"
    local before_size="$2"
    
    echo
    echo -e "${GREEN}Vacuum Results:${RESET}"
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${RESET}"
    
    local after_usage=$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]\+[A-Z]' | head -1)
    local after_size=$(du -sh /var/log/journal 2>/dev/null | awk '{print $1}' || echo "0")
    
    local usage_saved=$(calculate_savings "$before_usage" "$after_usage")
    local size_saved=$(calculate_savings "$before_size" "$after_size")
    
    printf "${CYAN}║${RESET} ${YELLOW}%-20s${RESET} ${GREEN}%8s${RESET} ${CYAN}→${RESET} ${GREEN}%8s${RESET} ${CYAN}(${GREEN}%s saved${RESET}${CYAN})${RESET} %15s ${CYAN}║${RESET}\n" \
        "Journal files:" "$before_usage" "$after_usage" "$usage_saved" ""
    
    printf "${CYAN}║${RESET} ${YELLOW}%-20s${RESET} ${GREEN}%8s${RESET} ${CYAN}→${RESET} ${GREEN}%8s${RESET} ${CYAN}(${GREEN}%s saved${RESET}${CYAN})${RESET} %15s ${CYAN}║${RESET}\n" \
        "Disk usage:" "$before_size" "$after_size" "$size_saved" ""
    
    local journal_files=$(find /var/log/journal -name "*.journal" 2>/dev/null | wc -l)
    local largest_file=$(find /var/log/journal -name "*.journal" -exec du -h {} \; 2>/dev/null | sort -hr | head -1 | awk '{print $1}')
    
    printf "${CYAN}║${RESET} ${YELLOW}%-20s${RESET} ${GREEN}%8d files${RESET} %30s ${CYAN}║${RESET}\n" \
        "Journal files count:" "$journal_files" ""
    
    if [[ -n "$largest_file" ]]; then
        printf "${CYAN}║${RESET} ${YELLOW}%-20s${RESET} ${GREEN}%8s${RESET} %30s ${CYAN}║${RESET}\n" \
            "Largest file:" "$largest_file" ""
    fi
    
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

calculate_savings() {
    local before="$1"
    local after="$2"
    
    local before_num=$(echo "$before" | grep -o '^[0-9.]\+')
    local before_unit=$(echo "$before" | grep -o '[A-Z]\+$')
    local after_num=$(echo "$after" | grep -o '^[0-9.]\+')
    local after_unit=$(echo "$after" | grep -o '[A-Z]\+$')
    
    if [[ "$before_unit" == "G" ]] && [[ "$after_unit" == "M" ]]; then
        before_num=$(echo "$before_num * 1024" | bc -l 2>/dev/null || echo "$before_num")
        before_unit="M"
    elif [[ "$before_unit" == "M" ]] && [[ "$after_unit" == "G" ]]; then
        after_num=$(echo "$after_num * 1024" | bc -l 2>/dev/null || echo "$after_num")
        after_unit="M"
    fi
    
    if [[ "$before_unit" == "$after_unit" ]] && command -v bc >/dev/null 2>&1; then
        local saved=$(echo "$before_num - $after_num" | bc -l 2>/dev/null)
        if (( $(echo "$saved > 0" | bc -l) )); then
            printf "%.1f%s" "$saved" "$before_unit"
        else
            echo "0$before_unit"
        fi
    else
        echo "N/A"
    fi
}

custom_vacuum_parameters() {
    local before_usage="$1"
    local before_size="$2"
    
    echo -e "\n${YELLOW}Custom Vacuum Parameters:${RESET}"
    read -rp "Size limit (e.g., 100M, 1G): " custom_size
    read -rp "Time limit (e.g., 7days, 1month, 2weeks): " custom_time
    
    [[ -z "$custom_size" && -z "$custom_time" ]] && {
        log_warn "No parameters specified"
        return
    }
    
    local vacuum_cmd="journalctl"
    [[ -n "$custom_size" ]] && vacuum_cmd="$vacuum_cmd --vacuum-size=$custom_size"
    [[ -n "$custom_time" ]] && vacuum_cmd="$vacuum_cmd --vacuum-time=$custom_time"
    
    echo -e "\n${CYAN}Executing: $vacuum_cmd${RESET}"
    
    if eval "$vacuum_cmd" 2>/dev/null; then
        show_vacuum_results "$before_usage" "$before_size"
        log_ok "Custom vacuum completed successfully"
    else
        log_error "Failed to execute custom vacuum"
    fi
}

view_log_usage() {
    section_title "Current Log Usage"
    
    echo -e "${GREEN}Journal Disk Usage:${RESET}"
    journalctl --disk-usage
    
    echo -e "\n${GREEN}Current Journal Configuration (Drop-ins):${RESET}"
    if [[ -d "/etc/systemd/journald.conf.d" ]]; then
        cat /etc/systemd/journald.conf.d/*.conf 2>/dev/null || echo "No drop-in files found"
    else
        echo "No drop-in files configured"
    fi
}

remove_log_optimization() {
    section_title "Remove Log Optimization"
    
    read -rp "Remove all log optimization settings? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || {
        log_warn "Operation cancelled"
        return
    }
    
    local journald_conf="/etc/systemd/journald.conf.d/99-vps-limits.conf"
    if [[ -f "$journald_conf" ]]; then
        rm -f "$journald_conf"
        log_ok "Journal drop-in configuration removed"
    else
        log_warn "No optimization configuration found"
    fi
    
    systemctl restart systemd-journald
    log_ok "Journald service restarted with default settings"
}
