#!/bin/bash
# ============================================================
# DDNS Auto-Update Manager
# Version: see SCRIPT_VERSION below
# ============================================================
#
# DESCRIPTION:
#   Monitors your public IP and automatically updates a
#   Cloudflare DNS A record when the IP changes.
#   Designed for dynamic IP environments (home servers,
#   NAT VPS, LXD containers, etc).
#
# COMPATIBILITY:
#   - Debian / Ubuntu (apt)
#   - Alpine Linux (apk)
#   - systemd and OpenRC init systems
#   - NAT VPS (uses DDNS domain as IP fallback)
#
# HOW IT WORKS:
#   1. Detects current public IP via HTTP services
#      (ifconfig.me, icanhazip.com, checkip.amazonaws.com)
#   2. Falls back to resolving DDNS_DOMAIN via DNS if HTTP fails
#   3. Compares detected IP against Cloudflare DNS record
#   4. Updates the Cloudflare A record if IP has changed
#   5. Creates the record if it does not exist yet
#   6. Warns and prompts before overwriting non-A records
#
# DEPENDENCIES (auto-installed if missing):
#   - curl       : HTTP requests to IP services and Cloudflare API
#   - dnsutils   : 'host' command for DNS resolution (Debian/Ubuntu)
#   - bind-tools : 'host' command (Alpine)
#   - awk        : parsing DNS output
#
# CONFIGURATION:
#   - Edit DEFAULT_* variables below for pre-deployment setup
#   - Or configure interactively via the Settings menu
#   - Config is saved to /etc/ddns-update/config.env
#
# SERVICE MODES:
#   - Systemd service (Debian/Ubuntu) for sub-minute intervals
#   - OpenRC service (Alpine) for sub-minute intervals
#   - Cron job for intervals >= 60 seconds
#
# USAGE:
#   ./ddns-manager.sh           -- interactive menu
#   ./ddns-manager.sh run       -- check and update once
#   ./ddns-manager.sh daemon    -- run continuously (used by service)
#   ./ddns-manager.sh status    -- show current status
#   ./ddns-manager.sh install   -- install as system service
#
# LOGS:
#   /var/log/ddns-update.log (capped at 500 lines)
#
# ============================================================

SCRIPT_NAME="DDNS Auto-Update Manager"
SCRIPT_VERSION="v0.3.4"

# ============================================================
# DEFAULT CONFIGURATION — edit here or configure via menu
# ============================================================
DEFAULT_DDNS_DOMAIN=""        # Source DDNS domain (optional, used as IP fallback)
DEFAULT_CF_ZONE_ID=""         # Cloudflare Zone ID
DEFAULT_CF_API_TOKEN=""       # Cloudflare API Token
DEFAULT_CF_RECORD_ID=""       # Cloudflare DNS Record ID (or use auto-fetch)
DEFAULT_TARGET_RECORD=""      # DNS record name to update (e.g. my.domain.com)
DEFAULT_TTL=60                # TTL in seconds (minimum 60)
DEFAULT_CHECK_INTERVAL=30     # Check interval in seconds

CONFIG_FILE="/etc/ddns-update/config.env"
LOG_FILE="/var/log/ddns-update.log"
MAX_LOG_LINES=500
CRON_FILE="/etc/cron.d/ddns-update"
SCRIPT_PATH=$(realpath "$0")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'


# ============================================================
# DETECT PACKAGE MANAGER & INIT SYSTEM
# ============================================================
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then PKG_MANAGER="apt"
    elif command -v apk &>/dev/null;   then PKG_MANAGER="apk"
    else                                    PKG_MANAGER="unknown"
    fi
}

detect_init_system() {
    if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service &>/dev/null; then
        INIT_SYSTEM="openrc"
    else
        INIT_SYSTEM="unknown"
    fi
}

# ============================================================
# ENSURE DEPENDENCIES
# ============================================================
ensure_dependencies() {
    detect_pkg_manager
    local missing_pkgs=()

    command -v curl &>/dev/null || missing_pkgs+=(curl)
    if ! command -v host &>/dev/null; then
        [ "$PKG_MANAGER" = "apk" ] && missing_pkgs+=(bind-tools) || missing_pkgs+=(dnsutils)
    fi
    command -v awk &>/dev/null || missing_pkgs+=(gawk)

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚙️  Installing: ${missing_pkgs[*]}${NC}"
        if [ "$PKG_MANAGER" = "apt" ]; then
            apt-get update -qq && apt-get install -y -qq "${missing_pkgs[@]}"
        elif [ "$PKG_MANAGER" = "apk" ]; then
            apk add --quiet "${missing_pkgs[@]}"
        else
            echo -e "${RED}❌ Unknown package manager — install manually: ${missing_pkgs[*]}${NC}"
            return 1
        fi
        [ $? -eq 0 ] && echo -e "${GREEN}✅ Dependencies installed${NC}" || echo -e "${RED}❌ Failed to install: ${missing_pkgs[*]}${NC}"
    fi
}
# ============================================================
# LOAD CONFIG
# ============================================================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        # Defaults from top-of-file variables
        DDNS_DOMAIN="$DEFAULT_DDNS_DOMAIN"
        CF_ZONE_ID="$DEFAULT_CF_ZONE_ID"
        CF_API_TOKEN="$DEFAULT_CF_API_TOKEN"
        CF_RECORD_ID="$DEFAULT_CF_RECORD_ID"
        TARGET_RECORD="$DEFAULT_TARGET_RECORD"
        TTL=$DEFAULT_TTL
        CHECK_INTERVAL=$DEFAULT_CHECK_INTERVAL
    fi
}

# ============================================================
# SAVE CONFIG
# ============================================================
save_config() {
    mkdir -p /etc/ddns-update
    cat > "$CONFIG_FILE" <<EOF
DDNS_DOMAIN="$DDNS_DOMAIN"
CF_ZONE_ID="$CF_ZONE_ID"
CF_API_TOKEN="$CF_API_TOKEN"
CF_RECORD_ID="$CF_RECORD_ID"
TARGET_RECORD="$TARGET_RECORD"
TTL=$TTL
CHECK_INTERVAL=$CHECK_INTERVAL
EOF
    echo -e "${GREEN}✅ Config saved to $CONFIG_FILE${NC}"
}

# ============================================================
# LOGGING
# ============================================================
log() {
    # Trim log if too large
    if [ -f "$LOG_FILE" ] && [ $(wc -l < "$LOG_FILE") -gt $MAX_LOG_LINES ]; then
        tail -$((MAX_LOG_LINES / 2)) "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
    # Strip ANSI color codes before writing to log file
    local plain
    plain=$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $plain" >> "$LOG_FILE"
    echo -e "$1"
}

# ============================================================
# GET CURRENT PUBLIC IP
# ============================================================
get_public_ip() {
    local ip
    # Primary: external HTTP IP services
    ip=$(curl -s --max-time 10 https://ifconfig.me 2>/dev/null)
    [ -n "$ip" ] && echo "$ip" && return
    ip=$(curl -s --max-time 10 https://icanhazip.com 2>/dev/null)
    [ -n "$ip" ] && echo "$ip" && return
    ip=$(curl -s --max-time 10 https://checkip.amazonaws.com 2>/dev/null)
    [ -n "$ip" ] && echo "$ip" && return
    # Fallback: resolve DDNS domain (if Source is configured)
    if [ -n "$DDNS_DOMAIN" ] && command -v host &>/dev/null; then
        ip=$(host "$DDNS_DOMAIN" 1.1.1.1 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
        [ -n "$ip" ] && echo "$ip" && return
    fi
    echo ""
}

# ============================================================
# GET RECORD INFO FROM CLOUDFLARE (type + content)
# ============================================================
get_cf_record_info() {
    curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$CF_RECORD_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json"
}

get_cf_ip() {
    get_cf_record_info | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"//'
}

get_cf_record_type() {
    get_cf_record_info | grep -o '"type":"[^"]*"' | head -1 | sed 's/"type":"//;s/"//'
}

# ============================================================
# CREATE NEW CLOUDFLARE A RECORD
# ============================================================
create_cf_record() {
    local new_ip=$1
    local result=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$TARGET_RECORD\",\"content\":\"$new_ip\",\"ttl\":$TTL,\"proxied\":false}")
    local success=$(echo "$result" | grep -o '"success":[^,}]*' | head -1 | sed 's/"success"://')
    # Save the new record ID
    if [ "$success" = "true" ]; then
        CF_RECORD_ID=$(echo "$result" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')
        save_config
    fi
    echo "$success"
}

# ============================================================
# UPDATE CLOUDFLARE DNS RECORD
# ============================================================
update_cf_record() {
    local new_ip=$1

    # If no Record ID, try to fetch or create
    if [ -z "$CF_RECORD_ID" ]; then
        log "${YELLOW}⚠️  No Record ID — attempting to fetch...${NC}"
        CF_RECORD_ID=$(fetch_record_id)
        if [ -z "$CF_RECORD_ID" ]; then
            log "${YELLOW}⚠️  Record not found — creating new A record...${NC}"
            echo $(create_cf_record "$new_ip")
            return
        fi
        save_config
    fi

    # Check record type — prompt if not A
    local rec_type=$(get_cf_record_type)
    if [ -n "$rec_type" ] && [ "$rec_type" != "A" ]; then
        # In daemon/non-interactive mode, skip to avoid silent overwrites
        if [ ! -t 0 ]; then
            log "${RED}❌ Record '$TARGET_RECORD' is type '$rec_type', not A — skipping (run interactively to overwrite)${NC}"
            echo "false"
            return
        fi
        echo -e "${YELLOW}⚠️  Record '$TARGET_RECORD' is type '$rec_type', not A.${NC}"
        read -p "Overwrite with A record pointing to $new_ip? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Skipped.${NC}"
            echo "false"
            return
        fi
    fi

    local result=$(curl -s -X PUT \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$CF_RECORD_ID" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$TARGET_RECORD\",\"content\":\"$new_ip\",\"ttl\":$TTL,\"proxied\":false}")

    local success=$(echo "$result" | grep -o '"success":[^,}]*' | head -1 | sed 's/"success"://')
    echo "$success"
}

# ============================================================
# GET RECORD ID FROM CLOUDFLARE
# ============================================================
fetch_record_id() {
    curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=$TARGET_RECORD&type=A" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" | \
        grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//'
}

# ============================================================
# CHECK AND UPDATE
# ============================================================
check_and_update() {
    local current_ip=$(get_public_ip)
    local cf_ip=$(get_cf_ip)

    if [ -z "$current_ip" ]; then
        log "${RED}❌ Failed to get public IP${NC}"
        return 1
    fi

    if [ "$current_ip" == "$cf_ip" ]; then
        # Silent on no change — only log updates and errors
        return 0
    fi

    log "${YELLOW}🔄 IP changed: $cf_ip → $current_ip — updating...${NC}"
    local result=$(update_cf_record "$current_ip")

    if [ "$result" == "true" ]; then
        log "${GREEN}✅ Updated $TARGET_RECORD → $current_ip${NC}"
    else
        log "${RED}❌ Failed to update Cloudflare record${NC}"
        return 1
    fi
}

# ============================================================
# INSTALL CRON JOB
# ============================================================
install_cron() {
    local interval=$CHECK_INTERVAL
    echo -e "${CYAN}Installing cron job every ${interval} seconds...${NC}"
    detect_init_system

    # Cron minimum is 1 minute — for sub-minute use a service
    if [ "$interval" -lt 60 ]; then
        echo -e "${YELLOW}⚠️  Interval < 60s — installing as service instead${NC}"
        install_service
    else
        local minutes=$((interval / 60))
        if [ "$INIT_SYSTEM" = "openrc" ]; then
            # Alpine: write to /etc/crontabs/root
            local cron_entry="*/$minutes * * * * /bin/sh ${SCRIPT_PATH} run >> $LOG_FILE 2>&1"
            touch /etc/crontabs/root
            grep -qF "$SCRIPT_PATH" /etc/crontabs/root &&                 sed -i "\|$SCRIPT_PATH|d" /etc/crontabs/root
            echo "$cron_entry" >> /etc/crontabs/root
            rc-service crond restart 2>/dev/null || crond 2>/dev/null
        else
            echo "*/$minutes * * * * root /bin/bash ${SCRIPT_PATH} run >> $LOG_FILE 2>&1" > "$CRON_FILE"
            chmod 644 "$CRON_FILE"
        fi
        echo -e "${GREEN}✅ Cron installed: every $minutes minute(s)${NC}"
    fi
}

# ============================================================
# INSTALL SERVICE (systemd or openrc)
# ============================================================
install_service() {
    detect_init_system
    if [ "$INIT_SYSTEM" = "openrc" ]; then
        # Alpine OpenRC
        cat > /etc/init.d/ddns-update << 'INITEOF'
#!/sbin/openrc-run
description="DDNS Auto Update Service"
command="/bin/sh"
command_args="${SCRIPT_PATH} daemon"
pidfile="/run/ddns-update.pid"
command_background=true
depend() { need net; }
INITEOF
        sed -i "s|\${SCRIPT_PATH}|${SCRIPT_PATH}|g" /etc/init.d/ddns-update
        chmod +x /etc/init.d/ddns-update
        rc-update add ddns-update default
        rc-service ddns-update restart
        echo -e "${GREEN}✅ OpenRC service installed and started${NC}"
    else
        # systemd (Debian/Ubuntu)
        cat > /etc/systemd/system/ddns-update.service <<EOF
[Unit]
Description=DDNS Auto Update Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash ${SCRIPT_PATH} daemon
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ddns-update
        systemctl restart ddns-update
        echo -e "${GREEN}✅ Systemd service installed and started${NC}"
    fi
}

# Keep old name as alias for compatibility
install_systemd_service() { install_service; }

# ============================================================
# DAEMON MODE (runs continuously)
# ============================================================
run_daemon() {
    log "${CYAN}🚀 DDNS Update Daemon started (interval: ${CHECK_INTERVAL}s)${NC}"
    while true; do
        check_and_update
        sleep "$CHECK_INTERVAL"
    done
}

# ============================================================
# SHOW STATUS
# ============================================================
show_status() {
    echo -e "\n${CYAN}============================================${NC}"
    echo -e "${CYAN}       ${SCRIPT_NAME}${NC}"
    echo -e "${CYAN}       Version: ${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo -e "${BLUE}Source:${NC}    $DDNS_DOMAIN"
    echo -e "${BLUE}Target Record:${NC}  $TARGET_RECORD"
    echo -e "${BLUE}Zone ID:${NC}        ${CF_ZONE_ID:0:8}...${CF_ZONE_ID: -4}"
    echo -e "${BLUE}Record ID:${NC}      ${CF_RECORD_ID:0:8}...${CF_RECORD_ID: -4}"
    echo -e "${BLUE}TTL:${NC}            ${TTL}s"
    echo -e "${BLUE}Check Interval:${NC} ${CHECK_INTERVAL}s"
    echo ""

    local current_ip=$(get_public_ip)
    local cf_ip=$(get_cf_ip)

    echo -e "${BLUE}Public IP:${NC}  ${current_ip:-unknown}"
    echo -e "${BLUE}CF Record IP:${NC}     ${cf_ip:-unknown}"

    if [ "$current_ip" == "$cf_ip" ] && [ -n "$current_ip" ]; then
        echo -e "${GREEN}✅ IPs are in sync${NC}"
    else
        echo -e "${RED}⚠️  IPs are out of sync!${NC}"
    fi

    echo ""
    echo -e "${BLUE}Service Status:${NC}"
    detect_init_system
    if [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service ddns-update status 2>/dev/null | grep -q started && \
            echo -e "  ${GREEN}● ddns-update service: running${NC}" || \
            echo -e "  ${RED}● ddns-update service: not running${NC}"
    else
        systemctl is-active ddns-update 2>/dev/null | grep -q active && \
            echo -e "  ${GREEN}● ddns-update service: running${NC}" || \
            echo -e "  ${RED}● ddns-update service: not running${NC}"
    fi

    echo -e "\n${BLUE}Last 5 log entries:${NC}"
    tail -5 "$LOG_FILE" 2>/dev/null || echo "  No logs yet"
    echo ""
}

# ============================================================
# SETTINGS MENU
# ============================================================
settings_menu() {
    echo -e "\n${CYAN}============================================${NC}"
    echo -e "${CYAN}         Settings${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo -e "Current values:\n"
    echo -e "  1) Source:    ${YELLOW}$DDNS_DOMAIN${NC}"
    echo -e "  2) Target Record:  ${YELLOW}$TARGET_RECORD${NC}"
    echo -e "  3) Zone ID:        ${YELLOW}${CF_ZONE_ID:0:8}...${NC}"
    echo -e "  4) API Token:      ${YELLOW}${CF_API_TOKEN:0:8}...${NC}"
    echo -e "  5) Record ID:      ${YELLOW}${CF_RECORD_ID:0:8}...${NC} (or auto-fetch)"
    echo -e "  6) TTL:            ${YELLOW}${TTL}s${NC}"
    echo -e "  7) Check Interval: ${YELLOW}${CHECK_INTERVAL}s${NC}"
    echo -e "  8) Auto-fetch Record ID from Cloudflare"
    echo -e "  9) Save & Exit"
    echo -e "  0) Cancel\n"

    read -p "Choose option: " opt
    case $opt in
        1) read -p "Source [$DDNS_DOMAIN]: " val; [ -n "$val" ] && DDNS_DOMAIN="$val"; settings_menu ;;
        2) read -p "Target Record [$TARGET_RECORD]: " val; [ -n "$val" ] && TARGET_RECORD="$val"; settings_menu ;;
        3) read -p "Zone ID [$CF_ZONE_ID]: " val; [ -n "$val" ] && CF_ZONE_ID="$val"; settings_menu ;;
        4) read -p "API Token [$CF_API_TOKEN]: " val; [ -n "$val" ] && CF_API_TOKEN="$val"; settings_menu ;;
        5) read -p "Record ID [$CF_RECORD_ID]: " val; [ -n "$val" ] && CF_RECORD_ID="$val"; settings_menu ;;
        6) read -p "TTL in seconds [$TTL]: " val; [ -n "$val" ] && TTL="$val"; settings_menu ;;
        7) read -p "Check interval in seconds [$CHECK_INTERVAL]: " val; [ -n "$val" ] && CHECK_INTERVAL="$val"; settings_menu ;;
        8)
            echo -e "${CYAN}Fetching Record ID...${NC}"
            local id=$(fetch_record_id)
            if [ -n "$id" ]; then
                CF_RECORD_ID="$id"
                echo -e "${GREEN}✅ Record ID fetched: $CF_RECORD_ID${NC}"
            else
                echo -e "${RED}❌ Failed to fetch Record ID — check Zone ID and API Token${NC}"
            fi
            settings_menu
            ;;
        9) save_config ;;
        0) return ;;
    esac
}

# ============================================================
# MAIN MENU
# ============================================================
main_menu() {
    load_config
    while true; do
        echo -e "\n${CYAN}============================================${NC}"
        echo -e "${CYAN}     ${SCRIPT_NAME}${NC}"
        echo -e "${CYAN}     ${SCRIPT_VERSION}${NC}"
        echo -e "${CYAN}============================================${NC}"
        echo -e "  1) Show Status"
        echo -e "  2) Run Update Now"
        echo -e "  3) Settings"
        echo -e "  4) Install Service (auto-start)"
        echo -e "  5) Start Service"
        echo -e "  6) Stop Service"
        echo -e "  7) View Logs"
        echo -e "  8) Exit\n"

        read -p "Choose option: " opt
        case $opt in
            1) show_status ;;
            2) check_and_update ;;
            3) settings_menu ;;
            4) install_cron ;;
            5) detect_init_system
               if [ "$INIT_SYSTEM" = "openrc" ]; then rc-service ddns-update start; else systemctl start ddns-update; fi
               echo -e "${GREEN}✅ Service started${NC}" ;;
            6) detect_init_system
               if [ "$INIT_SYSTEM" = "openrc" ]; then rc-service ddns-update stop; else systemctl stop ddns-update; fi
               echo -e "${GREEN}✅ Service stopped${NC}" ;;
            7) tail -50 "$LOG_FILE" 2>/dev/null || echo "No logs yet" ;;
            8) exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
    done
}

# ============================================================
# ENTRY POINT
# ============================================================
ensure_dependencies
load_config

case "${1:-menu}" in
    menu)    main_menu ;;
    run)     check_and_update ;;
    daemon)  run_daemon ;;
    status)  show_status ;;
    install) install_cron ;;
    *)       echo "Usage: $0 {menu|run|daemon|status|install}" ;;
esac
