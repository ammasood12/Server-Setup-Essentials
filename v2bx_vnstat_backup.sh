#!/bin/bash

# ============================================
# V2bX & vnstat Backup/Restore Script
# Version: 2.2.0
# Supports: Debian, Ubuntu, CentOS, RHEL, Alpine
# ============================================

SCRIPT_VERSION="2.2.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration
V2BX_PATH="/etc/V2bX"
VNSTAT_PATH="/var/lib/vnstat"
BACKUP_DIR="/root"

# Global variables
OS=""
PKG_MANAGER=""
V2BX_INSTALLED=false
VNSTAT_INSTALLED=false
V2BX_RUNNING=false
VNSTAT_RUNNING=false

# ============================================
# Utility Functions
# ============================================

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[+]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi
    
    # Detect package manager
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        INSTALL_CMD="apt update -y && apt install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        INSTALL_CMD="yum install -y"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        INSTALL_CMD="apk add --no-cache"
    fi
}

check_installation() {
    # Check V2bX - multiple methods
    V2BX_INSTALLED=false
    
    # Method 1: Check if process is running
    if pgrep -f "V2bX" >/dev/null; then
        V2BX_INSTALLED=true
        V2BX_RUNNING=true
    fi
    
    # Method 2: Check binary at standard location
    if [ -f "$V2BX_PATH/V2bX" ] || [ -f "$V2BX_PATH/v2bx" ] || [ -f "/usr/local/bin/V2bX" ] || [ -f "/usr/bin/V2bX" ]; then
        V2BX_INSTALLED=true
    fi
    
    # Method 3: Check if config exists (strong indicator)
    if [ -f "$V2BX_PATH/config.json" ]; then
        V2BX_INSTALLED=true
    fi
    
    # Check vnstat
    if command -v vnstat >/dev/null 2>&1; then
        VNSTAT_INSTALLED=true
        if pgrep -f "vnstat" >/dev/null; then
            VNSTAT_RUNNING=true
        fi
    fi
}

install_dependencies() {
    local deps=("jq" "tar" "gzip" "curl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_status "Installing dependencies: ${missing[*]}"
        eval "$INSTALL_CMD ${missing[*]}" || {
            print_error "Failed to install dependencies"
            exit 1
        }
    fi
}

# ============================================
# Installation Functions
# ============================================

install_v2bx() {
    print_status "Installing V2bX..."
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) print_error "Unsupported architecture: $ARCH"; return 1 ;;
    esac
    
    # Install unzip if needed
    if ! command -v unzip >/dev/null 2>&1; then
        eval "$INSTALL_CMD unzip"
    fi
    
    # Get latest version
    print_status "Fetching latest version..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/InazumaV/V2bX/releases/latest | jq -r .tag_name)
    DOWNLOAD_URL="https://github.com/InazumaV/V2bX/releases/download/${LATEST_VERSION}/V2bX-linux-${ARCH}.zip"
    
    # Download and install
    print_status "Downloading V2bX..."
    curl -L -o /tmp/V2bX.zip "$DOWNLOAD_URL" || { print_error "Download failed"; return 1; }
    
    unzip -o /tmp/V2bX.zip -d /tmp/V2bX_extract
    mkdir -p "$V2BX_PATH"
    cp -r /tmp/V2bX_extract/* "$V2BX_PATH/"
    chmod +x "$V2BX_PATH/V2bX"
    
    # Create service
    if command -v systemctl >/dev/null 2>&1; then
        cat > /etc/systemd/system/V2bX.service << EOF
[Unit]
Description=V2bX Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$V2BX_PATH/V2bX server
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable V2bX
        systemctl start V2bX
        
    elif command -v rc-update >/dev/null 2>&1; then
        cat > /etc/init.d/V2bX << 'EOF'
#!/sbin/openrc-run
name="V2bX"
command="/etc/V2bX/V2bX"
command_args="server"
pidfile="/run/${RC_SVCNAME}.pid"
command_background=true
depend() { need net; }
EOF
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
        rc-service V2bX start
    fi
    
    rm -rf /tmp/V2bX.zip /tmp/V2bX_extract
    print_success "V2bX installed successfully"
    V2BX_INSTALLED=true
    V2BX_RUNNING=true
}

install_vnstat() {
    print_status "Installing vnstat..."
    
    case $PKG_MANAGER in
        apt)
            apt update -y && apt install -y vnstat
            ;;
        apk)
            apk add --no-cache vnstat
            ;;
        yum|dnf)
            yum install -y epel-release && yum install -y vnstat
            ;;
    esac
    
    # Create database directory
    mkdir -p "$VNSTAT_PATH"
    
    # Initialize interfaces
    for interface in $(ls /sys/class/net/ | grep -v lo); do
        vnstat -i $interface --add 2>/dev/null || true
    done
    
    # Start service
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start vnstat
        systemctl enable vnstat
    elif command -v rc-update >/dev/null 2>&1; then
        rc-service vnstatd start
        rc-update add vnstatd default
    fi
    
    # Fix permissions
    if getent passwd vnstat >/dev/null 2>&1; then
        chown -R vnstat:vnstat "$VNSTAT_PATH"
    fi
    
    print_success "vnstat installed successfully"
    VNSTAT_INSTALLED=true
    VNSTAT_RUNNING=true
}

# ============================================
# Service Management
# ============================================

start_v2bx() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start V2bX
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service V2bX start
    fi
    print_success "V2bX started"
}

stop_v2bx() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop V2bX
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service V2bX stop
    fi
    print_success "V2bX stopped"
}

restart_v2bx() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart V2bX
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service V2bX restart
    fi
    print_success "V2bX restarted"
}

start_vnstat() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start vnstat
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service vnstatd start
    fi
    print_success "vnstat started"
}

stop_vnstat() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop vnstat
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service vnstatd stop
    fi
    print_success "vnstat stopped"
}

restart_vnstat() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart vnstat
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service vnstatd restart
    fi
    print_success "vnstat restarted"
}

# ============================================
# Backup Functions
# ============================================

get_domain() {
    if [ ! -f "$V2BX_PATH/config.json" ]; then
        echo "unknown"
        return
    fi
    domain=$(jq -r '.Nodes[].CertConfig | select(.CertDomain != null and .CertDomain != "example.com") | .CertDomain' "$V2BX_PATH/config.json" 2>/dev/null | head -n 1)
    [ -z "$domain" ] || [ "$domain" = "null" ] && echo "unknown" || echo "$domain"
}

create_backup() {
    if [ "$V2BX_INSTALLED" = false ]; then
        print_error "V2bX is not installed. Please install it first (Option 5)"
        return 1
    fi
    
    domain=$(get_domain)
    timestamp=$(date +%Y%m%d-%H%M%S)
    backup_file="$BACKUP_DIR/v2bx_vnstat_${domain}_${timestamp}.tar.gz"
    
    print_status "Creating backup..."
    
    if [ "$VNSTAT_INSTALLED" = true ]; then
        tar -czf "$backup_file" "$V2BX_PATH" "$VNSTAT_PATH" 2>/dev/null
    else
        tar -czf "$backup_file" "$V2BX_PATH" 2>/dev/null
    fi
    
    if [ $? -eq 0 ] && [ -f "$backup_file" ]; then
        size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup created: $(basename "$backup_file") ($size)"
    else
        print_error "Backup failed"
    fi
}

list_backups() {
    print_status "Available backups:"
    echo ""
    
    backups=$(ls -t "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null)
    
    if [ -z "$backups" ]; then
        print_warning "No backups found"
        return
    fi
    
    printf "  %-3s %-45s %-10s %-12s\n" "ID" "Domain" "Size" "Date"
    echo "  ---------------------------------------------------------------"
    
    id=1
    for backup in $backups; do
        domain=$(basename "$backup" | sed 's/^v2bx_vnstat_//; s/_[0-9]\{8\}-[0-9]\{6\}\.tar\.gz$//')
        size=$(du -h "$backup" | cut -f1)
        date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1)
        printf "  %-3s %-45s %-10s %-12s\n" "$id" "${domain:0:45}" "$size" "$date"
        id=$((id + 1))
    done
    echo ""
}

restore_backup() {
    if [ "$V2BX_INSTALLED" = false ]; then
        print_warning "V2bX is not installed"
        read -p "Install V2bX before restoring? (y/N): " install_v2bx_confirm
        if [[ "$install_v2bx_confirm" =~ ^[Yy]$ ]]; then
            install_v2bx
        else
            print_error "Cannot restore without V2bX"
            return 1
        fi
    fi
    
    list_backups
    
    backups=($(ls -t "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null))
    if [ ${#backups[@]} -eq 0 ]; then
        return
    fi
    
    echo ""
    read -p " Enter backup ID to restore (0 to cancel): " backup_id
    
    if [ "$backup_id" -eq 0 ] 2>/dev/null; then
        print_status "Restore cancelled"
        return
    fi
    
    if [ "$backup_id" -ge 1 ] && [ "$backup_id" -le ${#backups[@]} ] 2>/dev/null; then
        selected="${backups[$((backup_id-1))]}"
        print_status "Restoring from: $(basename "$selected")"
        
        echo ""
        print_warning "This will replace your current configuration"
        read -p " Continue? (y/N): " confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # Stop services
            stop_v2bx
            stop_vnstat
            
            # Backup current
            [ -d "$V2BX_PATH" ] && mv "$V2BX_PATH" "${V2BX_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
            [ -d "$VNSTAT_PATH" ] && mv "$VNSTAT_PATH" "${VNSTAT_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Extract backup
            tar -xzf "$selected" -C /
            
            # Fix permissions
            if getent passwd vnstat >/dev/null 2>&1; then
                chown -R vnstat:vnstat "$VNSTAT_PATH" 2>/dev/null
            fi
            
            # Restart services
            start_vnstat
            start_v2bx
            
            print_success "Restore completed"
        else
            print_status "Restore cancelled"
        fi
    else
        print_error "Invalid backup ID"
    fi
}

cleanup_backups() {
    read -p " Keep backups from last how many days? [30]: " days
    days=${days:-30}
    
    print_status "Cleaning up backups older than $days days"
    deleted=$(find "$BACKUP_DIR" -name "v2bx_vnstat_*.tar.gz" -type f -mtime +$days -delete -print 2>/dev/null | wc -l)
    print_success "Deleted $deleted old backup(s)"
}

# ============================================
# Dashboard
# ============================================

show_dashboard() {
    clear
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}     V2bX & vnstat Backup/Restore Tool v${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${BLUE}System:${NC} $OS ($PKG_MANAGER) | $(uname -r)"
    echo -e "${BLUE}Uptime:${NC} $(uptime -p | sed 's/up //')"
    echo ""
    
    echo -e "${BLUE}Services Status:${NC}"
    if [ "$V2BX_INSTALLED" = true ]; then
        if [ "$V2BX_RUNNING" = true ]; then
            echo -e "  ${GREEN}●${NC} V2bX - Running (v$(get_v2bx_version))"
        else
            echo -e "  ${RED}●${NC} V2bX - Stopped"
        fi
    else
        echo -e "  ${RED}●${NC} V2bX - Not Installed"
    fi
    
    if [ "$VNSTAT_INSTALLED" = true ]; then
        if [ "$VNSTAT_RUNNING" = true ]; then
            echo -e "  ${GREEN}●${NC} vnstat - Running"
        else
            echo -e "  ${RED}●${NC} vnstat - Stopped"
        fi
    else
        echo -e "  ${RED}●${NC} vnstat - Not Installed"
    fi
    echo ""
    
    backup_count=$(ls -1 "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null | wc -l)
    echo -e "${BLUE}Backups:${NC} $backup_count total"
    echo -e "${BLUE}Directory:${NC} $BACKUP_DIR"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

get_v2bx_version() {
    if [ -f "$V2BX_PATH/V2bX" ]; then
        $V2BX_PATH/V2bX -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "installed"
    else
        echo "unknown"
    fi
}

# ============================================
# Main Menu
# ============================================

show_menu() {
    echo " MAIN MENU"
    echo ""
    echo "   1. Create backup"
    echo "   2. Restore backup"
    echo "   3. List backups"
    echo "   4. Cleanup old backups"
    echo "   5. Install V2bX"
    echo "   6. Install vnstat"
    echo "   7. Manage services"
    echo "   8. Exit"
    echo ""
}

manage_services_menu() {
    while true; do
        clear
        show_dashboard
        echo " SERVICE MANAGEMENT"
        echo ""
        echo "   1. Start V2bX"
        echo "   2. Stop V2bX"
        echo "   3. Restart V2bX"
        echo "   4. Start vnstat"
        echo "   5. Stop vnstat"
        echo "   6. Restart vnstat"
        echo "   7. Back to main menu"
        echo ""
        read -p " Choose option [1-7]: " choice
        
        case $choice in
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
        read -p " Press Enter to continue..."
    done
}

# ============================================
# Main
# ============================================

main() {
    check_root
    detect_os
    install_dependencies
    check_installation
    
    while true; do
        show_dashboardf
        show_menu
        read -p " Choose option [1-8]: " choice
        
        case $choice in
            1) create_backup ;;
            2) restore_backup ;;
            3) list_backups ;;
            4) cleanup_backups ;;
            5) install_v2bx ;;
            6) install_vnstat ;;
            7) manage_services_menu ;;
            8) print_success "Goodbye!"; exit 0 ;;
            *) print_error "Invalid option" ;;
        esac
        
        echo ""
        read -p " Press Enter to continue..."
    done
}

# Run main function
main
