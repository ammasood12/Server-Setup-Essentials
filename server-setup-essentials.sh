#!/usr/bin/env bash
#
# Server Setup Essentials - Enhanced Version
# - Interactive menu with beautiful dashboard
# - Network diagnostics and optimization tools
# - Safe swap management with intelligent detection
# - Timezone configuration
# - Software installation (multi-select)
# - Comprehensive network optimization

VERSION="v2.3.1"
set -euo pipefail

#######################################
# Colors and Styles
#######################################
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly ORANGE='\033[0;33m'
readonly PURPLE='\033[0;35m'
readonly BOLD='\033[1m'
readonly UNDERLINE='\033[4m'
readonly RESET='\033[0m'

#######################################
# Configuration
#######################################
readonly SWAPFILE="/swapfile"
readonly MIN_SAFE_RAM_MB=100
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
readonly BASE_PACKAGES=("curl" "wget" "nano" "htop" "vnstat" "git" "unzip" "screen" "speedtest-cli" "traceroute" "ethtool")
# readonly NETWORK_PACKAGES=("speedtest-cli" "traceroute" "ethtool" "net-tools" "dnsutils" "iptables-persistent")
readonly NETWORK_PACKAGES=()
readonly LOG_FILE="/root/server-setup-$(date +%Y%m%d-%H%M%S).log"

#######################################
# Logging Functions
#######################################
log_info()  { echo -e "${CYAN}${BOLD}[INFO]${RESET} ${CYAN}$*${RESET}" | tee -a "$LOG_FILE"; }
log_ok()    { echo -e "${GREEN}${BOLD}[OK]${RESET} ${GREEN}$*${RESET}" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}${BOLD}[WARN]${RESET} ${YELLOW}$*${RESET}" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}${BOLD}[ERROR]${RESET} ${RED}$*${RESET}" | tee -a "$LOG_FILE"; }

#######################################
# Utility Functions
#######################################
require_root() {
    [[ $EUID -eq 0 ]] || {
        log_error "This script must be run as root"
        exit 1
    }
}

pause() {
    echo
    read -rp "Press Enter to continue..." _
}

print_separator() {
    echo -e "${BLUE}─────────────────────────────────────────────────────${RESET}"
}

print_double_separator() {
    local dummy
	# echo -e "${PURPLE}═════════════════════════════════════════════════${RESET}"
}

banner() {
    clear
    # echo -e "${BOLD}${CYAN}"
	echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║              SERVER SETUP ESSENTIALS ${VERSION}                    ║${RESET}"
    echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════╣${RESET}"
    # echo -e "${RESET}"
}

section_title() {
	banner
	print_double_separator
	display_system_status
    echo
    echo -e "${BOLD}${MAGENTA}🎯 $*${RESET}"
    # print_separator
}

sub_section() {
    echo
    echo -e "${BOLD}${CYAN}🔹 $*${RESET}"
}

#######################################
# System Information
#######################################
get_ram_mb() {
    grep MemTotal /proc/meminfo | awk '{printf "%.0f", $2/1024}'
}

get_swap_total_mb() {
    free -m | awk '/Swap:/ {print $2}'
}

get_swap_used_mb() {
    free -m | awk '/Swap:/ {print $3}'
}

get_free_ram_mb() {
    free -m | awk '/Mem:/ {print $4}'
}

get_disk_available_mb() {
    df -m / | awk 'NR==2 {print $4}'
}

get_active_swap_files() {
    swapon --show=NAME --noheadings 2>/dev/null | tr -d '[:space:]' || true
}

get_swap_file_size_mb() {
    local swap_file="$1"
    if [[ -f "$swap_file" ]]; then
        local size_bytes=$(stat -c%s "$swap_file" 2>/dev/null || echo 0)
        echo $((size_bytes / 1024 / 1024))
    else
        echo 0
    fi
}

recommended_swap_mb() {
    local ram_mb=$(get_ram_mb)
    
    if [[ $ram_mb -le 1024 ]]; then
        echo 2048
    elif [[ $ram_mb -le 2048 ]]; then
        echo 2048
    elif [[ $ram_mb -le 4096 ]]; then
        echo 1024
    else
        echo 0
    fi
}

detect_ifaces() {
	  ip -br link show | awk '{print $1}' | grep -E '^e|^en|^eth|^wlan' | paste -sd, -
}

fmt_uptime() {
  local up=$(uptime -p | sed 's/^up //')

  # Compact units
  up=$(echo "$up" | sed -E 's/weeks?/w/g; s/days?/d/g; s/hours?/h/g; s/minutes?/m/g; s/seconds?/s/g; s/,//g')

  # If uptime includes weeks or days, drop minutes and seconds
  if echo "$up" | grep -qE '[wd]'; then
	up=$(echo "$up" | sed -E 's/[0-9]+m//g; s/[0-9]+s//g')
  fi

  # Normalize spaces and remove trailing junk
  up=$(echo "$up" | tr -s ' ' | sed 's/ *$//')

  echo "$up"
}	

display_system_status() {
    # echo -e "${BOLD}${MAGENTA}🖥️  SYSTEM OVERVIEW${RESET}"
    # echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${RESET}"
    
    # Header line with time information
    printf "${MAGENTA}%-14s${RESET} %-17s ${MAGENTA}%-10s${RESET} %-20s\n" \
        "  Boot:" "$(who -b | awk '{print $3, $4}')" "Uptime:" "$(fmt_uptime)"
    
    printf "${MAGENTA}%-14s${RESET} %-17s ${MAGENTA}%-10s${RESET} %-20s\n" \
        "  Current:" "$(date '+%Y-%m-%d %H:%M')" "Timezone:" "$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")"
    
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${RESET}"

    ### System Information
    local HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    local OS=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    local KERNEL=$(uname -r)
    # local CPU=$(lscpu | grep 'Model name' | cut -d: -f2 | xargs | head -c 40)
    # local CORES=$(nproc)
	# local CPU=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | xargs)
	local CPU=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/\<Processor\>//g' | xargs)
	local CORES=$(nproc)
    local MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
    local MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    local MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
    local DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    local DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    local DISK_PERCENT=$(df -h / | awk 'NR==2 {print $5}')
    local LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local IP=$(hostname -I | awk '{print $1}')
    
    # Swap information
    local swap_total=$(get_swap_total_mb)
    local swap_used=$(get_swap_used_mb)
    local recommended_swap=$(recommended_swap_mb)
    local swap_percent=0
    if [[ $swap_total -gt 0 ]]; then
        swap_percent=$((swap_used * 100 / swap_total))
    fi

    # System details - Line 1
    printf "${YELLOW}%-14s${RESET} %-46s\n" \
        "  Hostname:" "$HOSTNAME"
    
    printf "${YELLOW}%-14s${RESET} %-46s\n" \
        "  OS:" "$OS"
    
    printf "${YELLOW}%-14s${RESET} %-46s\n" \
        "  Kernel:" "$KERNEL"
    
    printf "${YELLOW}%-14s${RESET} %-46s\n" \
        "  CPU:" "$CPU ($CORES cores)"

    # Memory and Disk - Line 2
    local mem_color=$GREEN
    local mem_status_icon="✅"
    [[ $MEM_PERCENT -gt 80 ]] && mem_status_icon="🚨"  && mem_color=$RED
    [[ $MEM_PERCENT -gt 60 ]] && mem_status_icon="⚠"  && mem_color=$YELLOW
	   
	printf "${YELLOW}%-14s${RESET} %-20s ${mem_color}%-15s${RESET}\n" \
		"  Memory:" "${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)" "$mem_status_icon $(get_free_ram_mb)MB Available"

	# Disk information
	local disk_color=$RESET
	if [[ "${DISK_PERCENT%\%}" -gt 80 ]]; then
		disk_color=$RED
	elif [[ "${DISK_PERCENT%\%}" -gt 60 ]]; then
		disk_color=$YELLOW
	fi

	# Disk type detection
	local disk_type_value=$(lsblk -d -o ROTA 2>/dev/null | awk 'NR==2 {print $1}')
	local disk_type_color disk_type_icon disk_type_text
	if [[ "$disk_type_value" == "0" ]]; then
		disk_type_color=$GREEN
		disk_type_icon="🚀"
		disk_type_text="SSD"
	elif [[ "$disk_type_value" == "1" ]]; then
		disk_type_color=$BLUE
		disk_type_icon="💾"
		disk_type_text="HDD"
	else
		disk_type_color=$YELLOW
		disk_type_icon="💿"
		disk_type_text="Unknown"
	fi

	printf "${YELLOW}%-14s${RESET} ${disk_color}%-20s${RESET} ${disk_type_color}%-15s${RESET}\n" \
		"  Disk:" "${DISK_USED} / ${DISK_TOTAL} (${DISK_PERCENT})" "${disk_type_icon} ${disk_type_text}"

# Swap information
if [[ $swap_total -eq 0 ]]; then
    printf "${YELLOW}%-14s${RESET} ${RED}%-25s${RESET} ${RED}%s${RESET}\n" \
        "  Swap:" "Not configured" "❌"
else
    local swap_color=$RESET
    [[ $swap_percent -gt 80 ]] && swap_color=$RED
    [[ $swap_percent -gt 60 ]] && swap_color=$YELLOW
    
    local swap_status="✅ Optimal "
    local swap_status_color=$GREEN
    
    [[ $swap_total -lt $recommended_swap ]] && swap_status="⚠ Small" && swap_status_color=$YELLOW
    [[ $swap_percent -gt 80 ]] && swap_status="🚨 High" && swap_status_color=$RED
    [[ $swap_percent -gt 60 ]] && [[ $swap_percent -le 80 ]] && swap_status="⚠ Medium" && swap_status_color=$YELLOW
    
    # printf "${YELLOW}%-14s${RESET} ${swap_color}%-20s${RESET} ${swap_status_color}%-15s${RESET}\n" \
        # "  Swap:" "${swap_total}MB (${swap_percent}% used)" "$swap_status"

	printf "${YELLOW}%-14s${RESET} ${swap_color}%-20s${RESET} ${swap_status_color}%-15s${RESET}\n" \
		"  Swap:" "${swap_used}MB / ${swap_total}MB (${swap_percent}%)" "$swap_status"
fi
		
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${RESET}"

    ### Network Information
    printf "${YELLOW}%-14s${RESET} %-46s\n" \
        "  IP Address:" "$IP"
    
    printf "${YELLOW}%-14s${RESET} %-46s\n" \
        "  Interfaces:" "$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -3 | tr '\n' ',' | sed 's/,$//')"
    
    printf "${YELLOW}%-14s${RESET} %-46s\n" \
        "  Load Avg:" "$LOAD"

    # BBR status
    local bbr_status=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    printf "${YELLOW}%-14s${RESET}" \
        "  Congestion:"
		if [[ "$bbr_status" == "bbr" || "$bbr_status" == "bbr2" ]]; then
			echo -e " ${GREEN}${bbr_status^^} ✅${RESET}"
		else
			echo -e " ${RED}${bbr_status} (BBR disabled) ❌${RESET}"
		fi

    # Queue discipline status
    local q_status=$(sysctl net.core.default_qdisc 2>/dev/null | awk '{print $3}')
    printf "${YELLOW}%-14s${RESET}" \
        "  QDisc:"
    if [[ "$q_status" == "fq_codel" ]]; then
        echo -e " ${GREEN}${q_status} ✅${RESET}"
    else
        echo -e " ${RED}${q_status} (fq_codel disabled) ❌${RESET}"
    fi

    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${RESET}"
    # echo
}

#######################################
# Swap Management Core
#######################################
cleanup_existing_swap() {
    log_info "Cleaning up existing swap configuration..."
    
    # Get all active swap files
    local active_swaps
    active_swaps=$(swapon --show=NAME --noheadings 2>/dev/null || true)
    
    if [[ -n "$active_swaps" ]]; then
        log_info "Disabling active swap files..."
        swapoff -a 2>/dev/null || {
            log_warn "Some swap files could not be disabled (may be in use)"
        }
    fi
    
    # Remove swap files
    local swap_files=("/swapfile" "/swapfile.new" "/swapfile2" "/tmp/temp_swap_"*)
    for file in "${swap_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing: $file"
            rm -f "$file" 2>/dev/null || log_warn "Could not remove: $file"
        fi
    done
    
    # Clean fstab
    if grep -q "swapfile" /etc/fstab 2>/dev/null; then
        log_info "Cleaning /etc/fstab..."
        sed -i '/swapfile/d' /etc/fstab 2>/dev/null || true
    fi
    
    log_ok "Cleanup completed"
}

create_swap_file() {
    local file_path="$1"
    local size_mb="$2"
    
    log_info "Creating swap file: ${file_path} (${size_mb}MB)"
    
    # Check disk space
    local available_mb=$(get_disk_available_mb)
    if [[ $available_mb -lt $size_mb ]]; then
        log_error "Insufficient disk space. Available: ${available_mb}MB, Required: ${size_mb}MB"
        return 1
    fi
    
    # Create file
    if command -v fallocate >/dev/null 2>&1; then
        if ! fallocate -l "${size_mb}M" "$file_path"; then
            log_warn "fallocate failed, using dd..."
            if ! dd if=/dev/zero of="$file_path" bs=1M count="$size_mb" status=none; then
                log_error "Failed to create swap file"
                return 1
            fi
        fi
    else
        if ! dd if=/dev/zero of="$file_path" bs=1M count="$size_mb" status=none; then
            log_error "Failed to create swap file"
            return 1
        fi
    fi
    
    # Set permissions and format
    chmod 600 "$file_path" || {
        log_error "Failed to set permissions"
        return 1
    }
    
    if ! mkswap "$file_path" >/dev/null 2>&1; then
        log_error "Failed to format swap file"
        rm -f "$file_path" 2>/dev/null || true
        return 1
    fi
    
    if ! swapon "$file_path"; then
        log_error "Failed to enable swap file"
        rm -f "$file_path" 2>/dev/null || true
        return 1
    fi
    
    log_ok "Swap file created and enabled successfully"
    return 0
}

setup_swap() {
    local target_mb="$1"
    local current_swap=$(get_swap_total_mb)
    local current_swap_file_size=$(get_swap_file_size_mb "$SWAPFILE")
    
    # Check if swap already exists and is the correct size
    if [[ -f "$SWAPFILE" ]] && [[ $current_swap_file_size -eq $target_mb ]] && [[ $current_swap -eq $target_mb ]]; then
        log_ok "Swap already configured with recommended size: ${target_mb}MB - no changes needed"
        return 0
    fi
    
    section_title "Configuring Swap: ${current_swap}MB → ${target_mb}MB"
    
    # Clean up first
    cleanup_existing_swap
    
    # Create new swap file
    if create_swap_file "$SWAPFILE" "$target_mb"; then
        # Update fstab
        echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
        log_ok "Swap configuration completed successfully"
        
        # Show final status
        echo
        free -h
        echo
        swapon --show
    else
        log_error "Failed to configure swap"
        return 1
    fi
}

#######################################
# Network Tools and Optimization
#######################################
install_network_tools() {
    sub_section "Installing Network Tools"
    log_info "Updating package lists..."
    apt update -y >/dev/null 2>&1
    
    log_info "Installing network diagnostic tools..."
    if apt install -y "${NETWORK_PACKAGES[@]}" >/dev/null 2>&1; then
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
    
    # Ping tests to major DNS providers
    sub_section "Ping Tests"
    declare -A ping_hosts=(
        ["Google DNS"]="8.8.8.8"
        ["Cloudflare"]="1.1.1.1" 
        ["AliDNS"]="223.5.5.5"
        ["Quad9"]="9.9.9.9"
    )
    
    for name in "${!ping_hosts[@]}"; do
        host="${ping_hosts[$name]}"
        echo -e "${CYAN}Pinging ${name} (${host})...${RESET}"
        if ping -c 4 -W 3 "$host" 2>/dev/null | tail -n2; then
            echo
        else
            echo -e "${RED}Failed to ping ${host}${RESET}\n"
        fi
    done
    
    # # Speed test
    # sub_section "Internet Speed Test"
    # if command -v speedtest-cli >/dev/null 2>&1; then
        # echo -e "${YELLOW}Running speed test (this may take a moment)...${RESET}"
        # speedtest-cli --simple 2>/dev/null || log_warn "Speed test failed or not available"
    # else
        # log_warn "speedtest-cli not available"
    # fi
    
    # Traceroute
    sub_section "Network Route Analysis"
    echo -e "${CYAN}Traceroute to 8.8.8.8 (first 10 hops):${RESET}"
    traceroute -m 10 8.8.8.8 2>/dev/null | head -n 15 || log_warn "Traceroute not available"
    
    # Interface information
    sub_section "Network Interface Status"
    for i in $(ls /sys/class/net | grep -v lo); do
        IP=$(ip -4 addr show $i | grep inet | awk '{print $2}' | head -n1)
        echo -e "${CYAN}Interface ${i}:${RESET} ${IP:-${RED}No IP${RESET}}"
    done
    
    echo
    log_ok "Network diagnostics completed"
}

apply_network_optimization() {
    section_title "Applying Network Optimization"
    
    log_info "Checking BBR availability..."
    
    # Check for BBR2 first
    local bbr_mode="bbr"
    if modprobe tcp_bbr2 2>/dev/null; then
        echo -e "${GREEN}BBR2 is available${RESET}"
        read -rp "Use BBR2 instead of BBR? [Y/n]: " use_bbr2
        if [[ "$use_bbr2" =~ ^[Yy]$|^$ ]]; then
            bbr_mode="bbr2"
            log_info "Using BBR2 for optimization"
        else
            log_info "Using BBR for optimization"
        fi
    else
        log_warn "BBR2 not available, using BBR"
    fi
    
    # Create backup
    local backup_file="/etc/sysctl.conf.bak-$(date +%Y%m%d-%H%M%S)"
    log_info "Creating backup: $backup_file"
    cp /etc/sysctl.conf "$backup_file" && log_ok "Backup created successfully"
    
    # Apply optimized settings
    log_info "Applying network optimization settings..."
    
    cat <<EOF > /etc/sysctl.conf
# based on sysctl-General-v03.conf file
# ============================================================
# 🌐 Network Optimization - Server Setup Essentials
# BBR/BBR2 + fq_codel + UDP/QUIC optimization
# version: v03 (based on sysctl-General-v03.conf file)
#
# Universal sysctl.conf for VPS (Generalized, Safe Everywhere)
# Works on: DigitalOcean, Vultr, Linode, AWS, Hetzner, OVH,
# Tencent, Alibaba, Oracle, RackNerd, Mikrotik CHR, etc.
# ============================================================

######## Core Network Optimization ########
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr

######## Connection Stability ########
######## TCP Stability & Handshake ########
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

######## MTU & RTT Optimization ########
######## MTU Auto-Adjustment ########
######## (Best for global routing) ########
# changed from 1 to 2
net.ipv4.tcp_mtu_probing = 2

######## TCP Buffers ########
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608

######## UDP / QUIC Optimization ########
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.udp_mem = 3145728 4194304 8388608
net.ipv4.udp_rmem_min = 32768
net.ipv4.udp_wmem_min = 32768

######## NIC / Packet Processing ########
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 5000

######## Performance & Stability ########
######## Queue / Backlog ########
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192

######## Port Range ########
net.ipv4.ip_local_port_range = 10240 65535

######## Security ########
net.ipv4.tcp_syncookies = 1

######## Routing ########
net.ipv4.ip_forward = 1
######## Anti-Route Conflicts ########
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

######## File Handles ########
fs.file-max = 1000000

# ============================================================
# END - Universal sysctl.conf
# ============================================================
EOF

    # Apply settings
    if sysctl -p >/dev/null 2>&1; then
        log_ok "Network optimization applied successfully with ${bbr_mode}"
        
        # Verify settings
        sub_section "Verification"
        echo -e "${GREEN}✓ Congestion Control:${RESET} $(sysctl -n net.ipv4.tcp_congestion_control)"
        echo -e "${GREEN}✓ Default Qdisc:${RESET} $(sysctl -n net.core.default_qdisc)"
        echo -e "${GREEN}✓ IPv4 Forwarding:${RESET} $(sysctl -n net.ipv4.ip_forward)"
        
    else
        log_error "Failed to apply network optimization"
        return 1
    fi
}

restore_network_settings() {
    section_title "Restore Network Settings"
    
    local last_backup=$(ls -t /etc/sysctl.conf.bak-* 2>/dev/null | head -n1)
    if [[ -z "$last_backup" ]]; then
        log_error "No backup found to restore"
        return 1
    fi
    
    echo -e "Last backup: ${CYAN}${last_backup}${RESET}"
    read -rp "Restore this backup? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Restoring network settings from backup..."
        if cp "$last_backup" /etc/sysctl.conf && sysctl -p >/dev/null 2>&1; then
            log_ok "Network settings restored successfully"
        else
            log_error "Failed to restore network settings"
        fi
    else
        log_warn "Restore cancelled"
    fi
}

network_system_info() {
    banner
	section_title "System & Network Overview"

    display_system_status

    echo -e "${GREEN}Active Network Interfaces (IPv4)${RESET}"
    for iface in $(ls /sys/class/net | grep -v lo); do
        local ip
        ip=$(ip -4 addr show "$iface" | awk '/inet /{print $2}' | head -n1)
        ip=${ip:-"N/A"}
        printf "  🔌 Interface: ${CYAN}%-8s${RESET}  IP: ${YELLOW}%s${RESET}\n" "$iface" "$ip"
    done
	
	echo -e "${GREEN}--------------------- BBR Availability ---------------------${RESET}"  
	sudo modprobe tcp_bbr;
	echo "tcp_bbr" | sudo tee /etc/modules-load.d/bbr.conf;
	sysctl net.ipv4.tcp_available_congestion_control | sed -E "s/(bbr2?)/\x1b[1;32m\1\x1b[0m/g"
	echo -e "${GREEN}---------------------- BBR Information ---------------------${RESET}"  
	sysctl net.ipv4.tcp_congestion_control | sed -E "s/(bbr2?)/\x1b[1;32m\1\x1b[0m/g"
	sysctl net.core.default_qdisc
	echo
  
    echo
    echo -e "${GREEN}Default Route${RESET}"
    if ip route get 8.8.8.8 &>/dev/null; then
        echo -e "  $(ip route get 8.8.8.8 | head -n1)"
    else
        echo -e "  ${YELLOW}No default route detected${RESET}"
    fi
    print_separator
}

network_tools_menu() {
    while true; do        
        section_title "Network Tools & Optimization"
        
        echo -e "${BOLD}${CYAN}Available Network Actions:${RESET}"
        echo "1) Run Network Diagnostics"
        echo "2) Apply Network Optimization (BBR/BBR2)"
        echo "3) Restore Network Settings"
        echo "4) Install Network Tools"
        echo "5) Show detailed system & network info"
        echo "0) Back to Main Menu"
        echo
        
        read -rp "Choose option [1-5]: " choice
        
        case $choice in
            1) network_diagnostics; pause ;;
            2) apply_network_optimization; pause ;;
            3) restore_network_settings; pause ;;
            4) install_network_tools; pause ;;
            5) network_system_info; pause ;;
            0) return ;;
            *) log_warn "Invalid choice"; pause ;;
        esac
    done
}

#######################################
# Swap Management Menu
#######################################
swap_management_menu() {
    while true; do
        section_title "Swap Management"
		
        echo "1) Auto-configure swap (intelligent detection)"
        echo "2) Set custom swap size"
        echo "3) Clean up all swap files and start fresh"
        echo "4) Show Current Swap Details"
        echo "0) Back to Main Menu"
        echo
        
        read -rp "Choose option [1-5]: " choice
        
        case $choice in
            1)
                local recommended=$(recommended_swap_mb)
                if [[ $recommended -gt 0 ]]; then
                    setup_swap $recommended
                else
                    log_ok "System has sufficient RAM - no swap recommended"
                fi
                pause
                ;;
            2)
                read -rp "Enter swap size in MB: " custom_size
                if [[ $custom_size =~ ^[0-9]+$ ]] && [[ $custom_size -gt 0 ]]; then
                    setup_swap $custom_size
                else
                    log_error "Invalid size entered"
                fi
                pause
                ;;
            3)
                log_info "Starting fresh swap configuration..."
                cleanup_existing_swap
                log_ok "System is now clean. Use option 1 or 2 to configure new swap."
                pause
                ;;
            4)
                echo
                echo -e "${BOLD}Swap Details:${RESET}"
                echo "free -h"
                free -h
                echo
                echo "swapon --show"
                swapon --show 2>/dev/null || log_info "No swap files active"
                echo
                pause
                ;;
            0)
                return
                ;;
            *)
                log_warn "Invalid choice"
                pause
                ;;
        esac
    done
}

#######################################
# Timezone Configuration
#######################################
configure_timezone() {
    section_title "Timezone Configuration"
    
    local current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")
    echo -e "Current timezone: ${CYAN}${current_tz}${RESET}"
    echo
    
    echo -e "${BOLD}Available timezones:${RESET}"
    echo "1) Asia/Shanghai"
    echo "2) Asia/Tokyo" 
    echo "3) Asia/Singapore"
    echo "4) UTC"
    echo "5) Europe/London"
    echo "6) America/New_York"
    echo "7) Custom input"
    echo "0) Cancel"
    echo
    
    read -rp "Choose option [1-8]: " tz_choice
    
    case $tz_choice in
        1) local new_tz="Asia/Shanghai" ;;
        2) local new_tz="Asia/Tokyo" ;;
        3) local new_tz="Asia/Singapore" ;;
        4) local new_tz="UTC" ;;
        5) local new_tz="Europe/London" ;;
        6) local new_tz="America/New_York" ;;
        7)
            read -rp "Enter timezone: " new_tz
            [[ -z "$new_tz" ]] && {
                log_warn "No timezone entered"
                return
            }
            ;;
        0)
            log_warn "Timezone change cancelled"
            return
            ;;
        *)
            log_warn "Invalid choice"
            return
            ;;
    esac
    
    if timedatectl set-timezone "$new_tz" 2>/dev/null; then
        log_ok "Timezone set to: $(timedatectl show --property=Timezone --value)"
    else
        log_error "Failed to set timezone: $new_tz"
    fi
    pause
}

#######################################
# Package Management
#######################################
install_packages() {
    section_title "Package Installation"
    
    echo -e "${BOLD}Select packages to install:${RESET}"
    echo "1) Essential tools (curl, wget, nano, htop, vnstat)"
    echo "2) Development tools (git, unzip, screen)"
    echo "3) Network tools (speedtest-cli, traceroute, ethtool, net-tools)"
    echo "4) All recommended packages"
    echo "5) Custom selection"
    echo "0) Cancel"
    echo
    
    read -rp "Choose option [1-6]: " pkg_choice
    
    case $pkg_choice in
        1)
            local packages=("curl" "wget" "nano" "htop" "vnstat")
            ;;
        2)
            local packages=("git" "unzip" "screen")
            ;;
        3)
            local packages=("${NETWORK_PACKAGES[@]}")
            ;;
        4)
            local packages=("${BASE_PACKAGES[@]}")
            ;;
        5)
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
    
    [[ ${#packages[@]} -eq 0 ]] && {
        log_warn "No packages selected"
        return
    }
    
    echo
    echo -e "Packages to install: ${CYAN}${packages[*]}${RESET}"
    read -rp "Proceed with installation? (y/N): " confirm
    
    [[ $confirm =~ ^[Yy]$ ]] || {
        log_warn "Installation cancelled"
        return
    }
    
    log_info "Updating package lists..."
    if ! apt update -y; then
        log_error "Failed to update package lists"
        return
    fi
    
    log_info "Installing packages..."
    if apt install -y "${packages[@]}"; then
        log_ok "Packages installed successfully"
    else
        log_error "Some packages failed to install"
    fi
    pause
}

#######################################
# Quick Setup
#######################################
quick_setup() {
    section_title "Quick Server Setup"
    
    echo -e "${BOLD}${GREEN}This will perform the following actions:${RESET}"
    echo "  ✅ Clean up existing swap files/partitions"
    echo "  ✅ Auto-configure optimal swap (if needed)"
    echo "  ✅ Set timezone to Asia/Shanghai" 
    echo "  ✅ Install essential packages"
    echo "  ✅ Apply network optimization (BBR/BBR2)"
    echo
    echo -e "${YELLOW}Note: This is recommended for new servers${RESET}"
    echo
    
    read -rp "Proceed with quick setup? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || {
        log_warn "Quick setup cancelled"
        return
    }
    
    # Step 1: Clean up existing swap
    sub_section "Step 1: Swap Configuration"
    log_info "Cleaning up existing swap..."
    cleanup_existing_swap
    
    local recommended=$(recommended_swap_mb)
    if [[ $recommended -gt 0 ]]; then
        log_info "Configuring ${recommended}MB swap..."
        setup_swap $recommended
    else
        log_ok "No swap configuration needed - sufficient RAM detected"
    fi
    
    # Step 2: Timezone
    sub_section "Step 2: Timezone Configuration"
    log_info "Setting timezone to $DEFAULT_TIMEZONE..."
    if timedatectl set-timezone "$DEFAULT_TIMEZONE" 2>/dev/null; then
        log_ok "Timezone set to: $(timedatectl show --property=Timezone --value)"
    else
        log_warn "Failed to set timezone"
    fi
    
    # Step 3: Packages
    sub_section "Step 3: Package Installation"
    log_info "Installing essential packages..."
    if apt update -y && apt install -y "${BASE_PACKAGES[@]}"; then
        log_ok "Packages installed successfully"
    else
        log_warn "Some packages failed to install"
    fi
    
    # Step 4: Network Optimization
    sub_section "Step 4: Network Optimization"
    apply_network_optimization
    
    echo
    print_double_separator
    log_ok "🎉 Quick setup completed successfully!"
    echo -e "${GREEN}Your server is now optimized and ready for use.${RESET}"
    print_double_separator
    echo
    pause
}

#######################################
# Main Menu
#######################################
main_menu() {
    while true; do
        section_title "🏠 MAIN MENU"
        # echo -e "${BOLD}${MAGENTA}Available Actions:${RESET}"
		# echo
		# echo -e "${BOLD}${BLUE}🏠 MAIN MENU${RESET}"
        echo -e "1) ${CYAN}System Swap Management${RESET}"
        echo -e "2) ${GREEN}Timezone Configuration${RESET}" 
        echo -e "3) ${YELLOW}Install Essential Software${RESET}"
        echo -e "4) ${BLUE}Network Diagnostics & Optimization${RESET}"
        echo -e "5) ${ORANGE}Quick Setup${RESET} (Recommended for new servers)"
        echo -e "0) ${RED}Exit${RESET}"
        echo
        
        read -rp "Choose option [1-6]: " choice
        
        case $choice in
            1) swap_management_menu ;;
            2) configure_timezone ;;
            3) install_packages ;;
            4) network_tools_menu ;;
            5) quick_setup ;;
            0)
                echo
                log_ok "Thank you for using Server Setup Essentials! 👋"
                echo -e "${GREEN}Log file: ${LOG_FILE}${RESET}"
                exit 0
                ;;
            *)
                log_warn "Invalid choice"
                pause
                ;;
        esac
    done
}

#######################################
# Main Execution
#######################################
main() {
    require_root
    trap 'echo; log_error "Script interrupted"; exit 1' INT TERM
    
    # Create log file
    echo "=== Server Setup Essentials $VERSION - $(date) ===" > "$LOG_FILE"
    
    # Check system
    if ! [[ -f /etc/debian_version ]]; then
        log_warn "This script is optimized for Debian-based systems"
        read -rp "Continue anyway? (y/N): " proceed
        [[ $proceed =~ ^[Yy]$ ]] || exit 1
    fi
    
    main_menu
}

# Run main function
main "$@"
