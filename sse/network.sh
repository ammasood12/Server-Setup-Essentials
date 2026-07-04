#!/usr/bin/env bash
#
# network.sh - Network tools and optimization

network_tools_menu() {
    while true; do        
        section_title "Network Tools & Optimization"
        echo "   (Modify sysctl.d)"
        echo
        echo "   1) Run Network Diagnostics"
        echo "   2) Apply Network Optimization (BBR/BBR2)"
        echo "   3) Restore Network Settings"
        echo "   4) Install Network Tools"
        echo "   0) Back to Main Menu"
        echo
        
        read -rp "   Choose option [0-4]: " choice
        case $choice in
            1) network_diagnostics; pause ;;
            2) apply_network_optimization; pause ;;
            3) restore_network_settings; pause ;;
            4) install_network_tools; pause ;;
            0) return ;;
            *) log_warn "Invalid choice"; pause ;;
        esac
    done
}

install_network_tools() {
    sub_section "Installing Network Tools"
    
    if [[ "$SSE_OS_TYPE" == "centos" ]] && [[ "$SSE_PKG_MANAGER" == "yum" ]] && ! rpm -q epel-release &>/dev/null; then
        log_info "Installing EPEL repository..."
        yum install -y epel-release
    fi
    
    log_info "Updating package lists..."
    pkg_update
    
    log_info "Installing network diagnostic tools..."
    if pkg_install "${SSE_NETWORK_PACKAGES[@]}"; then
        log_ok "Network tools installed successfully"
    else
        log_error "Failed to install some network tools"
        return 1
    fi
}

network_diagnostics() {
    section_title "Network Diagnostics"
    install_network_tools
    
    echo -e "${BOLD}${GREEN}🌐 Running Network Tests...${RESET}"
    echo
    
    sub_section "Ping Tests"
    declare -A ping_hosts=([Google]="8.8.8.8" [Cloudflare]="1.1.1.1" [AliDNS]="223.5.5.5" [Quad9]="9.9.9.9")
    for name in "${!ping_hosts[@]}"; do
        echo -e "${CYAN}Pinging ${name} (${ping_hosts[$name]})...${RESET}"
        ping -c 4 -W 3 "${ping_hosts[$name]}" 2>/dev/null | tail -n2 || echo -e "${RED}Failed to ping ${ping_hosts[$name]}${RESET}\n"
    done
    
    sub_section "Network Route Analysis"
    echo -e "${CYAN}Traceroute to 8.8.8.8 (first 10 hops):${RESET}"
    traceroute -m 10 8.8.8.8 2>/dev/null | head -n 15 || log_warn "Traceroute not available"
    
    sub_section "Network Interface Status"
    for i in $(ls /sys/class/net | grep -v lo); do
        local IP=$(ip -4 addr show $i | grep inet | awk '{print $2}' | head -n1)
        echo -e "${CYAN}Interface ${i}:${RESET} ${IP:-${RED}No IP${RESET}}"
    done
    
    log_ok "Network diagnostics completed"
}

apply_network_optimization() {
    section_title "Applying Network Optimization"
    
    log_info "Checking BBR availability..."
    local bbr_mode="bbr"
    if modprobe tcp_bbr2 2>/dev/null; then
        echo -e "${GREEN}BBR2 is available${RESET}"
        read -rp "Use BBR2 instead of BBR? [Y/n]: " use_bbr2
        [[ "$use_bbr2" =~ ^[Yy]$|^$ ]] && bbr_mode="bbr2"
    else
        log_warn "BBR2 not available, using BBR"
    fi
    
    local sysctl_conf="/etc/sysctl.d/99-vps-optimization.conf"
    
    log_info "Applying network optimization settings to ${sysctl_conf}..."
    mkdir -p /etc/sysctl.d
    
    if [[ -f "$sysctl_conf" ]]; then
        backup_file "$sysctl_conf"
    fi
    
    cat <<EOF > "$sysctl_conf"
# ============================================================
# Universal sysctl.conf for VPS (Generalized, Safe Everywhere)
# ============================================================

######## Core Network Optimization ########
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = ${bbr_mode}

######## Connection Stability ########
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3

######## MTU & RTT Optimization ########
net.ipv4.tcp_mtu_probing = 1

######## TCP Buffers ########
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608

######## UDP / QUIC Optimization ########
net.core.rmem_default = 2097152
net.core.wmem_default = 2097152
net.ipv4.udp_mem = 8388608 12582912 16777216
net.ipv4.udp_rmem_min = 65536
net.ipv4.udp_wmem_min = 65536

######## NIC / Packet Processing ########
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 5000

######## Queue / Backlog ########
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_max_syn_backlog = 4096

######## Port Range ########
net.ipv4.ip_local_port_range = 10240 65535

######## Security ########
net.ipv4.tcp_syncookies = 1

######## Routing ########
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

######## Disable IPv6 ########
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0

######## File Handles ########
fs.file-max = 500000

######## Virtual Memory ########
vm.swappiness = 10
EOF

    sysctl --ignore --system 2>/dev/null || sysctl -p "$sysctl_conf" 2>/dev/null || true
    log_ok "Network optimization applied successfully with ${bbr_mode}"
    sub_section "Verification"
    echo -e "${BLUE}✓ Congestion Control:${RESET} $(sysctl -n net.ipv4.tcp_congestion_control)"
    echo -e "${BLUE}✓ Default Qdisc:${RESET} $(sysctl -n net.core.default_qdisc)"
    echo -e "${BLUE}✓ IPv4 Forwarding:${RESET} $(sysctl -n net.ipv4.ip_forward)"
    install_sysctl_service
}

install_sysctl_service() {
    log_info "Installing persistent sysctl reload service..."
    cat > /etc/systemd/system/sysctl-reload.service << 'EOF'
[Unit]
Description=Reload sysctl settings on boot
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/sysctl --ignore --system
RemainAfterExit=yes
SuccessExitStatus=1

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sysctl-reload
    systemctl start sysctl-reload
    log_ok "sysctl-reload service installed and enabled"
}

restore_network_settings() {
    section_title "Restore Network Settings"
    local sysctl_conf="/etc/sysctl.d/99-vps-optimization.conf"
    local last_backup=$(ls -t ${sysctl_conf}.bak-* 2>/dev/null | head -n1)
    
    if [[ -z "$last_backup" ]]; then
        log_error "No backup found to restore in /etc/sysctl.d/"
        return 1
    fi
    
    echo -e "Last backup: ${CYAN}${last_backup}${RESET}"
    read -rp "Restore this backup? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Restoring network settings from backup..."
        if cp "$last_backup" "$sysctl_conf" && sysctl --system >/dev/null 2>&1; then
            log_ok "Network settings restored successfully"
        else
            log_error "Failed to restore network settings"
        fi
    else
        log_warn "Restore cancelled"
    fi
}
