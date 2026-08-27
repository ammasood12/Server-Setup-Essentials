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
        echo "   3) Configure IPv6 (Enable / Disable)"
        echo "   4) Restore Network Settings"
        echo "   5) Install Network Tools"
        echo "   0) Back to Main Menu"
        echo
        
        read -rp "   Choose option [0-5]: " choice
        case $choice in
            1) network_diagnostics; pause ;;
            2) apply_network_optimization; pause ;;
            3) configure_ipv6; pause ;;
            4) restore_network_settings; pause ;;
            5) install_network_tools; pause ;;
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
    
    log_info "Configuring IPv6..."
    read -rp "Enable IPv6 on this server? [Y/n]: " enable_ipv6_choice
    local disable_ipv6_val=0
    if [[ "$enable_ipv6_choice" =~ ^[Nn] ]] || [[ "$enable_ipv6_choice" == "2" ]] || [[ "$enable_ipv6_choice" =~ ^[Dd] ]]; then
        disable_ipv6_val=1
        log_info "IPv6 will be disabled (disable_ipv6 = 1)"
    else
        disable_ipv6_val=0
        log_info "IPv6 will be enabled (disable_ipv6 = 0)"
    fi

    local sysctl_conf="/etc/sysctl.d/99-vps-optimization.conf"
    local main_sysctl="/etc/sysctl.conf"
    
    log_info "Applying network optimization settings to ${sysctl_conf}..."
    mkdir -p /etc/sysctl.d
    
    if [[ ! -f "$main_sysctl" ]]; then
        log_info "Creating dummy ${main_sysctl} file prior to backup..."
        echo "# Dummy sysctl.conf created by Server Setup Essentials on $(date '+%Y-%m-%d %H:%M:%S')" > "$main_sysctl"
    fi
    backup_file "$main_sysctl"
    echo "# /etc/sysctl.conf - Managed by Server Setup Essentials optimization on $(date '+%Y-%m-%d %H:%M:%S'). Original backed up." > "$main_sysctl"
    
    if [[ -f "$sysctl_conf" ]]; then
        backup_file "$sysctl_conf"
    fi
    
    cat <<EOF > "$sysctl_conf"
# ============================================================
# Universal sysctl.conf for VPS (Generalized, Safe Everywhere)
# version: v07.3
# Date: 2026-08-27
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
# Reduces SYN-ACK retry count from default 5 -> faster resource release under load/SYN flood
# before = 2 -> probably problematic, had problems while whatsapp call
net.ipv4.tcp_synack_retries = 5

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
# your BBR throughput fix — deleting regresses long-haul speed
# ≤512MB NAT/LXD boxes only = 2MB
# net.ipv4.tcp_limit_output_bytes = 2097152
# Normal VPS = 4MB
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
    local ipv6_disp="Enabled"
    [[ "$disable_ipv6_val" == "1" ]] && ipv6_disp="Disabled"
    echo -e "${BLUE}✓ IPv6 Status:${RESET} ${ipv6_disp} (disable_ipv6=${disable_ipv6_val})"
    install_sysctl_service
}

configure_ipv6() {
    section_title "IPv6 Configuration"
    
    local current_val=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "0")
    if [[ "$current_val" == "1" ]]; then
        echo -e "Current IPv6 status: ${RED}Disabled (disable_ipv6 = 1)${RESET}"
    else
        echo -e "Current IPv6 status: ${GREEN}Enabled (disable_ipv6 = 0)${RESET}"
    fi
    echo
    echo "   1) Enable IPv6 (disable_ipv6 = 0)"
    echo "   2) Disable IPv6 (disable_ipv6 = 1)"
    echo "   0) Cancel"
    echo
    
    read -rp "   Choose option [0-2]: " choice
    local target_val=""
    case $choice in
        1) target_val=0 ;;
        2) target_val=1 ;;
        0) return ;;
        *) log_warn "Invalid choice"; return ;;
    esac
    
    local sysctl_conf="/etc/sysctl.d/99-vps-optimization.conf"
    mkdir -p /etc/sysctl.d
    
    if [[ -f "$sysctl_conf" ]]; then
        backup_file "$sysctl_conf"
        if grep -q "net.ipv6.conf.all.disable_ipv6" "$sysctl_conf"; then
            sed -i "s/net.ipv6.conf.all.disable_ipv6 = [01]/net.ipv6.conf.all.disable_ipv6 = ${target_val}/g" "$sysctl_conf"
            sed -i "s/net.ipv6.conf.default.disable_ipv6 = [01]/net.ipv6.conf.default.disable_ipv6 = ${target_val}/g" "$sysctl_conf"
            sed -i "s/net.ipv6.conf.lo.disable_ipv6 = [01]/net.ipv6.conf.lo.disable_ipv6 = ${target_val}/g" "$sysctl_conf"
        else
            cat <<EOF >> "$sysctl_conf"

######## IPv6 0=Enable, 1=Disable ########
net.ipv6.conf.all.disable_ipv6 = ${target_val}
net.ipv6.conf.default.disable_ipv6 = ${target_val}
net.ipv6.conf.lo.disable_ipv6 = ${target_val}
EOF
        fi
    else
        local ipv6_conf="/etc/sysctl.d/99-ipv6.conf"
        backup_file "$ipv6_conf"
        cat <<EOF > "$ipv6_conf"
######## IPv6 0=Enable, 1=Disable ########
net.ipv6.conf.all.disable_ipv6 = ${target_val}
net.ipv6.conf.default.disable_ipv6 = ${target_val}
net.ipv6.conf.lo.disable_ipv6 = ${target_val}
EOF
    fi
    
    sysctl -w net.ipv6.conf.all.disable_ipv6=${target_val} >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=${target_val} >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.lo.disable_ipv6=${target_val} >/dev/null 2>&1 || true
    sysctl --ignore --system >/dev/null 2>&1 || true
    
    if [[ "$target_val" == "0" ]]; then
        log_ok "IPv6 has been enabled successfully"
    else
        log_ok "IPv6 has been disabled successfully"
    fi
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
    
    if [[ -f "$sysctl_conf" ]]; then
        rm -f "$sysctl_conf"
        log_ok "Removed optimization configuration (${sysctl_conf})"
    else
        log_info "No active 99-vps network optimization file found to remove"
    fi

    local backup_files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && backup_files+=("$file")
    done < <(ls -t /etc/sysctl.conf.bak-* /etc/sysctl.d/99-vps-optimization.conf.bak-* 2>/dev/null)

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_warn "No backups found to restore for sysctl configuration"
        sysctl --ignore --system 2>/dev/null || true
        return 0
    fi

    echo -e "${YELLOW}Available sysctl backups:${RESET}"
    local i=1
    for bfile in "${backup_files[@]}"; do
        local mtime=$(date -r "$bfile" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown time")
        echo "   $i) $bfile ($mtime)"
        ((i++))
    done
    echo "   0) Skip backup restoration"
    echo

    read -rp "Select backup to restore [0-${#backup_files[@]}]: " choice
    if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && (( choice <= ${#backup_files[@]} )); then
        local selected_backup="${backup_files[$((choice - 1))]}"
        local target_file="/etc/sysctl.conf"
        if [[ "$selected_backup" == *99-vps-optimization.conf.bak-* ]]; then
            target_file="/etc/sysctl.d/99-vps-optimization.conf"
        fi

        log_info "Restoring ${selected_backup} -> ${target_file}..."
        if cp "$selected_backup" "$target_file"; then
            log_ok "Restored ${target_file} successfully"
        else
            log_error "Failed to restore ${target_file}"
        fi
    else
        log_warn "Backup restoration skipped"
    fi

    sysctl --ignore --system 2>/dev/null || true
    log_ok "Network settings reloaded"
}
