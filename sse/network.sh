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
    
    log_info "Applying network optimization settings to ${sysctl_conf}..."
	
    local sysctl_conf_org="/etc/sysctl.conf"
    if [[ -f "$sysctl_conf_org" ]]; then
        mv /etc/sysctl.conf /etc/sysctl.conf.bk_org
    fi
    
    local sysctl_conf="/etc/sysctl.d/99-vps-optimization.conf"
    mkdir -p /etc/sysctl.d
    
    if [[ -f "$sysctl_conf" ]]; then
        backup_file "$sysctl_conf"
    fi
    
    cat <<EOF > "$sysctl_conf"
# ============================================================
# Universal sysctl.conf for VPS (Generalized, Safe Everywhere)
# version: v07.2
# ============================================================
######## Core Network Optimization ########
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

######## Connection Stability ########
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 5000
# Caps max TIME_WAIT sockets to prevent memory exhaustion under tw_reuse churn on small-RAM boxes
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_synack_retries = 2
# Reduces SYN-ACK retry count from default 5 -> faster resource release under load/SYN flood

######## MTU & RTT Optimization ########
net.ipv4.tcp_mtu_probing = 1

######## TCP Buffers ########
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608
# 2GB+ VPS override — raises ceiling for high-BDP long-haul paths (UK/DE relay legs)
# net.core.rmem_max = 33554432
# net.core.wmem_max = 12582912
# net.ipv4.tcp_rmem = 4096 131072 33554432
# net.ipv4.tcp_wmem = 4096 16384 12582912

# BBR pacing buffer — default 1MB throttles BBR's output on high-BDP paths regardless
# of tcp_wmem size above. This is the actual throughput-limiting default, not wmem.
net.ipv4.tcp_limit_output_bytes = 4194304

######## UDP / QUIC Optimization ########
net.core.rmem_default = 2097152
net.core.wmem_default = 2097152
# Values in PAGES (4KB each), not bytes. Sized for ~256MB/512MB/1GB ceiling.
# before
# net.ipv4.udp_mem = 8388608 12582912 16777216
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.udp_rmem_min = 65536
net.ipv4.udp_wmem_min = 65536

######## NIC / Packet Processing ########
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 5000
net.ipv4.neigh.default.gc_stale_time = 120
# ARP/neighbor cache stale-entry cleanup interval — helps NAT/relay boxes with churning peer IPs

######## Queue / Backlog ########
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_max_syn_backlog = 4096

######## Port Range ########
net.ipv4.ip_local_port_range = 10240 65535

######## Security ########
# Applies to both IPv4 and IPv6 SYN floods — no separate ipv6 toggle exists
net.ipv4.tcp_syncookies = 1

######## Routing ########
net.ipv4.ip_forward = 1
# rp_filter=0 needed for NAT/relay/multi-homed asymmetric routing.
# Set to 1 (default) on pure direct-exit single-path nodes — 0 weakens spoofing protection unnecessarily there.
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

######## IPv6 0=Enable, 1=Disable ########
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0

######## File Handles ########
fs.file-max = 500000

######## Virtual Memory ########
vm.swappiness = 10

######## Aliyun-only (classic network mode) — do NOT add to non-Aliyun boxes ########
# kernel.sysrq = 1
# net.ipv4.conf.default.arp_announce = 2
# net.ipv4.conf.lo.arp_announce = 2
# net.ipv4.conf.all.arp_announce = 2
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
    if command -v systemctl >/dev/null 2>&1; then
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
    else
        log_info "Non-systemd environment detected. Skipping persistent sysctl-reload service installation (sysctl settings are loaded natively by init system)."
    fi
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
