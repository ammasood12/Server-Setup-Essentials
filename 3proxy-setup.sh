#!/bin/bash
# ═══════════════════════════════════════════════════
#   3proxy SOCKS5 Manager
#   GitHub: your-repo/3proxy-setup
# ═══════════════════════════════════════════════════

VERSION="1.0.0"

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CFG="/etc/3proxy/3proxy.cfg"
LOG="/var/log/3proxy.log"

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; }
die()   { error "$1"; exit 1; }

# ─── Helpers ──────────────────────────────────────────────────────────────────

require_root() {
    [[ $EUID -ne 0 ]] && die "Run as root (sudo bash $0)"
}

require_installed() {
    command -v 3proxy > /dev/null 2>&1 || die "3proxy is not installed. Choose 'Install' first."
    [[ -f "$CFG" ]] || die "Config not found at $CFG. Choose 'Install' first."
}

get_port() {
    grep -oP '(?<=socks -p)\d+' "$CFG" 2>/dev/null || echo "unknown"
}

get_users() {
    grep -oP '(?<=users ).*' "$CFG" 2>/dev/null | tr ' ' '\n' | grep -oP '^[^:]+' || true
}

get_maxconn() {
    grep -oP '(?<=maxconn )\d+' "$CFG" 2>/dev/null || echo "100"
}

get_public_ip() {
    curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "unknown"
}

pause() {
    echo ""
    read -p "Press Enter to continue..."
}

firewall_allow() {
    local port=$1
    if command -v ufw > /dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow "$port"/tcp > /dev/null 2>&1 && info "UFW: allowed port $port"
    elif command -v iptables > /dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        info "iptables: allowed port $port"
    fi
}

firewall_remove() {
    local port=$1
    if command -v ufw > /dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw delete allow "$port"/tcp > /dev/null 2>&1 && info "UFW: removed rule for port $port"
    elif command -v iptables > /dev/null 2>&1; then
        iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
        info "iptables: removed rule for port $port"
    fi
}

write_config() {
    local port=$1
    local maxconn=$2
    local users_line=$3    # already formatted as "user1:CL:pass1 user2:CL:pass2"

    cat > "$CFG" << EOF
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60

auth strong
users ${users_line}

log ${LOG} D
logformat "- +_L%t.%.  %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 30

maxconn ${maxconn}

socks -p${port} -i0.0.0.0 -e0.0.0.0
EOF
    chmod 600 "$CFG"
}

systemd_fix() {
    SYSTEMD_UNIT=$(systemctl cat 3proxy 2>/dev/null | grep ExecStart | head -1 || true)
    if echo "$SYSTEMD_UNIT" | grep -q "3proxy.cfg" && ! echo "$SYSTEMD_UNIT" | grep -q "/etc/3proxy/3proxy.cfg"; then
        mkdir -p /etc/systemd/system/3proxy.service.d
        cat > /etc/systemd/system/3proxy.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/3proxy /etc/3proxy/3proxy.cfg
EOF
        systemctl daemon-reload
    fi
}

# ─── Screens ──────────────────────────────────────────────────────────────────

show_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║         3proxy SOCKS5 Manager             ║"
    echo "║         Version: ${VERSION}                    ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_status_bar() {
    if command -v 3proxy > /dev/null 2>&1 && [[ -f "$CFG" ]]; then
        local port
        port=$(get_port)
        local status
        if systemctl is-active --quiet 3proxy 2>/dev/null; then
            status="${GREEN}running${NC}"
        else
            status="${RED}stopped${NC}"
        fi
        local users
        users=$(get_users | tr '\n' ' ')
        local log_size
        log_size=$(du -sh "$LOG" 2>/dev/null | cut -f1 || echo "0")
        echo -e "  Status : $status"
        echo    "  Port   : $port"
        echo    "  Users  : ${users:-none}"
        echo    "  Log    : $log_size"
    else
        echo -e "  Status : ${YELLOW}not installed${NC}"
    fi
    echo ""
    echo "───────────────────────────────────────────"
    echo ""
}

# ─── Install ──────────────────────────────────────────────────────────────────

do_install() {
    show_header
    echo -e "${BOLD}  [ Install ]${NC}"
    echo ""

    if command -v 3proxy > /dev/null 2>&1 && [[ -f "$CFG" ]]; then
        warn "3proxy appears to already be installed."
        read -p "  Reinstall and overwrite config? [y/N]: " CONFIRM
        [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && return
    fi

    read -p "  SOCKS5 port (e.g. 54321): " SOCKS_PORT
    [[ -z "$SOCKS_PORT" ]] && die "Port cannot be empty"
    [[ ! "$SOCKS_PORT" =~ ^[0-9]+$ ]] && die "Port must be a number"
    [[ "$SOCKS_PORT" -lt 1024 || "$SOCKS_PORT" -gt 65535 ]] && die "Port must be 1024–65535"

    read -p "  Username: " PROXY_USER
    [[ -z "$PROXY_USER" ]] && die "Username cannot be empty"

    read -s -p "  Password: " PROXY_PASS; echo ""
    [[ -z "$PROXY_PASS" ]] && die "Password cannot be empty"
    [[ ${#PROXY_PASS} -lt 8 ]] && die "Password must be at least 8 characters"

    read -s -p "  Confirm password: " PROXY_PASS2; echo ""
    [[ "$PROXY_PASS" != "$PROXY_PASS2" ]] && die "Passwords do not match"

    read -p "  Max connections [100]: " MAXCONN
    MAXCONN=${MAXCONN:-100}

    echo ""
    info "Installing 3proxy..."
    apt-get update -qq
    apt-get install -y 3proxy > /dev/null 2>&1

    mkdir -p /etc/3proxy
    write_config "$SOCKS_PORT" "$MAXCONN" "${PROXY_USER}:CL:${PROXY_PASS}"
    systemd_fix
    firewall_allow "$SOCKS_PORT"

    systemctl enable 3proxy > /dev/null 2>&1
    systemctl restart 3proxy
    sleep 1

    if systemctl is-active --quiet 3proxy; then
        info "3proxy is running"
    else
        die "3proxy failed to start. Check: journalctl -u 3proxy -n 30"
    fi

    if ss -tlnp | grep -q ":${SOCKS_PORT}"; then
        info "Listening on port $SOCKS_PORT ✓"
    else
        warn "Port not detected in ss — verify with: ss -tlnp | grep 3proxy"
    fi

    PUBLIC_IP=$(get_public_ip)
    echo ""
    echo "───────────────────────────────────────────"
    echo "  Install complete"
    echo "  Test: curl -x socks5h://${PROXY_USER}:${PROXY_PASS}@${PUBLIC_IP}:${SOCKS_PORT} https://api.ipify.org"
    echo "───────────────────────────────────────────"
    pause
}

# ─── User Management ──────────────────────────────────────────────────────────

do_user_menu() {
    while true; do
        show_header
        echo -e "${BOLD}  [ User Management ]${NC}"
        echo ""
        echo "  Current users:"
        local users
        users=$(get_users)
        if [[ -z "$users" ]]; then
            echo "    (none)"
        else
            echo "$users" | while read -r u; do echo "    • $u"; done
        fi
        echo ""
        echo "  1) Add user"
        echo "  2) Remove user"
        echo "  3) Change password"
        echo "  4) List users"
        echo "  0) Back"
        echo ""
        read -p "  Choice: " CHOICE
        case $CHOICE in
            1) do_add_user ;;
            2) do_remove_user ;;
            3) do_change_password ;;
            4) do_list_users ;;
            0) return ;;
            *) warn "Invalid choice" ;;
        esac
    done
}

do_add_user() {
    require_installed
    echo ""
    read -p "  New username: " NEW_USER
    [[ -z "$NEW_USER" ]] && { error "Username cannot be empty"; pause; return; }

    # Check duplicate
    if get_users | grep -qx "$NEW_USER"; then
        error "User '$NEW_USER' already exists"
        pause
        return
    fi

    read -s -p "  Password: " NEW_PASS; echo ""
    [[ ${#NEW_PASS} -lt 8 ]] && { error "Password must be at least 8 characters"; pause; return; }
    read -s -p "  Confirm: " NEW_PASS2; echo ""
    [[ "$NEW_PASS" != "$NEW_PASS2" ]] && { error "Passwords do not match"; pause; return; }

    # Append new user to existing users line
    local old_users_line
    old_users_line=$(grep -oP '(?<=users ).*' "$CFG")
    local new_users_line="${old_users_line} ${NEW_USER}:CL:${NEW_PASS}"

    local port maxconn
    port=$(get_port)
    maxconn=$(get_maxconn)
    write_config "$port" "$maxconn" "$new_users_line"
    systemctl restart 3proxy

    info "User '$NEW_USER' added"
    pause
}

do_remove_user() {
    require_installed
    echo ""
    local users
    users=$(get_users)
    if [[ -z "$users" ]]; then
        error "No users configured"
        pause
        return
    fi

    echo "  Users:"
    echo "$users" | nl -w2 -s') '
    echo ""
    read -p "  Username to remove: " DEL_USER

    if ! echo "$users" | grep -qx "$DEL_USER"; then
        error "User '$DEL_USER' not found"
        pause
        return
    fi

    local old_users_line
    old_users_line=$(grep -oP '(?<=users ).*' "$CFG")

    # Remove the user:CL:pass entry for that user
    local new_users_line
    new_users_line=$(echo "$old_users_line" | sed "s/${DEL_USER}:CL:[^ ]*//g" | tr -s ' ' | sed 's/^ //;s/ $//')

    if [[ -z "$new_users_line" ]]; then
        error "Cannot remove last user — add another user first"
        pause
        return
    fi

    local port maxconn
    port=$(get_port)
    maxconn=$(get_maxconn)
    write_config "$port" "$maxconn" "$new_users_line"
    systemctl restart 3proxy

    info "User '$DEL_USER' removed"
    pause
}

do_change_password() {
    require_installed
    echo ""
    local users
    users=$(get_users)
    if [[ -z "$users" ]]; then
        error "No users configured"
        pause
        return
    fi

    echo "  Users:"
    echo "$users" | nl -w2 -s') '
    echo ""
    read -p "  Username to update: " CHG_USER

    if ! echo "$users" | grep -qx "$CHG_USER"; then
        error "User '$CHG_USER' not found"
        pause
        return
    fi

    read -s -p "  New password: " NEW_PASS; echo ""
    [[ ${#NEW_PASS} -lt 8 ]] && { error "Password must be at least 8 characters"; pause; return; }
    read -s -p "  Confirm: " NEW_PASS2; echo ""
    [[ "$NEW_PASS" != "$NEW_PASS2" ]] && { error "Passwords do not match"; pause; return; }

    local old_users_line
    old_users_line=$(grep -oP '(?<=users ).*' "$CFG")
    local new_users_line
    new_users_line=$(echo "$old_users_line" | sed "s/${CHG_USER}:CL:[^ ]*/${CHG_USER}:CL:${NEW_PASS}/g")

    local port maxconn
    port=$(get_port)
    maxconn=$(get_maxconn)
    write_config "$port" "$maxconn" "$new_users_line"
    systemctl restart 3proxy

    info "Password updated for '$CHG_USER'"
    pause
}

do_list_users() {
    require_installed
    echo ""
    echo "  Configured users:"
    get_users | while read -r u; do echo "    • $u"; done
    pause
}

# ─── Config ───────────────────────────────────────────────────────────────────

do_config_menu() {
    while true; do
        show_header
        echo -e "${BOLD}  [ Configuration ]${NC}"
        echo ""
        if [[ -f "$CFG" ]]; then
            echo "  Current port   : $(get_port)"
            echo "  Current maxconn: $(get_maxconn)"
        fi
        echo ""
        echo "  1) Change port"
        echo "  2) Change max connections"
        echo "  0) Back"
        echo ""
        read -p "  Choice: " CHOICE
        case $CHOICE in
            1) do_change_port ;;
            2) do_change_maxconn ;;
            0) return ;;
            *) warn "Invalid choice" ;;
        esac
    done
}

do_change_port() {
    require_installed
    echo ""
    local OLD_PORT
    OLD_PORT=$(get_port)
    read -p "  New port (current: $OLD_PORT): " NEW_PORT
    [[ ! "$NEW_PORT" =~ ^[0-9]+$ ]] && { error "Invalid port"; pause; return; }
    [[ "$NEW_PORT" -lt 1024 || "$NEW_PORT" -gt 65535 ]] && { error "Port must be 1024–65535"; pause; return; }

    local users_line maxconn
    users_line=$(grep -oP '(?<=users ).*' "$CFG")
    maxconn=$(get_maxconn)

    firewall_remove "$OLD_PORT"
    write_config "$NEW_PORT" "$maxconn" "$users_line"
    firewall_allow "$NEW_PORT"
    systemctl restart 3proxy

    info "Port changed: $OLD_PORT → $NEW_PORT"
    pause
}

do_change_maxconn() {
    require_installed
    echo ""
    local OLD_MC
    OLD_MC=$(get_maxconn)
    read -p "  New maxconn (current: $OLD_MC): " NEW_MC
    [[ ! "$NEW_MC" =~ ^[0-9]+$ ]] && { error "Invalid value"; pause; return; }

    local users_line port
    users_line=$(grep -oP '(?<=users ).*' "$CFG")
    port=$(get_port)
    write_config "$port" "$NEW_MC" "$users_line"
    systemctl restart 3proxy

    info "maxconn changed: $OLD_MC → $NEW_MC"
    pause
}

# ─── Logs ─────────────────────────────────────────────────────────────────────

do_log_menu() {
    while true; do
        show_header
        echo -e "${BOLD}  [ Logs ]${NC}"
        echo ""
        local log_size
        log_size=$(du -sh "$LOG" 2>/dev/null | cut -f1 || echo "0")
        echo "  Log file : $LOG"
        echo "  Log size : $log_size"
        echo ""
        echo "  1) View recent logs (last 50 lines)"
        echo "  2) Live tail (Ctrl+C to exit)"
        echo "  3) Clear log now"
        echo "  4) Setup auto-cleanup (cron)"
        echo "  5) Remove auto-cleanup"
        echo "  0) Back"
        echo ""
        read -p "  Choice: " CHOICE
        case $CHOICE in
            1) do_view_logs ;;
            2) do_tail_logs ;;
            3) do_clear_log ;;
            4) do_setup_log_cron ;;
            5) do_remove_log_cron ;;
            0) return ;;
            *) warn "Invalid choice" ;;
        esac
    done
}

do_view_logs() {
    echo ""
    if [[ -f "$LOG" ]]; then
        tail -n 50 "$LOG"
    else
        warn "Log file not found"
    fi
    pause
}

do_tail_logs() {
    echo ""
    info "Press Ctrl+C to stop"
    echo ""
    tail -f "$LOG" 2>/dev/null || warn "Log file not found"
    pause
}

do_clear_log() {
    echo ""
    read -p "  Clear log file? This cannot be undone. [y/N]: " CONFIRM
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        > "$LOG"
        info "Log cleared"
    else
        warn "Cancelled"
    fi
    pause
}

do_setup_log_cron() {
    echo ""
    echo "  Auto-cleanup options:"
    echo "  1) Keep last 5MB  (clear when log exceeds 5MB)  — recommended for NAT/small VPS"
    echo "  2) Keep last 10MB"
    echo "  3) Keep last 20MB"
    echo "  4) Custom size (MB)"
    echo ""
    read -p "  Choice: " CHOICE

    local MAX_MB
    case $CHOICE in
        1) MAX_MB=5 ;;
        2) MAX_MB=10 ;;
        3) MAX_MB=20 ;;
        4)
            read -p "  Max log size in MB: " MAX_MB
            [[ ! "$MAX_MB" =~ ^[0-9]+$ ]] && { error "Invalid size"; pause; return; }
            ;;
        *) error "Invalid choice"; pause; return ;;
    esac

    # Write a cron job that checks log size every hour and clears if over limit
    local CRON_CMD="0 * * * * [ -f ${LOG} ] && [ \$(du -m ${LOG} | cut -f1) -ge ${MAX_MB} ] && > ${LOG}"
    local CRON_MARKER="# 3proxy-log-cleanup"

    # Remove old entry if exists
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab - 2>/dev/null || true

    # Add new entry
    (crontab -l 2>/dev/null; echo "${CRON_CMD} ${CRON_MARKER}") | crontab -

    info "Auto-cleanup set: clear log when it exceeds ${MAX_MB}MB (checks hourly)"
    pause
}

do_remove_log_cron() {
    echo ""
    local CRON_MARKER="# 3proxy-log-cleanup"
    if crontab -l 2>/dev/null | grep -q "$CRON_MARKER"; then
        crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab -
        info "Auto-cleanup removed"
    else
        warn "No auto-cleanup cron job found"
    fi
    pause
}

# ─── Service ──────────────────────────────────────────────────────────────────

do_service_menu() {
    while true; do
        show_header
        echo -e "${BOLD}  [ Service Control ]${NC}"
        echo ""
        local status
        if systemctl is-active --quiet 3proxy 2>/dev/null; then
            status="${GREEN}running${NC}"
        else
            status="${RED}stopped${NC}"
        fi
        echo -e "  Status: $status"
        echo ""
        echo "  1) Start"
        echo "  2) Stop"
        echo "  3) Restart"
        echo "  4) Show status"
        echo "  0) Back"
        echo ""
        read -p "  Choice: " CHOICE
        case $CHOICE in
            1) systemctl start 3proxy && info "Started" || error "Failed"; pause ;;
            2) systemctl stop 3proxy && info "Stopped" || error "Failed"; pause ;;
            3) systemctl restart 3proxy && info "Restarted" || error "Failed"; pause ;;
            4) echo ""; systemctl status 3proxy; pause ;;
            0) return ;;
            *) warn "Invalid choice" ;;
        esac
    done
}

# ─── Diagnostics ──────────────────────────────────────────────────────────────

do_diagnostics() {
    require_installed
    show_header
    echo -e "${BOLD}  [ Diagnostics ]${NC}"
    echo ""

    local port
    port=$(get_port)
    local public_ip
    public_ip=$(get_public_ip)
    local users
    users=$(get_users | head -1)  # use first user for test

    echo "  Public IP : $public_ip"
    echo "  Port      : $port"
    echo ""

    # Port listening check
    if ss -tlnp | grep -q ":${port}"; then
        echo -e "  Port $port  : ${GREEN}listening ✓${NC}"
    else
        echo -e "  Port $port  : ${RED}NOT listening ✗${NC}"
    fi

    # Service check
    if systemctl is-active --quiet 3proxy; then
        echo -e "  Service   : ${GREEN}active ✓${NC}"
    else
        echo -e "  Service   : ${RED}inactive ✗${NC}"
    fi

    # Active connections
    local conn_count
    conn_count=$(ss -tnp | grep -c "3proxy" 2>/dev/null || echo 0)
    echo "  Active connections: $conn_count"

    echo ""
    if [[ -n "$users" ]]; then
        read -p "  Run connectivity test using user '$users'? [y/N]: " DO_TEST
        if [[ "$DO_TEST" == "y" || "$DO_TEST" == "Y" ]]; then
            local pass
            pass=$(grep -oP "(?<=${users}:CL:)[^ ]+" "$CFG" 2>/dev/null || echo "")
            if [[ -n "$pass" ]]; then
                echo ""
                info "Testing SOCKS5 via curl..."
                RESULT=$(curl -s --max-time 10 -x "socks5h://${users}:${pass}@127.0.0.1:${port}" https://api.ipify.org 2>&1 || echo "FAILED")
                if [[ "$RESULT" == "FAILED" || -z "$RESULT" ]]; then
                    echo -e "  Result: ${RED}FAILED ✗${NC}"
                else
                    echo -e "  Result: ${GREEN}OK ✓${NC} — exit IP: $RESULT"
                fi
            else
                warn "Could not extract password for test"
            fi
        fi
    fi

    echo ""
    echo "  Test command (from external machine):"
    echo "  curl -x socks5h://<user>:<pass>@${public_ip}:${port} https://api.ipify.org"
    pause
}

# ─── Uninstall ────────────────────────────────────────────────────────────────

do_uninstall() {
    show_header
    echo -e "${BOLD}  [ Uninstall ]${NC}"
    echo ""
    warn "This will remove 3proxy, its config, and logs."
    read -p "  Type 'yes' to confirm: " CONFIRM
    [[ "$CONFIRM" != "yes" ]] && { warn "Cancelled"; pause; return; }

    local port
    port=$(get_port 2>/dev/null || echo "")

    systemctl stop 3proxy 2>/dev/null || true
    systemctl disable 3proxy 2>/dev/null || true

    apt-get remove -y 3proxy > /dev/null 2>&1 || true
    apt-get purge -y 3proxy > /dev/null 2>&1 || true

    rm -f "$CFG" "$LOG"
    rm -rf /etc/3proxy
    rm -f /etc/systemd/system/3proxy.service.d/override.conf
    rmdir /etc/systemd/system/3proxy.service.d 2>/dev/null || true
    systemctl daemon-reload

    # Remove cron
    crontab -l 2>/dev/null | grep -v "# 3proxy-log-cleanup" | crontab - 2>/dev/null || true

    [[ -n "$port" ]] && firewall_remove "$port" || true

    info "3proxy fully removed"
    pause
}

# ─── Main Menu ────────────────────────────────────────────────────────────────

main_menu() {
    require_root
    while true; do
        show_header
        show_status_bar
        echo "  1) Install"
        echo "  2) User management"
        echo "  3) Configuration"
        echo "  4) Logs"
        echo "  5) Service control"
        echo "  6) Diagnostics"
        echo "  7) Uninstall"
        echo "  0) Exit"
        echo ""
        read -p "  Choice: " CHOICE
        echo ""
        case $CHOICE in
            1) do_install ;;
            2) do_user_menu ;;
            3) do_config_menu ;;
            4) do_log_menu ;;
            5) do_service_menu ;;
            6) do_diagnostics ;;
            7) do_uninstall ;;
            0) echo "Bye."; exit 0 ;;
            *) warn "Invalid choice"; sleep 1 ;;
        esac
    done
}

main_menu
