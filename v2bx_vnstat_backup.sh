#!/bin/bash

# ============================================
# V2bX & vnstat Backup/Restore Script
# Version: 2.1.1
# Supports: Debian, Ubuntu, CentOS, RHEL, Alpine
# ============================================

# Script version
SCRIPT_VERSION="2.1.1"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
V2BX_PATH="/etc/V2bX"
VNSTAT_PATH="/var/lib/vnstat"
BACKUP_DIR="/root"
SCRIPT_NAME=$(basename "$0")

# Global variables for dashboard
OS=""
VER=""
PKG_MANAGER=""
V2BX_VERSION=""
VNSTAT_VERSION=""
V2BX_RUNNING=false
VNSTAT_RUNNING=false
LAST_BACKUP=""
BACKUP_COUNT=0

# ============================================
# Utility Functions
# ============================================

print_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}     V2bX & vnstat Backup/Restore Tool v${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root (use sudo)"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi
}

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        INSTALL_CMD="apt update -y && apt install -y"
        REMOVE_CMD="apt remove -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
        REMOVE_CMD="dnf remove -y"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        INSTALL_CMD="yum install -y"
        REMOVE_CMD="yum remove -y"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        INSTALL_CMD="apk add --no-cache"
        REMOVE_CMD="apk del"
    else
        print_error "No supported package manager found"
        exit 1
    fi
}

install_dependencies() {
    local deps=("jq" "tar" "gzip")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_status "Installing missing dependencies: ${missing_deps[*]}"
        eval "$INSTALL_CMD ${missing_deps[*]}" || {
            print_error "Failed to install dependencies"
            exit 1
        }
    fi
}

get_v2bx_version() {
    if [ -f "$V2BX_PATH/V2bX" ]; then
        V2BX_VERSION=$("$V2BX_PATH/V2bX" -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -z "$V2BX_VERSION" ] && V2BX_VERSION="installed"
    else
        V2BX_VERSION="-"
    fi
}

get_vnstat_version() {
    if command -v vnstat >/dev/null 2>&1; then
        VNSTAT_VERSION=$(vnstat --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        [ -z "$VNSTAT_VERSION" ] && VNSTAT_VERSION="installed"
    else
        VNSTAT_VERSION="-"
    fi
}

check_services_status() {
    if pgrep -f "V2bX" >/dev/null; then
        V2BX_RUNNING=true
    else
        V2BX_RUNNING=false
    fi
    
    if pgrep -f "vnstat" >/dev/null; then
        VNSTAT_RUNNING=true
    else
        VNSTAT_RUNNING=false
    fi
}

get_backup_stats() {
    local backups=($(ls -t "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null))
    BACKUP_COUNT=${#backups[@]}
    
    if [ $BACKUP_COUNT -gt 0 ]; then
        local latest="${backups[0]}"
        local domain=$(basename "$latest" | sed 's/^v2bx_vnstat_//; s/_[0-9]\{8\}-[0-9]\{6\}\.tar\.gz$//')
        local date=$(stat -c %y "$latest" 2>/dev/null | cut -d. -f1 | cut -d' ' -f1 || stat -f %Sm -t "%Y-%m-%d" "$latest" 2>/dev/null)
        LAST_BACKUP="${domain} (${date})"
    else
        LAST_BACKUP="none"
    fi
}

check_services() {
    if [ ! -d "$V2BX_PATH" ]; then
        V2BX_INSTALLED=false
    else
        V2BX_INSTALLED=true
    fi
    
    if [ ! -d "$VNSTAT_PATH" ]; then
        VNSTAT_INSTALLED=false
    else
        VNSTAT_INSTALLED=true
    fi
}

# ============================================
# Compact Dashboard
# ============================================

show_dashboard() {
    get_v2bx_version
    get_vnstat_version
    check_services_status
    get_backup_stats
    
    clear
    
    # Elegant header
    echo ""
    echo -e "    ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "    ${WHITE}                     V2bX & vnstat Backup/Restore Tool${NC}"
    echo -e "    ${CYAN}                            v${SCRIPT_VERSION}${NC}"
    echo -e "    ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # System Info
    echo -e "    ${BLUE}▸${NC} ${CYAN}System:${NC}      ${WHITE}$OS $VER${NC}"
    echo -e "    ${BLUE}▸${NC} ${CYAN}Package Mgr:${NC} ${WHITE}$PKG_MANAGER${NC}"
    echo -e "    ${BLUE}▸${NC} ${CYAN}Kernel:${NC}      ${WHITE}$(uname -r | cut -d'-' -f1)${NC}"
    echo -e "    ${BLUE}▸${NC} ${CYAN}Uptime:${NC}      ${WHITE}$(uptime -p | sed 's/up //' | sed 's/ hours/H/g' | sed 's/ hour/H/g' | sed 's/ minutes/M/g' | sed 's/ minute/M/g')${NC}"
    echo ""
    
    # Services
    echo -e "    ${GREEN}▸${NC} ${CYAN}Services:${NC}"
    if [ "$V2BX_INSTALLED" = true ]; then
        if [ "$V2BX_RUNNING" = true ]; then
            echo -e "      ${GREEN}●${NC} V2bX ${WHITE}v$V2BX_VERSION${NC} - ${GREEN}Running${NC}  ${BLUE}[${WHITE}$V2BX_PATH${BLUE}]${NC}"
        else
            echo -e "      ${RED}●${NC} V2bX ${WHITE}v$V2BX_VERSION${NC} - ${RED}Stopped${NC}  ${BLUE}[${WHITE}$V2BX_PATH${BLUE}]${NC}"
        fi
    else
        echo -e "      ${RED}●${NC} V2bX - ${RED}Not Installed${NC}"
    fi
    
    if command -v vnstat >/dev/null 2>&1; then
        if [ "$VNSTAT_RUNNING" = true ]; then
            echo -e "      ${GREEN}●${NC} vnstat ${WHITE}v$VNSTAT_VERSION${NC} - ${GREEN}Running${NC}  ${BLUE}[${WHITE}$VNSTAT_PATH${BLUE}]${NC}"
        else
            echo -e "      ${RED}●${NC} vnstat ${WHITE}v$VNSTAT_VERSION${NC} - ${RED}Stopped${NC}  ${BLUE}[${WHITE}$VNSTAT_PATH${BLUE}]${NC}"
        fi
    else
        echo -e "      ${RED}●${NC} vnstat - ${RED}Not Installed${NC}"
    fi
    echo ""
    
    # Backup Info
    echo -e "    ${YELLOW}▸${NC} ${CYAN}Backups:${NC}      ${WHITE}$BACKUP_COUNT${NC} total, latest: ${WHITE}$LAST_BACKUP${NC}"
    echo -e "    ${YELLOW}▸${NC} ${CYAN}Directory:${NC}    ${WHITE}$BACKUP_DIR${NC}"
    echo ""
    echo -e "    ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}


# ============================================
# Menu
# ============================================

show_menu() {
    echo -e "    ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "    ${MAGENTA}                           MAIN MENU${NC}"
    echo -e "    ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "      ${GREEN}1.${NC} 🔄  Create backup          ${YELLOW}2.${NC} 📥  Restore backup"
    echo -e "      ${BLUE}3.${NC} 📋  List backups          4. 🧹  Cleanup old backups"
    echo -e "      5. ℹ️   Show backup info       6. ⚡  Install V2bX"
    echo -e "      7. 📊  Install vnstat         8. 🔧  Start/restart services"
    echo -e "      ${RED}9.${NC} 🚪  Exit"
    echo ""
    echo -e "    ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "    ${CYAN}➤${NC} ${WHITE}Choose an option:${NC} \c"
}

# ============================================
# Installation Functions
# ============================================

install_v2bx() {
    print_status "Installing V2bX..."
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            return 1
            ;;
    esac
    
    print_status "Fetching latest V2bX version..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/InazumaV/V2bX/releases/latest | jq -r .tag_name)
    
    if [ -z "$LATEST_VERSION" ]; then
        print_warning "Failed to fetch latest version, using latest release"
        DOWNLOAD_URL="https://github.com/InazumaV/V2bX/releases/latest/download/V2bX-linux-${ARCH}.zip"
    else
        DOWNLOAD_URL="https://github.com/InazumaV/V2bX/releases/download/${LATEST_VERSION}/V2bX-linux-${ARCH}.zip"
    fi
    
    print_status "Downloading V2bX..."
    curl -L -o /tmp/V2bX.zip "$DOWNLOAD_URL" || {
        print_error "Failed to download V2bX"
        return 1
    }
    
    if ! command -v unzip >/dev/null 2>&1; then
        print_status "Installing unzip..."
        eval "$INSTALL_CMD unzip" || {
            print_error "Failed to install unzip"
            return 1
        }
    fi
    
    unzip -o /tmp/V2bX.zip -d /tmp/V2bX_extract || {
        print_error "Failed to extract V2bX"
        return 1
    }
    
    mkdir -p "$V2BX_PATH"
    cp -r /tmp/V2bX_extract/* "$V2BX_PATH/" 2>/dev/null || true
    
    if [ -f "$V2BX_PATH/V2bX" ]; then
        chmod +x "$V2BX_PATH/V2bX"
    elif [ -f "$V2BX_PATH/V2bX-linux-${ARCH}" ]; then
        mv "$V2BX_PATH/V2bX-linux-${ARCH}" "$V2BX_PATH/V2bX"
        chmod +x "$V2BX_PATH/V2bX"
    fi
    
    create_v2bx_service
    
    rm -rf /tmp/V2bX.zip /tmp/V2bX_extract
    
    print_success "V2bX installed successfully"
    V2BX_INSTALLED=true
}

create_v2bx_service() {
    if command -v systemctl >/dev/null 2>&1; then
        print_status "Creating systemd service..."
        cat > /etc/systemd/system/V2bX.service << EOF
[Unit]
Description=V2bX Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$V2BX_PATH/V2bX server
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable V2bX.service
        
    elif command -v rc-update >/dev/null 2>&1; then
        print_status "Creating OpenRC service..."
        cat > /etc/init.d/V2bX << EOF
#!/sbin/openrc-run

name="V2bX"
description="V2bX Service"
command="$V2BX_PATH/V2bX"
command_args="server"
command_user="root"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background=true

depend() {
    need net
}
EOF
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
    fi
}

install_vnstat() {
    print_status "Installing vnstat..."
    
    case $PKG_MANAGER in
        apt)
            eval "$INSTALL_CMD vnstat"
            ;;
        yum|dnf)
            eval "$INSTALL_CMD epel-release" || true
            eval "$INSTALL_CMD vnstat"
            ;;
        apk)
            eval "$INSTALL_CMD vnstat"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        mkdir -p "$VNSTAT_PATH"
        
        if command -v vnstat >/dev/null 2>&1; then
            for interface in $(ls /sys/class/net/ | grep -v lo); do
                vnstat -i $interface --add 2>/dev/null || true
            done
        fi
        
        if command -v systemctl >/dev/null 2>&1; then
            systemctl start vnstat
            systemctl enable vnstat
        elif command -v rc-service >/dev/null 2>&1; then
            rc-service vnstat start
            rc-update add vnstat default
        elif command -v service >/dev/null 2>&1; then
            service vnstat start
        fi
        
        print_success "vnstat installed successfully"
        VNSTAT_INSTALLED=true
    else
        print_error "Failed to install vnstat"
        return 1
    fi
}

start_v2bx() {
    print_status "Starting V2bX..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start V2bX.service
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service V2bX start
    elif [ -f "$V2BX_PATH/V2bX" ]; then
        nohup "$V2BX_PATH/V2bX" server > /var/log/V2bX.log 2>&1 &
    fi
    
    sleep 2
    if pgrep -f "V2bX" >/dev/null; then
        print_success "V2bX started"
    else
        print_warning "V2bX may not be running"
    fi
}

stop_v2bx() {
    print_status "Stopping V2bX..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop V2bX.service
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service V2bX stop
    else
        pkill -f "V2bX" || true
    fi
}

restart_v2bx() {
    print_status "Restarting V2bX..."
    stop_v2bx
    sleep 2
    start_v2bx
}

start_vnstat() {
    print_status "Starting vnstat..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start vnstat
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service vnstat start
    elif command -v service >/dev/null 2>&1; then
        service vnstat start
    fi
}

stop_vnstat() {
    print_status "Stopping vnstat..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop vnstat
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service vnstat stop
    elif command -v service >/dev/null 2>&1; then
        service vnstat stop
    fi
}

restart_vnstat() {
    print_status "Restarting vnstat..."
    stop_vnstat
    sleep 2
    start_vnstat
}

# ============================================
# Backup Functions
# ============================================

get_domain() {
    local config_file="$V2BX_PATH/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo "unknown"
        return
    fi
    
    local domain=$(jq -r '.Nodes[].CertConfig | select(.CertDomain != null and .CertDomain != "example.com") | .CertDomain' "$config_file" 2>/dev/null | head -n 1)
    
    if [ -z "$domain" ] || [ "$domain" = "null" ]; then
        echo "unknown"
    else
        echo "$domain"
    fi
}

backup_v2bx() {
    local backup_path="$1"
    print_status "Backing up V2bX..."
    
    if [ -d "$V2BX_PATH" ]; then
        tar -rf "$backup_path" "$V2BX_PATH" 2>/dev/null || {
            print_error "Failed to backup V2bX"
            return 1
        }
        print_success "V2bX backed up"
    else
        print_warning "V2bX not found"
        return 1
    fi
}

backup_vnstat() {
    local backup_path="$1"
    
    if [ -d "$VNSTAT_PATH" ]; then
        print_status "Backing up vnstat..."
        tar -rf "$backup_path" "$VNSTAT_PATH" 2>/dev/null || {
            print_error "Failed to backup vnstat"
            return 1
        }
        print_success "vnstat backed up"
    else
        print_warning "vnstat not found, skipping"
    fi
}

create_backup() {
    local domain=$(get_domain)
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$BACKUP_DIR/v2bx_vnstat_${domain}_${timestamp}.tar.gz"
    local temp_file="/tmp/v2bx_backup_${timestamp}.tar"
    
    print_status "Creating backup: $(basename "$backup_file")"
    
    touch "$temp_file"
    
    backup_v2bx "$temp_file" || {
        rm -f "$temp_file"
        return 1
    }
    
    backup_vnstat "$temp_file"
    
    if [ -s "$temp_file" ]; then
        gzip -c "$temp_file" > "$backup_file"
        rm -f "$temp_file"
        local size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup created: $(basename "$backup_file") (${size})"
    else
        rm -f "$temp_file"
        print_error "Backup failed"
        return 1
    fi
}

list_backups() {
    print_status "Available backups:"
    echo ""
    
    local backups=($(ls -t "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found"
        return
    fi
    
    printf "  %-4s %-35s %-10s %-20s\n" "ID" "Domain" "Size" "Date"
    echo "  ------------------------------------------------------------------------"
    
    local id=1
    for backup in "${backups[@]}"; do
        local domain=$(basename "$backup" | sed 's/^v2bx_vnstat_//; s/_[0-9]\{8\}-[0-9]\{6\}\.tar\.gz$//')
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" 2>/dev/null | cut -d. -f1 | cut -d' ' -f1 || stat -f %Sm -t "%Y-%m-%d" "$backup" 2>/dev/null)
        printf "  %-4s %-35s %-10s %-20s\n" "$id" "$domain" "$size" "$date"
        ((id++))
    done
    echo ""
}

# ============================================
# Restore Functions
# ============================================

ensure_v2bx_installed() {
    if [ "$V2BX_INSTALLED" = false ]; then
        print_warning "V2bX is not installed"
        read -p "Install V2bX before restoring? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_v2bx
            if [ "$V2BX_INSTALLED" = false ]; then
                print_error "Failed to install V2bX"
                return 1
            fi
        else
            print_error "V2bX required for restore"
            return 1
        fi
    fi
    return 0
}

ensure_vnstat_installed() {
    if [ "$VNSTAT_INSTALLED" = false ]; then
        print_warning "vnstat is not installed"
        read -p "Install vnstat before restoring? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_vnstat
        else
            print_warning "Skipping vnstat restore"
            return 1
        fi
    fi
    return 0
}

restore_v2bx() {
    local temp_dir="$1"
    
    print_status "Restoring V2bX..."
    stop_v2bx
    
    if [ -d "$V2BX_PATH" ]; then
        local backup_v2bx="$V2BX_PATH.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$V2BX_PATH" "$backup_v2bx"
        print_status "Current V2bX backed up to $backup_v2bx"
    fi
    
    if [ -d "$temp_dir/etc/V2bX" ]; then
        cp -r "$temp_dir/etc/V2bX" "$V2BX_PATH"
        print_success "V2bX restored"
        restart_v2bx
    else
        print_error "V2bX not found in backup"
        return 1
    fi
}

restore_vnstat() {
    local temp_dir="$1"
    
    if [ -d "$temp_dir/var/lib/vnstat" ]; then
        print_status "Restoring vnstat..."
        stop_vnstat
        
        if [ -d "$VNSTAT_PATH" ]; then
            local backup_vnstat="$VNSTAT_PATH.backup.$(date +%Y%m%d_%H%M%S)"
            mv "$VNSTAT_PATH" "$backup_vnstat"
            print_status "Current vnstat backed up to $backup_vnstat"
        fi
        
        cp -r "$temp_dir/var/lib/vnstat" "$VNSTAT_PATH"
        
        if getent passwd vnstat >/dev/null 2>&1; then
            chown -R vnstat:vnstat "$VNSTAT_PATH" 2>/dev/null || true
        fi
        
        start_vnstat
        print_success "vnstat restored"
    else
        print_warning "vnstat not found in backup, skipping"
    fi
}

restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi
    
    print_status "Restoring from: $(basename "$backup_file")"
    
    ensure_v2bx_installed || return 1
    ensure_vnstat_installed
    
    local temp_dir=$(mktemp -d)
    
    tar -xzf "$backup_file" -C "$temp_dir" || {
        print_error "Failed to extract backup"
        rm -rf "$temp_dir"
        return 1
    }
    
    echo ""
    print_warning "This will replace your current V2bX configuration"
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Restore cancelled"
        rm -rf "$temp_dir"
        return
    fi
    
    restore_v2bx "$temp_dir"
    restore_vnstat "$temp_dir"
    
    rm -rf "$temp_dir"
    
    print_success "Restore completed"
}

interactive_restore() {
    list_backups
    
    local backups=($(ls -t "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        return
    fi
    
    echo ""
    read -p "Enter backup ID to restore (0 to cancel): " backup_id
    
    if [ "$backup_id" -eq 0 ] 2>/dev/null; then
        print_status "Restore cancelled"
        return
    fi
    
    if [ "$backup_id" -ge 1 ] && [ "$backup_id" -le ${#backups[@]} ] 2>/dev/null; then
        restore_backup "${backups[$((backup_id-1))]}"
    else
        print_error "Invalid backup ID"
    fi
}

# ============================================
# Maintenance Functions
# ============================================

cleanup_old_backups() {
    local days="${1:-30}"
    
    print_status "Cleaning up backups older than $days days"
    
    local deleted=$(find "$BACKUP_DIR" -name "v2bx_vnstat_*.tar.gz" -type f -mtime +$days -delete -print 2>/dev/null | wc -l)
    
    print_success "Deleted $deleted old backup(s)"
}

show_backup_info() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found"
        return 1
    fi
    
    echo ""
    print_status "Backup: $(basename "$backup_file")"
    echo -e "  ${CYAN}Size:${NC} $(du -h "$backup_file" | cut -f1)"
    echo -e "  ${CYAN}Created:${NC} $(stat -c %y "$backup_file" 2>/dev/null | cut -d. -f1 || stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null)"
    echo ""
    print_status "Contents:"
    tar -tzf "$backup_file" | head -15 | sed 's/^/  /'
    local total=$(tar -tzf "$backup_file" | wc -l)
    if [ $total -gt 15 ]; then
        echo "  ... and $((total - 15)) more files"
    fi
    echo ""
}

# ============================================
# Service Management Menu
# ============================================

manage_services_menu() {
    while true; do
        clear
        show_dashboard
        
        echo -e "${WHITE}SERVICE MANAGEMENT${NC}"
        echo ""
        echo "  1. Start V2bX"
        echo "  2. Stop V2bX"
        echo "  3. Restart V2bX"
        echo "  4. Start vnstat"
        echo "  5. Stop vnstat"
        echo "  6. Restart vnstat"
        echo "  7. Back to main menu"
        echo ""
        
        read -p "Choose option [1-7]: " svc_choice
        
        case $svc_choice in
            1) start_v2bx ;;
            2) stop_v2bx ;;
            3) restart_v2bx ;;
            4) start_vnstat ;;
            5) stop_vnstat ;;
            6) restart_vnstat ;;
            7) return ;;
            *) print_error "Invalid option" ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# ============================================
# Main Function
# ============================================

main() {
    check_root
    detect_os
    detect_package_manager
    install_dependencies
    check_services
    
    while true; do
        show_dashboard
        show_menu
        read -p "Choose option [1-9]: " choice
        
        case $choice in
            1)
                create_backup
                ;;
            2)
                interactive_restore
                ;;
            3)
                list_backups
                ;;
            4)
                read -p "Keep backups from last how many days? [30]: " days
                days=${days:-30}
                cleanup_old_backups "$days"
                ;;
            5)
                list_backups
                if [ $BACKUP_COUNT -gt 0 ]; then
                    echo ""
                    read -p "Enter backup ID to inspect: " backup_id
                    local backups=($(ls -t "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null))
                    if [ "$backup_id" -ge 1 ] 2>/dev/null && [ "$backup_id" -le ${#backups[@]} ] 2>/dev/null; then
                        show_backup_info "${backups[$((backup_id-1))]}"
                    else
                        print_error "Invalid backup ID"
                    fi
                fi
                ;;
            6)
                if [ "$V2BX_INSTALLED" = false ]; then
                    install_v2bx
                else
                    print_warning "V2bX already installed"
                fi
                ;;
            7)
                if [ "$VNSTAT_INSTALLED" = false ]; then
                    install_vnstat
                else
                    print_warning "vnstat already installed"
                fi
                ;;
            8)
                manage_services_menu
                ;;
            9)
                print_success "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Handle command line arguments
case "$1" in
    backup)
        check_root
        detect_os
        detect_package_manager
        install_dependencies
        check_services
        create_backup
        ;;
    restore)
        check_root
        detect_os
        detect_package_manager
        install_dependencies
        check_services
        if [ -n "$2" ]; then
            restore_backup "$2"
        else
            interactive_restore
        fi
        ;;
    list)
        check_root
        list_backups
        ;;
    cleanup)
        check_root
        days="${2:-30}"
        cleanup_old_backups "$days"
        ;;
    info)
        check_root
        if [ -n "$2" ]; then
            show_backup_info "$2"
        else
            print_error "Usage: $SCRIPT_NAME info <backup_file>"
        fi
        ;;
    status)
        check_root
        detect_os
        detect_package_manager
        check_services
        show_dashboard
        ;;
    install-v2bx)
        check_root
        detect_os
        detect_package_manager
        install_dependencies
        install_v2bx
        ;;
    install-vnstat)
        check_root
        detect_os
        detect_package_manager
        install_dependencies
        install_vnstat
        ;;
    version)
        echo "V2bX Backup/Restore Script v$SCRIPT_VERSION"
        ;;
    *)
        main
        ;;
esac
