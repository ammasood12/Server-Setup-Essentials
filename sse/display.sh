#!/usr/bin/env bash
#
# display.sh - Display, formatting, system info, and session cache logic

sse_init_session_cache() {
    echo -e "${CYAN}${BOLD}[INFO]${RESET} ${CYAN}Initializing dashboard (one-time fetch)...${RESET}"

    set +o pipefail

    SSE_SESSION_HOSTNAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
    SSE_SESSION_OS=$(get_os_info 2>/dev/null || echo "Unknown OS")
    SSE_SESSION_KERNEL=$(uname -r 2>/dev/null || echo "unknown")
    
    local cpu_info
    cpu_info=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo 2>/dev/null | sed -E 's/\<(Processor|Logical Core)\>//g' | xargs 2>/dev/null)
    if [[ -z "$cpu_info" ]]; then
        cpu_info=$(awk -F: '/Processor/ {name=$2} END {print name}' /proc/cpuinfo 2>/dev/null | xargs 2>/dev/null)
    fi
    if [[ -z "$cpu_info" ]]; then
        cpu_info=$(uname -m 2>/dev/null || echo "unknown")
    fi
    SSE_SESSION_CPU="$cpu_info"

    SSE_SESSION_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
    SSE_SESSION_DISK_TYPE=$(get_disk_type 2>/dev/null || echo "unknown")

    SSE_SESSION_BBR_STATUS=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")
    SSE_SESSION_QDISC_STATUS=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "N/A")
    SSE_SESSION_IPV6_LOCAL=$(ip -6 addr show scope global 2>/dev/null | grep -m1 inet6 | awk '{print $2}' | cut -d'/' -f1 || ip -6 addr show 2>/dev/null | grep inet6 | grep -v 'fe80::' | head -n1 | awk '{print $2}' | cut -d'/' -f1 || echo "")

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
        if [[ $d -gt 0 ]]; then
            up="${d}d "
        fi
        if [[ $h -gt 0 ]]; then
            up="${up}${h}h "
        fi
        if [[ $m -gt 0 ]]; then
            up="${up}${m}m"
        fi
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
    # 1. Try sysfs rotational flag for the root partition disk
    local root_dev
    root_dev=$(df / 2>/dev/null | awk 'NR==2 {print $1}')
    if [[ -n "$root_dev" ]]; then
        local disk_name
        disk_name=$(basename "$root_dev")
        # Handle NVMe partitions (e.g. nvme0n1p1 -> nvme0n1) and standard partitions (e.g. sda1 -> sda)
        if [[ "$disk_name" =~ nvme ]]; then
            disk_name=$(echo "$disk_name" | sed -E 's/p[0-9]+$//')
        else
            disk_name=$(echo "$disk_name" | sed -E 's/[0-9]+$//')
        fi
        
        if [[ -f "/sys/block/${disk_name}/queue/rotational" ]]; then
            local rota
            rota=$(cat "/sys/block/${disk_name}/queue/rotational" 2>/dev/null)
            if [[ "$rota" == "0" ]]; then
                echo -e "${GREEN}🚀 SSD$RESET"
                return
            elif [[ "$rota" == "1" ]]; then
                echo -e "${BLUE}💾 HDD$RESET"
                return
            fi
        fi
    fi

    # 2. Fallback to lsblk
    if command -v lsblk >/dev/null 2>&1; then
        local disk_type_value
        disk_type_value=$(lsblk -d -o ROTA 2>/dev/null | awk 'NR==2 {print $1}')
        case "$disk_type_value" in
            "0") echo -e "${GREEN}🚀 SSD$RESET" ; return ;;
            "1") echo -e "${BLUE}💾 HDD$RESET" ; return ;;
        esac
    fi

    # 3. Default fallback
    echo -e "${YELLOW}💿 Unknown$RESET"
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
    local OS=""
    if [[ "$SSE_OS_TYPE" == "alpine" ]]; then
        OS=$(cat /etc/alpine-release 2>/dev/null)
        OS="Alpine Linux ${OS:-}"
    elif [[ "$SSE_OS_TYPE" == "debian" ]]; then
        OS=$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        OS=$(cat /etc/redhat-release 2>/dev/null || cat /etc/centos-release 2>/dev/null || \
             cat /etc/almalinux-release 2>/dev/null || cat /etc/rocky-release 2>/dev/null || \
             grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    fi
    echo "$OS" | xargs
}

display_system_status() {
    local boot_str=""
    if command -v who >/dev/null 2>&1; then
        boot_str=$(who -b 2>/dev/null | awk '{print $3, $4}' || true)
    fi
    if [[ -z "$boot_str" ]]; then
        local uptime_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
        if [[ $uptime_secs -gt 0 ]]; then
            local current_epoch=$(date +%s)
            local boot_epoch=$((current_epoch - uptime_secs))
            boot_str=$(date -d "@$boot_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$boot_epoch" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "N/A")
        else
            boot_str="N/A"
        fi
    fi

    printf "${MAGENTA}%-14s${RESET} %-17s ${MAGENTA}%-10s${RESET} %-20s\n" \
        "  Boot:" "$boot_str" "Uptime:" "$(fmt_uptime)"

    local tz_val
    tz_val=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || date +%Z 2>/dev/null || echo "Unknown")
    printf "${MAGENTA}%-14s${RESET} %-17s ${MAGENTA}%-10s${RESET} %-20s\n" \
        "  Current:" "$(date '+%Y-%m-%d %H:%M')" "Timezone:" "$tz_val"
    
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
    local boot_days
    local uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
    boot_days=$((uptime_seconds / 86400))

    sed 's/:/ /' /proc/net/dev | awk -v boot_days="${boot_days}d" '
    function human(x){
        split("B KB MB GB TB",u); i=1;
        while(x>=1024&&i<5){ x/=1024; i++ }
        return sprintf("%.2f %s",x,u[i])
    }
    NR > 2 {
        iface=$1;
        if(iface != "lo") {
            rx=$2; tx=$10; total=rx+tx;
            printf "  %-12s %-9s %-9s %-10s %-10s %-10s\n", "Server", iface, boot_days, human(rx), human(tx), human(total)
        }
    }' 2>/dev/null | head -3
}

display_system_info() {
    printf "${YELLOW}%-14s${RESET} %-46s\n" "  Hostname:" "$SSE_SESSION_HOSTNAME"
    printf "${YELLOW}%-14s${RESET} %-22s ${GRAY}%s${RESET}\n" "  OS:" "$SSE_SESSION_OS" "(Kernel: $SSE_SESSION_KERNEL)"
    printf "${YELLOW}%-14s${RESET} %-46s\n" "  CPU:" "$SSE_SESSION_CPU ($SSE_SESSION_CORES cores)"
}

display_resource_usage() {
    local MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
    local MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    local MEM_PERCENT=0
    if [[ $MEM_TOTAL -gt 0 ]]; then
        MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
    fi
    
    local df_output
    df_output=$(df -h / 2>/dev/null | tail -n 1)
    local DISK_TOTAL=$(echo "$df_output" | awk '{print $(NF-4)}')
    local DISK_USED=$(echo "$df_output" | awk '{print $(NF-3)}')
    local DISK_PERCENT=$(echo "$df_output" | awk '{print $(NF-1)}')
    
    local LOAD
    LOAD=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | xargs 2>/dev/null || echo "")
    if [[ -z "$LOAD" ]]; then
        LOAD=$(awk '{print $1 ", " $2 ", " $3}' /proc/loadavg 2>/dev/null || echo "0.00, 0.00, 0.00")
    fi
    local load1=$(echo "$LOAD" | awk -F', ' '{print $1}' | sed 's/,//g')
    [[ -z "$load1" ]] && load1="0.00"
    
    local CORES
    CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
    
    local disk_color=$(get_disk_status "$DISK_PERCENT")
    printf "${YELLOW}%-14s${RESET} ${disk_color}%-22s${RESET} %s\n" "  Disk:" \
        "${DISK_USED} / ${DISK_TOTAL} (${DISK_PERCENT})" "$SSE_SESSION_DISK_TYPE"
        
    printf "${YELLOW}%-14s${RESET} %-22s %s\n" "  Load Avg:" "$LOAD" "$(get_load_status "$load1" "$CORES")"
    
    printf "${YELLOW}%-14s${RESET} %-22s %s\n" "  Memory:" "${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)" \
        "$(get_mem_status "$MEM_PERCENT" "$(get_free_ram_mb)")"    
    
    local swap_total=$(get_swap_total_mb)
    local swap_used=$(get_swap_used_mb)
    local swap_percent=0
    if [[ $swap_total -gt 0 ]]; then
        swap_percent=$((swap_used * 100 / swap_total))
    fi
    local recommended_swap=$(recommended_swap_mb)
    
    if [[ $swap_total -eq 0 ]]; then
        printf "${YELLOW}%-14s${RESET} ${RED}%-22s${RESET} ${RED}%s${RESET}\n" "  Swap:" "Not configured" "❌"
    else
        local swap_color=$RESET
        if [[ $swap_percent -gt 80 ]]; then
            swap_color=$RED
        elif [[ $swap_percent -gt 60 ]]; then
            swap_color=$YELLOW
        fi
        printf "${YELLOW}%-14s${RESET} ${swap_color}%-22s${RESET} %s\n" "  Swap:" \
            "${swap_used}MB / ${swap_total}MB (${swap_percent}%)" "$(get_swap_status "$swap_total" "$swap_used" "$swap_percent" "$recommended_swap")"
    fi
}

display_network_info() {
    local IPV4
    IPV4=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "$IPV4" ]]; then
        IPV4=$(hostname -i 2>/dev/null | awk '{print $1}')
    fi
    if [[ -z "$IPV4" ]]; then
        IPV4=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}' || echo "127.0.0.1")
    fi
    
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
