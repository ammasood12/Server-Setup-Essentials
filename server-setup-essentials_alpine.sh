#!/usr/bin/env bash
#
# Server Setup Essentials - Alpine Linux Version
# - Interactive menu with beautiful dashboard
# - Network diagnostics and optimization tools
# - Safe swap management with intelligent detection
# - Timezone configuration
# - Software installation (multi-select)
# - Comprehensive network optimization

APP_NAME="SERVER SETUP ESSENTIALS"
VERSION="v2.5.4-alpine"
set -euo pipefail

#######################################

###### Colors and Styles ######

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly ORANGE='\033[0;33m'
readonly PURPLE='\033[0;35m'
readonly GRAY='\033[0;90m'
readonly LIGHT_GRAY='\033[0;37m'
readonly BOLD='\033[1m'
readonly UNDERLINE='\033[4m'
readonly RESET='\033[0m'

#######################################

###### Configuration ######

readonly SWAPFILE="/swapfile"
readonly MIN_SAFE_RAM_MB=100
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
readonly LOG_DIR="/root/server-setup-logs/"
mkdir -p "$LOG_DIR" 
readonly LOG_FILE="/root/server-setup-logs/server-setup.log"

#######################################

###### OS Detection ######

detect_os() {
    if [[ -f /etc/alpine-release ]]; then
        echo "alpine"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]] || [[ -f /etc/centos-release ]]; then
        echo "centos"
    elif [[ -f /etc/almalinux-release ]] || [[ -f /etc/rocky-release ]]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

detect_package_manager() {
    if command -v apk &>/dev/null; then
        echo "apk"
    elif command -v apt &>/dev/null; then
        echo "apt"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    else
        echo "unknown"
    fi
}

OS_TYPE=$(detect_os)
PKG_MANAGER=$(detect_package_manager)

# Override incompatible commands for Alpine - MOVED HERE AFTER OS_TYPE is set
if [[ "$OS_TYPE" == "alpine" ]]; then
    hostname() { command hostname "$@"; }
    alias hostname='hostname'
fi

# Package name mappings for Alpine
init_package_lists() {
    if [[ "$OS_TYPE" == "alpine" ]]; then
        # Alpine Linux packages
        BASE_PACKAGES=("curl" "wget" "nano" "htop" "vnstat" "jq" "bc")
        NETWORK_PACKAGES=("vnstat" "net-tools" "bind-tools" "iputils" "traceroute" "ethtool")
        LOG_OPTIMIZATION_PACKAGES=()  # Alpine uses busybox syslogd
        EXTRA_PACKAGES=("git" "unzip" "screen" "speedtest-cli" "coreutils")
    elif [[ "$OS_TYPE" == "debian" ]]; then
        BASE_PACKAGES=("curl" "wget" "nano" "htop" "vnstat" "jq")
        NETWORK_PACKAGES=("vnstat" "net-tools" "dnsutils" "iputils-ping" "traceroute")
        LOG_OPTIMIZATION_PACKAGES=("systemd-journal-remote" "logrotate")
        EXTRA_PACKAGES=("git" "unzip" "screen" "speedtest-cli" "bc")
    else
        BASE_PACKAGES=("curl" "wget" "nano" "htop" "vnstat" "jq" "bc")
        NETWORK_PACKAGES=("vnstat" "net-tools" "bind-utils" "iputils" "traceroute")
        LOG_OPTIMIZATION_PACKAGES=()
        EXTRA_PACKAGES=("git" "unzip" "screen" "speedtest" "epel-release")
    fi
    
    readonly BASE_PACKAGES
    readonly NETWORK_PACKAGES
    readonly LOG_OPTIMIZATION_PACKAGES
    readonly EXTRA_PACKAGES
}

init_package_lists

#######################################

###### Package Management Wrappers ######

pkg_update() {
    log_info "Updating package lists..."
    case "$PKG_MANAGER" in
        apk)
            apk update
            ;;
        apt)
            apt update -y
            ;;
        yum)
            yum check-update -y || true
            ;;
        dnf)
            dnf check-update -y || true
            ;;
    esac
}

pkg_upgrade() {
    log_info "Upgrading packages..."
    case "$PKG_MANAGER" in
        apk)
            apk upgrade
            ;;
        apt)
            DEBIAN_FRONTEND=noninteractive apt upgrade -y
            ;;
        yum|dnf)
            $PKG_MANAGER update -y
            ;;
    esac
}

pkg_install() {
    local packages=("$@")
    log_info "Installing packages: ${packages[*]}"
    
    case "$PKG_MANAGER" in
        apk)
            apk add --no-cache "${packages[@]}"
            ;;
        apt)
            apt update
            apt install -y "${packages[@]}"
            ;;
        yum|dnf)
            $PKG_MANAGER install -y "${packages[@]}"
            ;;
    esac
}

pkg_remove() {
    local packages=("$@")
    log_info "Removing packages: ${packages[*]}"
    
    case "$PKG_MANAGER" in
        apk)
            apk del "${packages[@]}"
            ;;
        apt)
            apt remove -y "${packages[@]}"
            ;;
        yum|dnf)
            $PKG_MANAGER remove -y "${packages[@]}"
            ;;
    esac
}

pkg_autoremove() {
    log_info "Cleaning up unnecessary packages..."
    case "$PKG_MANAGER" in
        apk)
            apk cache clean
            ;;
        apt)
            apt autoremove -y --purge
            ;;
        yum)
            yum autoremove -y
            ;;
        dnf)
            dnf autoremove -y
            ;;
    esac
}

pkg_search() {
    local package="$1"
    case "$PKG_MANAGER" in
        apk)
            apk search "$package"
            ;;
        apt)
            apt-cache search "$package"
            ;;
        yum|dnf)
            $PKG_MANAGER search "$package"
            ;;
    esac
}

#######################################

###### Logging Functions ######

log_info()  { 
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] ${CYAN}${BOLD}[INFO]${RESET} ${CYAN}$*${RESET}" | tee -a "$LOG_FILE" 
}
log_ok()    { 
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] ${GREEN}${BOLD}[OK]${RESET} ${GREEN}$*${RESET}" | tee -a "$LOG_FILE" 
}
log_warn()  { 
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] ${YELLOW}${BOLD}[WARN]${RESET} ${YELLOW}$*${RESET}" | tee -a "$LOG_FILE" 
}
log_error() { 
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] ${RED}${BOLD}[ERROR]${RESET} ${RED}$*${RESET}" | tee -a "$LOG_FILE" 
}

feature_unavailable() {
    log_error "This feature is not available in Alpine Linux"
    echo -e "${RED}${BOLD}❌ Feature Unavailable${RESET}"
    echo -e "${YELLOW}Alpine Linux uses different tools. This feature requires:${RESET}"
    echo -e "  • systemd (Alpine uses OpenRC)"
    echo -e "  • Different package naming conventions"
    echo -e "  • Alternative configuration paths"
    pause
}

#######################################

###### Utility Functions ######

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

banner() {
    clear
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║              SERVER SETUP ESSENTIALS ${VERSION}                    ║${RESET}"
    echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════╣${RESET}"
}

section_title() {
    banner
    display_system_status
    echo
    echo -e "${BOLD}${MAGENTA}🎯 $*${RESET}"
}

sub_section() {
    echo
    echo -e "${BOLD}${CYAN}🔹 $*${RESET}"
}

#######################################

###### System Information Functions ######

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
    up=$(echo "$up" | sed -E 's/weeks?/w/g; s/days?/d/g; s/hours?/h/g; s/minutes?/m/g; s/seconds?/s/g; s/,//g')
    
    if echo "$up" | grep -qE '[wd]'; then
        up=$(echo "$up" | sed -E 's/[0-9]+m//g; s/[0-9]+s//g')
    fi
    
    echo "$up" | tr -s ' ' | sed 's/ *$//'
}

get_load_status() {
    local load_value=$1 cores=$2
    if (( $(echo "$load_value > $cores * 2" | bc -l 2>/dev/null) )); then
        echo -e "${RED}❌ High Load$RESET"
    elif (( $(echo "$load_value > $cores" | bc -l 2>/dev/null) )); then
        echo -e "${YELLOW}⚠️ Medium Load$RESET"
    else
        echo -e "${GREEN}✅ Optimal Load$RESET"
    fi
}

get_mem_status() {
    local percent=$1 free_mb=$2
    local status_icon="✅" color=$GREEN
    
    [[ $percent -gt 80 ]] && { status_icon="🚨"; color=$RED; }
    [[ $percent -gt 60 ]] && { status_icon="⚠"; color=$YELLOW; }
    
    echo -e "$color$status_icon ${free_mb}MB Available$RESET"
}

get_disk_status() {
    local percent=$1
    local color=$RESET
    [[ "${percent%\%}" -gt 80 ]] && color=$RED
    [[ "${percent%\%}" -gt 60 ]] && color=$YELLOW
    echo "$color"
}

get_disk_type() {
    local disk_type_value=$(lsblk -d -o ROTA 2>/dev/null | awk 'NR==2 {print $1}')
    case "$disk_type_value" in
        "0") echo -e "${GREEN}🚀 SSD$RESET" ;;
        "1") echo -e "${BLUE}💾 HDD$RESET" ;;
        *) echo -e "${YELLOW}💿 Unknown$RESET" ;;
    esac
}

get_swap_status() {
    local total=$1 used=$2 percent=$3 recommended=$4
    if [[ $total -eq 0 ]]; then
        echo "$RED❌ Not configured$RESET"
    else
        local color=$GREEN status="✅ Optimal usage"
        [[ $percent -gt 80 ]] && { color=$RED; status="🚨 High usage"; }
        [[ $percent -gt 60 ]] && [[ $percent -le 80 ]] && { color=$YELLOW; status="⚠ Medium usage"; }
        [[ $total -lt $recommended ]] && { color=$GREEN; status="✅ Small usage"; }
        echo -e "$color$status$RESET"
    fi
}

get_os_info() {
    if [[ "$OS_TYPE" == "alpine" ]]; then
        cat /etc/alpine-release 2>/dev/null || echo "Alpine Linux"
    elif [[ "$OS_TYPE" == "debian" ]]; then
        lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'
    else
        cat /etc/redhat-release 2>/dev/null || cat /etc/centos-release 2>/dev/null || \
        cat /etc/almalinux-release 2>/dev/null || cat /etc/rocky-release 2>/dev/null || \
        grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'
    fi
}

#######################################

###### Display System Status ######

display_system_status() {
    printf "${MAGENTA}%-14s${RESET} %-17s ${MAGENTA}%-10s${RESET} %-20s\n" \
        "  Boot:" "$(uptime -s | cut -d' ' -f1,2)" "Uptime:" "$(fmt_uptime)"
    
    printf "${MAGENTA}%-14s${RESET} %-17s ${MAGENTA}%-10s${RESET} %-20s\n" \
        "  Current:" "$(date '+%Y-%m-%d %H:%M')" "Timezone:" "$(date +%Z 2>/dev/null || echo "Unknown")"
    
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${RESET}"
    
    display_bandwidth_info
    display_traffic_info
    
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${RESET}"
    
    display_system_info
    display_resource_usage
    display_network_info
    
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${RESET}"
}

display_bandwidth_info() {
    local INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -2 | tr '\n' ',' | sed 's/,$//')
    
    if command -v vnstat >/dev/null 2>&1; then
        local VNSTAT_VERSION=$(vnstat --version 2>/dev/null | awk '{print $2}')
        local vnstat_output=$(vnstat --oneline 2>/dev/null)
        
        if [[ -n "$vnstat_output" ]]; then
            local vnstat_month=$(echo "$vnstat_output" | awk -F';' '{print $8}')
            local vnstat_rx=$(echo "$vnstat_output" | awk -F';' '{print $9}')
            local vnstat_tx=$(echo "$vnstat_output" | awk -F';' '{print $10}')
            local vnstat_total=$(echo "$vnstat_output" | awk -F';' '{print $11}')
            
            printf "${YELLOW}%-14s${RESET} %-9s %-9s ${GREEN}%-10s${RESET} ${CYAN}%-10s${RESET} ${MAGENTA}%-10s${RESET}\n" \
                "" "iface" "Duration" "RX/UL" "TX/DL" "Total"
            printf "${YELLOW}%-14s${RESET} %-9s %-9s %-10s %-10s %-10s\n" \
                "  vnStat $VNSTAT_VERSION" "$INTERFACES" "$vnstat_month" "$vnstat_rx" "$vnstat_tx" "$vnstat_total"
        else
            printf "${YELLOW}%-14s${RESET} ${RED}%-46s${RESET}\n" \
                "  Bandwidth:" "Collecting data..."
        fi
    else
        printf "${YELLOW}%-14s${RESET} ${RED}%-46s${RESET}\n" \
            "  Bandwidth:" "vnStat not installed"
    fi
}

display_traffic_info() {
    local BOOT_DAYS=$(echo $(($(date +%s) - $(date -d "$(who -b | awk '{print $3, $4}')" +%s))) | awk '{printf "%d days\n", $1/86400}')
    
    ip -s link | awk -v boot_days="$BOOT_DAYS" '
    function human(x){
        split("B KB MB GB TB",u);
        i=1;
        while(x>=1024&&i<5){
            x/=1024;
            i++
        }
        return sprintf("%.2f %s",x,u[i])
    } 
    /^[0-9]+:/{
        iface=$2;
        gsub(":","",iface)
    } 
    /RX:/{
        getline;
        rx=$1
    } 
    /TX:/{
        getline;
        tx=$1;
        if(iface != "lo") {
            total=rx+tx;
            printf "  %-12s %-9s %-9s %-10s %-10s %-10s\n", "Server", iface, boot_days, human(rx), human(tx), human(total)
        }
    }' | head -3
}

display_system_info() {
    local HOSTNAME=$(cat /etc/hostname 2>/dev/null || hostname)
    local OS=$(get_os_info)
    local KERNEL=$(uname -r)
    local CPU=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/\<Processor\>//g' | xargs)
    local CORES=$(nproc)
    
    printf "${YELLOW}%-14s${RESET} %-46s\n" "  Hostname:" "$HOSTNAME"
    printf "${YELLOW}%-14s${RESET} %-22s ${GRAY}%s${RESET}\n" "  OS:" "$OS" "(Kernel: $KERNEL)" 
    printf "${YELLOW}%-14s${RESET} %-46s\n" "  CPU:" "$CPU ($CORES cores)"
}

display_resource_usage() {
    local MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
    local MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    local MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
    local DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    local DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    local DISK_PERCENT=$(df -h / | awk 'NR==2 {print $5}')
    local LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local load1=$(echo "$LOAD" | awk -F', ' '{print $1}' | sed 's/,//g')
    local CORES=$(nproc)
    	
    local disk_color=$(get_disk_status "$DISK_PERCENT")
    printf "${YELLOW}%-14s${RESET} ${disk_color}%-22s${RESET} %s\n" "  Disk:" \
        "${DISK_USED} / ${DISK_TOTAL} (${DISK_PERCENT})" "$(get_disk_type)"
		
    printf "${YELLOW}%-14s${RESET} %-22s %s\n" "  Load Avg:" "$LOAD" "$(get_load_status "$load1" "$CORES")"
    
    printf "${YELLOW}%-14s${RESET} %-22s %s\n" "  Memory:" "${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)" \
        "$(get_mem_status "$MEM_PERCENT" "$(get_free_ram_mb)")"    
    
    local swap_total=$(get_swap_total_mb)
    local swap_used=$(get_swap_used_mb)
    local swap_percent=0
    [[ $swap_total -gt 0 ]] && swap_percent=$((swap_used * 100 / swap_total))
    local recommended_swap=$(recommended_swap_mb)
    
    if [[ $swap_total -eq 0 ]]; then
        printf "${YELLOW}%-14s${RESET} ${RED}%-22s${RESET} ${RED}%s${RESET}\n" "  Swap:" "Not configured" "❌"
    else
        local swap_color=$RESET
        [[ $swap_percent -gt 80 ]] && swap_color=$RED
        [[ $swap_percent -gt 60 ]] && swap_color=$YELLOW
        printf "${YELLOW}%-14s${RESET} ${swap_color}%-22s${RESET} %s\n" "  Swap:" \
            "${swap_used}MB / ${swap_total}MB (${swap_percent}%)" "$(get_swap_status "$swap_total" "$swap_used" "$swap_percent" "$recommended_swap")"
    fi
}

display_network_info() {
    local IPV4=$(hostname -i 2>/dev/null | awk '{print $1}')
    local IPV4_onlineIP="$(curl -4 -s --max-time 3 https://ifconfig.me 2>/dev/null || echo "")"
    local IPV6=$(ip -6 addr show scope global 2>/dev/null | grep inet6 | head -1 | awk '{print $2}' | cut -d'/' -f1)
    local bbr_status=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' || echo "not set")
local q_status=$(sysctl net.core.default_qdisc 2>/dev/null | awk '{print $3}' || echo "not set")
    
    local ipv6_status=$([ -n "$IPV6" ] && echo -e "${GREEN}IPv6 ✓${RESET}" || echo -e "${RED}IPv6 ✗${RESET}")
    local bbr_display=$([ "$bbr_status" == "bbr" ] || [ "$bbr_status" == "bbr2" ] && echo -e "${GREEN}${bbr_status^^} ✓${RESET}" || echo -e "${RED}${bbr_status} ✗${RESET}")
    local qdisc_display=$([ "$q_status" == "fq_codel" ] && echo -e "${GREEN}${q_status^^} ✓${RESET}" || echo -e "${RED}${q_status} ✗${RESET}")
        
    printf "${YELLOW}%-14s${RESET} %-22s %s\n" "  Network:" "$IPV4" "$bbr_display + $qdisc_display"
    printf "${YELLOW}%-14s${RESET} %-22s %s\n" "  Internet:" "$IPV4_onlineIP" "$ipv6_status"
}

#######################################

###### Swap Management Core ######

swap_management_menu() {
    while true; do
        section_title "Swap Management"
        echo
        echo "   1) Auto-configure swap (intelligent detection)"
        echo "   2) Set custom swap size"
        echo "   3) Clean up all swap files and start fresh"
        echo "   4) Show Current Swap Details"
        echo "   0) Back to Main Menu"
        echo
        
        read -rp "   Choose option [0-4]: " choice
        case $choice in
            1)
                local recommended=$(recommended_swap_mb)
                [[ $recommended -gt 0 ]] && setup_swap $recommended || log_ok "System has sufficient RAM - no swap recommended"
                pause
                ;;
            2)
                read -rp "Enter swap size in MB: " custom_size
                [[ $custom_size =~ ^[0-9]+$ ]] && [[ $custom_size -gt 0 ]] && setup_swap $custom_size || log_error "Invalid size entered"
                pause
                ;;
            3)
                log_info "Starting fresh swap configuration..."
                cleanup_existing_swap
                log_ok "System is now clean. Use option 1 or 2 to configure new swap."
                pause
                ;;
            4)
                echo -e "${BOLD}Swap Details:${RESET}"
                free -h; echo; swapon --show 2>/dev/null || log_info "No swap files active"; echo
                pause
                ;;
            0) return ;;
            *) log_warn "Invalid choice"; pause ;;
        esac
    done
}

cleanup_existing_swap() {
    log_info "Cleaning up existing swap configuration..."
    
    local active_swaps=$(swapon --show=NAME --noheadings 2>/dev/null || true)
    if [[ -n "$active_swaps" ]]; then
        log_info "Disabling active swap files..."
        swapoff -a 2>/dev/null || log_warn "Some swap files could not be disabled (may be in use)"
    fi
    
    local swap_files=("/swapfile" "/swapfile.new" "/swapfile2" "/tmp/temp_swap_"*)
    for file in "${swap_files[@]}"; do
        [[ -f "$file" ]] && { log_info "Removing: $file"; rm -f "$file" 2>/dev/null || log_warn "Could not remove: $file"; }
    done
    
    if [[ "$OS_TYPE" == "alpine" ]]; then
        grep -q "swapfile" /etc/fstab 2>/dev/null && {
            log_info "Cleaning /etc/fstab..."
            sed -i '/swapfile/d' /etc/fstab 2>/dev/null || true
        }
    else
        grep -q "swapfile" /etc/fstab 2>/dev/null && {
            log_info "Cleaning /etc/fstab..."
            sed -i '/swapfile/d' /etc/fstab 2>/dev/null || true
        }
    fi
    
    log_ok "Cleanup completed"
}

create_swap_file() {
    local file_path="$1" size_mb="$2"
    local available_mb=$(get_disk_available_mb)
    
    [[ $available_mb -lt $size_mb ]] && {
        log_error "Insufficient disk space. Available: ${available_mb}MB, Required: ${size_mb}MB"
        return 1
    }
    
    log_info "Creating swap file: ${file_path} (${size_mb}MB)"
    
    if command -v fallocate >/dev/null 2>&1; then
        fallocate -l "${size_mb}M" "$file_path" || {
            log_warn "fallocate failed, using dd..."
            dd if=/dev/zero of="$file_path" bs=1M count="$size_mb" status=none || {
                log_error "Failed to create swap file"; return 1; }
        }
    else
        dd if=/dev/zero of="$file_path" bs=1M count="$size_mb" status=none || {
            log_error "Failed to create swap file"; return 1; }
    fi
    
    chmod 600 "$file_path" || { log_error "Failed to set permissions"; return 1; }
    mkswap "$file_path" >/dev/null 2>&1 || { log_error "Failed to format swap file"; rm -f "$file_path"; return 1; }
    swapon "$file_path" || { log_error "Failed to enable swap file"; rm -f "$file_path"; return 1; }
    
    log_ok "Swap file created and enabled successfully"
    return 0
}

setup_swap() {
    local target_mb="$1"
    local current_swap=$(get_swap_total_mb)
    local current_swap_file_size=$(get_swap_file_size_mb "$SWAPFILE")
    
    if [[ -f "$SWAPFILE" ]] && [[ $current_swap_file_size -eq $target_mb ]] && [[ $current_swap -eq $target_mb ]]; then
        log_ok "Swap already configured with recommended size: ${target_mb}MB - no changes needed"
        return 0
    fi
    
    section_title "Configuring Swap: ${current_swap}MB → ${target_mb}MB"
    cleanup_existing_swap
    
    if create_swap_file "$SWAPFILE" "$target_mb"; then
        echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
        log_ok "Swap configuration completed successfully"
        echo; free -h; echo; swapon --show
    else
        log_error "Failed to configure swap"
        return 1
    fi
}

###############################################

###### Network Tools and Optimization ######

network_tools_menu() {
    while true; do        
        section_title "Network Tools & Optimization"
        echo "   (Modify sysctl.conf)"
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
    
    log_info "Updating package lists..."
    pkg_update
    
    log_info "Installing network diagnostic tools..."
    if pkg_install "${NETWORK_PACKAGES[@]}"; then
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
    if command -v traceroute >/dev/null 2>&1; then
        echo -e "${CYAN}Traceroute to 8.8.8.8 (first 10 hops):${RESET}"
        traceroute -m 10 8.8.8.8 2>/dev/null | head -n 15 || log_warn "Traceroute failed"
    else
        echo -e "${RED}Traceroute not available in Alpine${RESET}"
    fi
    
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
    
    # Check for BBR support in Alpine kernel
    if modprobe tcp_bbr 2>/dev/null; then
        echo -e "${GREEN}BBR is available${RESET}"
    elif modprobe tcp_bbr2 2>/dev/null; then
        echo -e "${GREEN}BBR2 is available${RESET}"
        read -rp "Use BBR2 instead of BBR? [Y/n]: " use_bbr2
        [[ "$use_bbr2" =~ ^[Yy]$|^$ ]] && bbr_mode="bbr2"
    else
        log_warn "BBR not available in Alpine kernel"
        echo -e "${YELLOW}Alpine Linux may need a custom kernel for BBR support${RESET}"
        read -rp "Continue with optimization anyway? [y/N]: " continue_anyway
        [[ "$continue_anyway" =~ ^[Yy]$ ]] || return
    fi
    
    local backup_file="/etc/sysctl.conf.bak-$(date +%Y%m%d-%H%M%S)"
    log_info "Creating backup: $backup_file"
    cp /etc/sysctl.conf "$backup_file" 2>/dev/null && log_ok "Backup created successfully" || log_warn "No existing sysctl.conf to backup"
    
    log_info "Applying network optimization settings..."
    cat <<EOF > /etc/sysctl.conf
# ============================================================
# 🌐 Network Optimization - Server Setup Essentials
# BBR/BBR2 + fq_codel + UDP/QUIC optimization
# version: v03 (Alpine Linux Compatible)
#
# Universal sysctl.conf for VPS
# ============================================================

######## Core Network Optimization ########
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = $bbr_mode

######## Connection Stability ########
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

######## MTU & RTT Optimization ########
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
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192

######## Port Range ########
net.ipv4.ip_local_port_range = 10240 65535

######## Security ########
net.ipv4.tcp_syncookies = 1

######## Routing ########
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

######## Disable IPv6 ########
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

######## File Handles ########
fs.file-max = 1000000

# ============================================================
# END - Universal sysctl.conf
# ============================================================
EOF

    if sysctl -p >/dev/null 2>&1; then
        log_ok "Network optimization applied successfully with ${bbr_mode}"
        sub_section "Verification"
        echo -e "${GREEN}✓ Congestion Control:${RESET} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")"
        echo -e "${GREEN}✓ Default Qdisc:${RESET} $(sysctl -n net.core.default_qdisc 2>/dev/null || echo "N/A")"
        echo -e "${GREEN}✓ IPv4 Forwarding:${RESET} $(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "N/A")"
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

#######################################

###### System Logs Optimization ######

logs_optimization_menu() {
    section_title "System Logs Optimization"
    
    if [[ "$OS_TYPE" == "alpine" ]]; then
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
    
    echo "   (Modify journald.conf)"
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
    if [[ "$OS_TYPE" == "alpine" ]]; then
        feature_unavailable
        return
    fi
    
    section_title "System Logs Optimization"
    
    echo -e "${BOLD}${GREEN}This will optimize system journal logs and rotation:${RESET}"
    echo "  ✅ Configure journald limits (SystemMaxUse=100M, RuntimeMaxUse=50M)"
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
    if pkg_update && pkg_install "${LOG_OPTIMIZATION_PACKAGES[@]}"; then
        log_ok "Log optimization tools installed successfully"
    else
        log_error "Failed to install some packages"
        return 1
    fi
    
    sub_section "Step 2: Configuring Journald Limits"
    log_info "Configuring journald system limits..."
    
    local journald_conf="/etc/systemd/journald.conf"
    local journald_backup="${journald_conf}.bak-$(date +%Y%m%d-%H%M%S)"
    
    if [[ -f "$journald_conf" ]]; then
        cp "$journald_conf" "$journald_backup" && log_ok "Backup created: $journald_backup"
    fi
    
    cat <<EOF > "$journald_conf"
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
    
    journalctl --vacuum-size=300M 2>/dev/null && log_ok "Journal logs vacuumed to 300MB limit" || log_warn "Failed to vacuum journal by size"
    journalctl --vacuum-time=15days 2>/dev/null && log_ok "Journal logs older than 15 days removed" || log_warn "Failed to vacuum journal by time"
    
    sub_section "Step 5: Verification"
    log_info "Current journal usage:"
    journalctl --disk-usage
    
    echo
    log_ok "🎉 System logs optimization completed successfully!"
    echo -e "${GREEN}Journal logs are now optimized with proper limits and cleanup.${RESET}"
}

set_custom_journal_limits() {
    if [[ "$OS_TYPE" == "alpine" ]]; then
        feature_unavailable
        return
    fi
    
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
    
    local journald_conf="/etc/systemd/journald.conf"
    local backup="${journald_conf}.bak-$(date +%Y%m%d-%H%M%S)"
    [[ -f "$journald_conf" ]] && cp "$journald_conf" "$backup"
    
    grep -v -E "^(SystemMaxUse|RuntimeMaxUse|SystemMaxFileSize|MaxRetentionSec)=" "$journald_conf" > "${journald_conf}.tmp" 2>/dev/null || true
    
    cat <<EOF >> "${journald_conf}.tmp"
SystemMaxUse=${system_max}
RuntimeMaxUse=${runtime_max}
SystemMaxFileSize=${file_size}
MaxRetentionSec=${retention}
EOF

    mv "${journald_conf}.tmp" "$journald_conf"
    systemctl restart systemd-journald
    
    log_ok "Custom journal limits applied successfully"
}

vacuum_logs_only() {
    if [[ "$OS_TYPE" == "alpine" ]]; then
        feature_unavailable
        return
    fi
    
    section_title "Vacuum System Logs"
    
    echo -e "${GREEN}Current Journal Disk Usage:${RESET}"
    local before_usage=$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]\+[A-Z]' | head -1)
    local before_size=$(du -sh /var/log/journal 2>/dev/null | awk '{print $1}')
    
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
                log_ok "Logs vacuumed to 50MB limit"
            else
                log_error "Failed to vacuum logs"
            fi
            ;;
        2)
            echo -e "\n${CYAN}Vacuuming logs older than 7 days...${RESET}"
            if journalctl --vacuum-time=7days 2>/dev/null; then
                log_ok "Logs older than 7 days removed"
            else
                log_error "Failed to vacuum logs"
            fi
            ;;
        3)
            echo -e "\n${CYAN}Vacuuming logs by size and time...${RESET}"
            if journalctl --vacuum-size=50M --vacuum-time=7days 2>/dev/null; then
                log_ok "Logs vacuumed by both size and time"
            else
                log_error "Failed to vacuum logs"
            fi
            ;;
        4)
            echo -e "\n${CYAN}Custom Vacuum Parameters:${RESET}"
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
                log_ok "Custom vacuum completed successfully"
            else
                log_error "Failed to execute custom vacuum"
            fi
            ;;
        0)
            log_warn "Vacuum operation cancelled"
            ;;
        *)
            log_warn "Invalid choice"
            ;;
    esac
}

view_log_usage() {
    if [[ "$OS_TYPE" == "alpine" ]]; then
        echo -e "${GREEN}Alpine Linux Log Information:${RESET}"
        echo -e "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"
        
        if [[ -d /var/log ]]; then
            echo -e "${YELLOW}Log directory size:${RESET}"
            du -sh /var/log 2>/dev/null
            echo
            echo -e "${YELLOW}Largest log files:${RESET}"
            find /var/log -type f -exec du -h {} \; 2>/dev/null | sort -hr | head -10
        fi
        
        echo
        echo -e "${YELLOW}Syslog configuration:${RESET}"
        if [[ -f /etc/conf.d/syslog ]]; then
            cat /etc/conf.d/syslog 2>/dev/null | grep -v "^#" | grep -v "^$"
        else
            echo "No custom syslog configuration"
        fi
        
        echo
        echo -e "${YELLOW}Log rotation status:${RESET}"
        if command -v logrotate >/dev/null 2>&1; then
            logrotate --version 2>/dev/null | head -1
        else
            echo "logrotate not installed"
        fi
    else
        echo -e "${GREEN}Journal Disk Usage:${RESET}"
        journalctl --disk-usage 2>/dev/null || echo "journalctl not available"
        
        echo -e "\n${GREEN}Current Journal Configuration:${RESET}"
        grep -E "^(SystemMaxUse|RuntimeMaxUse|SystemMaxFileSize|MaxRetentionSec)=" /etc/systemd/journald.conf 2>/dev/null || echo "Using default settings"
    fi
}

remove_log_optimization() {
    if [[ "$OS_TYPE" == "alpine" ]]; then
        feature_unavailable
        return
    fi
    
    section_title "Remove Log Optimization"
    
    read -rp "Remove all log optimization settings? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || {
        log_warn "Operation cancelled"
        return
    }
    
    local journald_conf="/etc/systemd/journald.conf"
    if [[ -f "${journald_conf}.original" ]]; then
        cp "${journald_conf}.original" "$journald_conf"
        log_ok "Original journald configuration restored"
    else
        log_warn "No original backup found, keeping current configuration"
    fi
    
    systemctl restart systemd-journald
    log_ok "Journald service restarted with default settings"
}

#######################################

###### Timezone Configuration ######

configure_timezone() {
    section_title "Timezone Configuration"

    local current_tz
    current_tz=$(date +%Z 2>/dev/null || echo "Unknown")
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

    case "$tz_choice" in
        1) new_tz="etc/UTC" ;;
        2) new_tz="Etc/GMT+5" ;;
        3) new_tz="Etc/GMT+16" ;;
        4) new_tz="Asia/Shanghai" ;;
        5) new_tz="America/New_York" ;;
        6) new_tz="UTC" ;;
        7) read -rp "Enter custom timezone (e.g., Europe/Berlin): " new_tz
            if [[ -z "$new_tz" ]]; then
                log_warn "No timezone entered. Cancelled."
                return
            fi ;;
        0) log_warn "Timezone change cancelled."
            return ;;
        *) log_warn "Invalid choice."
            return ;;
    esac

    if [[ "$OS_TYPE" == "alpine" ]]; then
        if cp /usr/share/zoneinfo/$new_tz /etc/localtime 2>/dev/null; then
            echo "$new_tz" > /etc/timezone
            log_ok "Timezone successfully set to: ${CYAN}${new_tz}${RESET}"
        else
            log_error "Failed to set timezone: $new_tz"
        fi
    else
        if timedatectl set-timezone "$new_tz" 2>/dev/null; then
            log_ok "Timezone:" "$(date +%Z 2>/dev/null || echo "Unknown")"
        else
            log_error "Failed to set timezone: $new_tz"
        fi
    fi

    pause
}

#######################################

###### Server Hostname Configuration ######

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
        echo "$new_hostname" > /etc/hostname
        
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

###############################################

###### Package Management ######

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
            if [[ "$OS_TYPE" == "alpine" ]]; then
                packages=("speedtest-cli" "traceroute" "net-tools" "bind-tools" "ethtool")
            elif [[ "$OS_TYPE" == "debian" ]]; then
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
            packages=("${BASE_PACKAGES[@]}")
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

###############################################

###### System Update Function ######

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
    
    if [[ "$OS_TYPE" == "alpine" ]]; then
        log_info "Checking if reboot is needed..."
        if [[ -f /var/run/reboot-required ]]; then
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

####################################################

###### Combined Benchmark & Media Check Menu ######

benchmark_menu() {
    while true; do
        section_title "Benchmark & Media Checking Tools"
        echo -e "${CYAN}Collection of useful online benchmarking and testing tools:${RESET}"
        echo
        echo -e "   ── ${YELLOW}Full Benchmark Tools${RESET} ──────────────────────────────"        
        
        echo "   1) YABS (Yet Another Benchmark Script)"
        echo "   2) Speedtest (from Ookla)"
        echo "   3) Bench.sh (Full System Benchmark)"
        echo "   4) spiritLHLS/ecs Full Check (bash.spiritlhl.net/ecs)"
        
        echo -e "   ── ${YELLOW}Media Checking Tools${RESET} ─────────────────────────"
        
        echo "   5) BackBone Check 1 (ludashi2020/backtrace)"
        echo "   6) BackBone Check 2 (route.f2k.pub)"
        
        echo "   7) Check Media 1 (Check.Unlock.Media)"
        echo "   8) Check Media 2 (Media.Check.Place)"
        echo "   9) Check Media Quality (Check.Place)"
        echo -e "   ─────────────────────────────────────────────────"        
        echo "   10) Check System Detailed Information"
        echo
        echo "   0) Back to Main Menu"
        echo
        
        read -rp "   Choose option [0-8]: " choice
        case $choice in            
            1) run_yabs; pause ;;
            2) run_speedtest; pause ;;
            3) run_generic_command \
                "Bench.sh" \
                "interactive" \
                "wget -qO- bench.sh | bash" \
                "Classic interactive system benchmark" \
                "bench.sh";
                pause ;;
            4)  run_generic_command \
                "spiritLHLS/ecs Check" \
                "exec" \
                "bash <(wget -qO- bash.spiritlhl.net/ecs) -en" \
                "VPS Fusion Monster Server Test Script" \
                "bash.spiritlhl.net/ecs"; pause ;;
            5) run_generic_command \
                "BackBone Check 1" \
                "interactive" \
                "curl -sSf https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh | bash" \
                "Interactive backbone connectivity check script" \
                "https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh";
                pause ;;
            6) run_generic_command \
                "BackBone Check 2" \
                "interactive" \
                "wget -q route.f2k.pub -O route && bash route && rm -f route" \
                "Interactive backbone connectivity check script" \
                "route.f2k.pub";
                pause ;;
            7) run_generic_command \
                "Media Check 1 (unlock.media)" \
                "interactive" \
                "bash <(curl -L -s check.unlock.media) -E en" \
                "Interactive media unlock status check" \
                "check.unlock.media";
                pause ;;            
            8) run_generic_command \
                "Media Check 2 (Media.Check.Place)" \
                "interactive" \
                "bash <(curl -sL Media.Check.Place) -E en" \
                "Interactive media unlock status check" \
                "Media.Check.Place";
                pause ;;        
            9) run_generic_command \
                "Media Quality Check" \
                "interactive" \
                "bash <(curl -Ls Check.Place) -E" \
                "Interactive media streaming quality check" \
                "Check.Place";
                pause ;;            
            10) run_generic_command \
                "Check System Detailed Information" \
                "direct" \
                "wget -qO - https://raw.github.com/tdulcet/Linux-System-Information/master/info.sh | bash -s" \
                "Non-interactive system information check script" \
                "https://raw.github.com/tdulcet/Linux-System-Information/master/info.sh";
                pause ;;
            0) return ;;
            *) log_warn "Invalid choice"; pause ;;
        esac
    done
}

###### Generic Command Runner Function ######

run_generic_command() {
    local command_name="$1"
    local command_type="$2"  # "direct", "pipe", "eval", "interactive"
    local command="$3"
    local description="$4"
    local source_info="$5"
    
    section_title "$command_name"
    
    if [[ -n "$description" ]]; then
        echo -e "${YELLOW}Note: $description${RESET}"
    fi
    
    if [[ -n "$source_info" ]]; then
        echo -e "${YELLOW}Source: $source_info${RESET}"
    fi
    
    echo -e "${YELLOW}Command: $command${RESET}"
    echo
    
    if [[ "$command_type" == "exec" ]]; then
        echo -e "${RED}Note: This will exit this menu and run the external script directly.${RESET}"        
    fi
    
    read -rp "   Are you sure you want to continue? (y/N): " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { log_warn "Cancelled"; return 1; }
    
    log_info "Running $command_name..."
    echo -e "${CYAN}Executing: $command${RESET}"
    echo
    
    local exit_code=0
    
    case "$command_type" in
        "direct"|"pipe"|"eval")
            eval "$command"
            exit_code=$?
            ;;
        "interactive")
            log_info "Running interactive command. Use Ctrl+C to exit."
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"
            eval "$command"
            exit_code=$?
            echo -e "${CYAN}════════════════════════════════════════════════════════════════════${RESET}"
            ;;
        "exec")
            log_info "Exiting menu and executing: $command"
            exec bash -c "$command"
            ;;
        *)
            log_error "Unknown command type: $command_type"
            return 1
            ;;
    esac
    
    if [[ $exit_code -eq 0 ]] || [[ $exit_code -eq 130 ]] || [[ $exit_code -eq 143 ]]; then
        log_ok "$command_name completed"
        return 0
    else
        log_error "$command_name failed (exit code: $exit_code)"
        return $exit_code
    fi
}

###### Benchmark Functions using Generic Runner ######

run_yabs() {
    section_title "Running YABS (Yet Another Benchmark Script)"
    
    echo "   Select benchmark options:"
    echo "   1) Full YABS (default)"
    echo "   2) YABS without Geekbench"
    echo "   3) YABS without disk test"
    echo "   4) Custom flags"
    echo "   0) Cancel"
    echo
    
    read -rp "   Choose option [0-4]: " yabs_choice
    
    [[ "$yabs_choice" == "0" ]] && { log_warn "Cancelled"; return 1; }
    
    local yabs_flags=""
    case $yabs_choice in
        1) yabs_flags="" ;;
        2) yabs_flags="-i" ;;
        3) yabs_flags="-d" ;;
        4)
            echo "   Available flags:"
            echo "   -i : skip Geekbench system performance test"
            echo "   -d : skip fio disk performance test"
            echo "   -r : skip speedtest network performance test"
            echo "   -w : skip WireGuard network stack test"
            echo "   Example: -id (skip both Geekbench and disk test)"
            read -rp "   Enter flags (without dash): " custom_flags
            [[ -n "$custom_flags" ]] && yabs_flags="-$custom_flags"
            ;;
        *) log_warn "Invalid choice"; return 1 ;;
    esac
    
    run_generic_command \
        "YABS Benchmark" \
        "interactive" \
        "curl -sL yabs.sh | bash $yabs_flags" \
        "Interactive comprehensive system testing" \
        "yabs.sh"
}

run_speedtest() {
    section_title "Running Speedtest (Ookla)"
    
    if ! command -v speedtest-cli >/dev/null 2>&1; then
        log_info "speedtest-cli not found. Installing..."
        pkg_update >/dev/null 2>&1 && pkg_install "speedtest-cli" >/dev/null 2>&1
    fi
    
    echo "   Speedtest options:"
    echo "   1) Automatic server selection (interactive)"
    echo "   2) List servers and choose"
    echo "   3) Test download only"
    echo "   4) Test upload only"
    echo "   5) Share results"
    echo "   0) Cancel"
    echo
    
    read -rp "   Choose option [0-5]: " speed_choice
    
    [[ "$speed_choice" == "0" ]] && { log_warn "Cancelled"; return 1; }
    
    local speedtest_cmd="speedtest-cli"
    
    case $speed_choice in
        1) 
            run_generic_command \
                "Speedtest" \
                "interactive" \
                "speedtest-cli" \
                "Interactive network speed test" \
                "speedtest.net"
            ;;
        2) 
            log_info "Fetching server list..."
            speedtest-cli --list | head -20
            read -rp "   Enter server ID: " server_id
            if [[ -n "$server_id" ]]; then
                run_generic_command \
                    "Speedtest" \
                    "interactive" \
                    "speedtest-cli --server $server_id" \
                    "Interactive network speed test with selected server" \
                    "speedtest.net"
            fi
            ;;
        3)
            run_generic_command \
                "Speedtest (Download Only)" \
                "interactive" \
                "speedtest-cli --no-upload" \
                "Interactive download speed test" \
                "speedtest.net"
            ;;
        4)
            run_generic_command \
                "Speedtest (Upload Only)" \
                "interactive" \
                "speedtest-cli --no-download" \
                "Interactive upload speed test" \
                "speedtest.net"
            ;;
        5)
            run_generic_command \
                "Speedtest (with Sharing)" \
                "interactive" \
                "speedtest-cli --share" \
                "Interactive network speed test with result sharing" \
                "speedtest.net"
            ;;
        *) log_warn "Invalid choice"; return 1 ;;
    esac
}


#######################################

###### Quick Setup ######

quick_setup_full() {
    section_title "Quick Server Setup"
    echo -e "${BOLD}${GREEN}This will perform the following actions:${RESET}"
    echo "  🔄 Update system packages (apk update && apk upgrade)"
    echo "  ✅ Clean up existing swap files/partitions"
    echo "  ✅ Auto-configure optimal swap (if needed)"
    echo "  ✅ Set timezone to Asia/Shanghai" 
    echo "  ✅ Install essential packages"
    echo "  ✅ Apply network optimization (BBR/BBR2)"
    
    if [[ "$OS_TYPE" != "alpine" ]]; then
        echo "  ✅ Apply system logs optimization"
    else
        echo -e "  ${YELLOW}⚠️  Logs optimization skipped (not available in Alpine)${RESET}"
    fi
    
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
    if [[ "$OS_TYPE" == "alpine" ]]; then
        cp /usr/share/zoneinfo/$DEFAULT_TIMEZONE /etc/localtime 2>/dev/null && \
            echo "$DEFAULT_TIMEZONE" > /etc/timezone && \
            log_ok "Timezone set to: $DEFAULT_TIMEZONE" || \
            log_warn "Failed to set timezone"
    else
        timedatectl set-timezone "$DEFAULT_TIMEZONE" 2>/dev/null && \
            log_ok "Timezone set to: $(timedatectl show --property=Timezone --value)" || \
            log_warn "Failed to set timezone"
    fi
    
    sub_section "Step 4: Package Installation"
    pkg_install "${BASE_PACKAGES[@]}" && \
        log_ok "Packages installed successfully" || \
        log_warn "Some packages failed to install"
    
    sub_section "Step 5: Network Optimization"
    apply_network_optimization
    
    if [[ "$OS_TYPE" != "alpine" ]]; then
        sub_section "Step 6: System Logs Optimization"
        optimize_system_logs
    else
        log_info "Logs optimization skipped for Alpine Linux"
    fi
    
    log_ok "🎉 Quick setup completed successfully!"
    echo -e "${GREEN}Your server is now optimized and ready for use.${RESET}"
    pause
}

quick_setup_partial() {
    section_title "Quick Server Setup (Software+Swap+Network)"
    echo -e "${BOLD}${GREEN}This will perform the following actions:${RESET}"
    echo "  🔄 Update system packages (apk update && apk upgrade)"
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
    pkg_install "${BASE_PACKAGES[@]}" && \
        log_ok "Packages installed successfully" || \
        log_warn "Some packages failed to install"
    
    sub_section "Step 4: Network Optimization"
    apply_network_optimization
    
    log_ok "🎉 Quick setup completed successfully!"
    echo -e "${GREEN}Your server is now optimized and ready for use.${RESET}"
    pause
}

#######################################

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
        printf "   %-${col1_width}s\n" ""
        
        echo
        read -rp "   Choose option [0-10]: " choice
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
            0)
                echo
                log_ok "   Thank you for using Server Setup Essentials! 👋"
                echo -e "${GREEN}Log file: ${LOG_FILE}${RESET}"
                exit 0
                ;;
            *) log_warn "Invalid choice"; pause ;;
        esac
    done
}

main() {
    require_root
    
    trap 'echo; log_error "Script interrupted"; exit 1' INT TERM
    
    echo "=== Server Setup Essentials $VERSION - $(date) ===" > "$LOG_FILE"
    
    # OS compatibility check
    if [[ "$OS_TYPE" == "alpine" ]]; then
        log_info "Running on Alpine Linux - some features are adapted for Alpine"
        log_info "Detected OS: $OS_TYPE, Package Manager: $PKG_MANAGER"
        
        # Install bc if not present
        if ! command -v bc >/dev/null 2>&1; then
            log_info "Installing bc for calculations..."
            apk add --no-cache bc 2>/dev/null || true
        fi
    elif [[ "$OS_TYPE" == "unknown" ]]; then
        log_warn "This script is optimized for Alpine, Debian/Ubuntu and CentOS/RHEL based systems"
        read -rp "Continue anyway? (y/N): " proceed
        [[ $proceed =~ ^[Yy]$ ]] || exit 1
    else
        log_info "Detected OS: $OS_TYPE, Package Manager: $PKG_MANAGER"
    fi
    
    main_menu
}

main "$@"
