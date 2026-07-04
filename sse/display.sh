#!/usr/bin/env bash
#
# display.sh - Display, formatting, system info, and session cache logic

sse_init_session_cache() {
    echo -e "${CYAN}${BOLD}[INFO]${RESET} ${CYAN}Initializing dashboard (one-time fetch)...${RESET}"

    set +o pipefail

    SSE_SESSION_HOSTNAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    SSE_SESSION_OS=$(get_os_info 2>/dev/null || echo "Unknown OS")
    SSE_SESSION_KERNEL=$(uname -r 2>/dev/null || echo "unknown")
    SSE_SESSION_CPU=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo 2>/dev/null | sed 's/\<Processor\>//g' | xargs 2>/dev/null || echo "unknown")
    SSE_SESSION_CORES=$(nproc 2>/dev/null || echo "?")
    SSE_SESSION_DISK_TYPE=$(get_disk_type 2>/dev/null || echo "unknown")

    SSE_SESSION_BBR_STATUS=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")
    SSE_SESSION_QDISC_STATUS=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "N/A")
    SSE_SESSION_IPV6_LOCAL=$(ip -6 addr show scope global 2>/dev/null | grep -m1 inet6 | awk '{print $2}' | cut -d'/' -f1 || echo "")

    SSE_SESSION_IPV4_ONLINE="$(
        curl -4 -s --max-time 3 https://ping0.cc 2>/dev/null ||
        curl -4 -s --max-time 3 https://ifconfig.me 2>/dev/null ||
        curl -4 -s --max-time 3 https://api.ipify.org 2>/dev/null ||
        echo "N/A"
    )" || SSE_SESSION_IPV4_ONLINE="N/A"
    
    SSE_SESSION_IPV6_ONLINE="$(
        curl -6 -s --max-time 3 https://ping0.cc 2>/dev/null ||
        curl -6 -s --max-time 3 https://ifconfig.me 2>/dev/null ||
        curl -6 -s --max-time 3 https://api.ipify.org 2>/dev/null ||
        echo "N/A"
    )" || SSE_SESSION_IPV6_ONLINE="N/A"

    if command -v vnstat >/dev/null 2>&1; then
        SSE_SESSION_VNSTAT_VERSION=$(vnstat --version 2>/dev/null | awk '{print $2}' || echo "")
        SSE_SESSION_VNSTAT_OUTPUT=$(vnstat --oneline 2>/dev/null || echo "")
    fi

    SSE_SESSION_CACHE_READY=1
    set -o pipefail
}

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
    awk 'NR>1 {print $1}' /proc/swaps 2>/dev/null || true
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

fmt_uptime() {
    local up
    up=$(uptime -p 2>/dev/null | sed 's/^up //') || true
    if [[ -z "$up" || "$up" == *"error"* ]]; then
        local secs
        secs=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || echo 0)
        local d=$(( secs/86400 )) h=$(( (secs%86400)/3600 )) m=$(( (secs%3600)/60 ))
        up=""
        [[ $d -gt 0 ]] && up="${d}d "
        [[ $h -gt 0 ]] && up="${up}${h}h "
        [[ $m -gt 0 ]] && up="${up}${m}m"
        up="${up:-0m}"
    else
        up=$(echo "$up" | sed -E 's/weeks?/w/g; s/days?/d/g; s/hours?/h/g; s/minutes?/m/g; s/seconds?/s/g; s/,//g')
        if echo "$up" | grep -qE '[wd]'; then
            up=$(echo "$up" | sed -E 's/[0-9]+m//g; s/[0-9]+s//g')
        fi
        up=$(echo "$up" | tr -s ' ' | sed 's/ *$//')
    fi
    echo "$up"
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
    local percent=$1 color=$RESET
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
    if [[ "$SSE_OS_TYPE" == "debian" ]]; then
        OS=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        OS=$(cat /etc/redhat-release 2>/dev/null || cat /etc/centos-release 2>/dev/null || \
             cat /etc/almalinux-release 2>/dev/null || cat /etc/rocky-release 2>/dev/null || \
             grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    fi
    echo "$OS"
}

display_system_status() {
    local boot_str
    boot_str=$(who -b 2>/dev/null | awk '{print $3, $4}' || true)
    [[ -z "$boot_str" ]] && boot_str="N/A (WSL)"
    printf "${MAGENTA}%-14s${RESET} %-17s ${MAGENTA}%-10s${RESET} %-20s\n" \
        "  Boot:" "$boot_str" "Uptime:" "$(fmt_uptime)"

    printf "${MAGENTA}%-14s${RESET} %-17s ${MAGENTA}%-10s${RESET} %-20s\n" \
        "  Current:" "$(date '+%Y-%m-%d %H:%M')" "Timezone:" "$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")"
    
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

    if [[ -n "$SSE_SESSION_VNSTAT_VERSION" ]]; then
        local vnstat_output="$SSE_SESSION_VNSTAT_OUTPUT"
        if [[ -n "$vnstat_output" ]]; then
            local vnstat_month=$(echo "$vnstat_output" | awk -F';' '{print $8}')
            local vnstat_rx=$(echo "$vnstat_output" | awk -F';' '{print $9}')
            local vnstat_tx=$(echo "$vnstat_output" | awk -F';' '{print $10}')
            local vnstat_total=$(echo "$vnstat_output" | awk -F';' '{print $11}')

            printf "${YELLOW}%-14s${RESET} %-9s %-9s ${GREEN}%-10s${RESET} ${CYAN}%-10s${RESET} ${MAGENTA}%-10s${RESET}\n" \
                "" "iface" "Duration" "RX/UL" "TX/DL" "Total"
            printf "${YELLOW}%-14s${RESET} %-9s %-9s %-10s %-10s %-10s\n" \
                "  vnStat $SSE_SESSION_VNSTAT_VERSION" "$INTERFACES" "$vnstat_month" "$vnstat_rx" "$vnstat_tx" "$vnstat_total"
        else
            printf "${YELLOW}%-14s${RESET} ${RED}%-46s${RESET}\n" "  Bandwidth:" "Collecting data..."
        fi
    else
        printf "${YELLOW}%-14s${RESET} ${RED}%-46s${RESET}\n" "  Bandwidth:" "vnStat not installed"
    fi
}

display_traffic_info() {
    local boot_time_str
    boot_time_str=$(who -b 2>/dev/null | awk '{print $3, $4}' || true)
    local BOOT_DAYS
    if [[ -n "$boot_time_str" ]]; then
        local boot_epoch=$(date -d "$boot_time_str" +%s 2>/dev/null || echo 0)
        BOOT_DAYS=$(echo $(( $(date +%s) - boot_epoch )) | awk '{printf "%d days\n", $1/86400}')
    else
        local uptime_secs=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || echo 0)
        BOOT_DAYS=$(echo "$uptime_secs" | awk '{printf "%d days\n", $1/86400}')
    fi

    ip -s link | awk -v boot_days="$BOOT_DAYS" '
    function human(x){
        split("B KB MB GB TB",u); i=1;
        while(x>=1024&&i<5){ x/=1024; i++ }
        return sprintf("%.2f %s",x,u[i])
    } 
    /^[0-9]+:/{ iface=$2; gsub(":","",iface) } 
    /RX:/{ getline; rx=$1 } 
    /TX:/{
        getline; tx=$1;
        if(iface != "lo") {
            total=rx+tx;
            printf "  %-12s %-9s %-9s %-10s %-10s %-10s\n", "Server", iface, boot_days, human(rx), human(tx), human(total)
        }
    }' | head -3
}

display_system_info() {
    printf "${YELLOW}%-14s${RESET} %-46s\n" "  Hostname:" "$SSE_SESSION_HOSTNAME"
    printf "${YELLOW}%-14s${RESET} %-22s ${GRAY}%s${RESET}\n" "  OS:" "$SSE_SESSION_OS" "(Kernel: $SSE_SESSION_KERNEL)"
    printf "${YELLOW}%-14s${RESET} %-46s\n" "  CPU:" "$SSE_SESSION_CPU ($SSE_SESSION_CORES cores)"
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
        "${DISK_USED} / ${DISK_TOTAL} (${DISK_PERCENT})" "$SSE_SESSION_DISK_TYPE"
        
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
    local IPV4=$(hostname -I | awk '{print $1}')
    local IPV4_onlineIP="$SSE_SESSION_IPV4_ONLINE"
    local IPV6_onlineIP="$SSE_SESSION_IPV6_ONLINE"
    local IPV6="$SSE_SESSION_IPV6_LOCAL"
    local bbr_status="$SSE_SESSION_BBR_STATUS"
    local q_status="$SSE_SESSION_QDISC_STATUS"

    local ipv6_status=$([ -n "$IPV6" ] && echo -e "${GREEN}IPv6 ✓${RESET}" || echo -e "${RED}IPv6 ✗${RESET}")
    local bbr_display=$(
      if [ "$bbr_status" == "bbr" ] || [ "$bbr_status" == "bbr2" ]; then
        echo -e "${GREEN}${bbr_status^^} ✓${RESET}"
      else
        echo -e "${RED}${bbr_status:-Not Set} ✗${RESET}"
      fi
    )
    local qdisc_display=$(
      if [ "$q_status" == "fq" ]; then
        echo -e "${GREEN}${q_status^^} ✓${RESET}"
      else
        echo -e "${RED}${q_status:-Not Set} ✗${RESET}"
      fi
    )

    printf "${YELLOW}%-14s${RESET} %-22s %s\n" "  Network:" "$IPV4" "$bbr_display + $qdisc_display"
    printf "${YELLOW}%-14s${RESET} %-22s %s\n" "  Internet:" "$IPV4_onlineIP" "$ipv6_status"
    printf "${YELLOW}%-14s${RESET} %-22s %s\n" "  IPv6:" "$IPV6_onlineIP"
}
