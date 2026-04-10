#!/bin/bash

# ============================================
# V2bX & vnstat Backup/Restore Script
# Supports: Debian, Ubuntu, CentOS, RHEL, Alpine
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
V2BX_PATH="/etc/V2bX"
VNSTAT_PATH="/var/lib/vnstat"
BACKUP_DIR="/root"
SCRIPT_NAME=$(basename "$0")
V2BX_SERVICE="V2bX"
VNSTAT_SERVICE="vnstat"

# ============================================
# Utility Functions
# ============================================

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
    
    print_status "Detected OS: $OS $VER"
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
    
    print_status "Package manager: $PKG_MANAGER"
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

check_services() {
    # Check if V2bX is installed
    if [ ! -d "$V2BX_PATH" ]; then
        print_warning "V2bX not found at $V2BX_PATH"
        V2BX_INSTALLED=false
    else
        V2BX_INSTALLED=true
    fi
    
    # Check for vnstat
    if [ ! -d "$VNSTAT_PATH" ]; then
        print_warning "vnstat not found at $VNSTAT_PATH"
        VNSTAT_INSTALLED=false
    else
        VNSTAT_INSTALLED=true
    fi
}

get_domain() {
    local config_file="$V2BX_PATH/config.json"
    
    if [ ! -f "$config_file" ]; then
        print_warning "config.json not found"
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

# ============================================
# Installation Functions
# ============================================

install_v2bx() {
    print_status "Installing V2bX..."
    
    # Detect architecture
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
    
    # Get latest version
    print_status "Fetching latest V2bX version..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/InazumaV/V2bX/releases/latest | jq -r .tag_name)
    
    if [ -z "$LATEST_VERSION" ]; then
        print_warning "Failed to fetch latest version, using latest release"
        DOWNLOAD_URL="https://github.com/InazumaV/V2bX/releases/latest/download/V2bX-linux-${ARCH}.zip"
    else
        DOWNLOAD_URL="https://github.com/InazumaV/V2bX/releases/download/${LATEST_VERSION}/V2bX-linux-${ARCH}.zip"
    fi
    
    # Download and install
    print_status "Downloading V2bX from $DOWNLOAD_URL"
    curl -L -o /tmp/V2bX.zip "$DOWNLOAD_URL" || {
        print_error "Failed to download V2bX"
        return 1
    }
    
    # Install unzip if needed
    if ! command -v unzip >/dev/null 2>&1; then
        print_status "Installing unzip..."
        eval "$INSTALL_CMD unzip" || {
            print_error "Failed to install unzip"
            return 1
        }
    fi
    
    # Extract and install
    unzip -o /tmp/V2bX.zip -d /tmp/V2bX_extract || {
        print_error "Failed to extract V2bX"
        return 1
    }
    
    mkdir -p "$V2BX_PATH"
    cp -r /tmp/V2bX_extract/* "$V2BX_PATH/" 2>/dev/null || true
    
    # Make binary executable
    if [ -f "$V2BX_PATH/V2bX" ]; then
        chmod +x "$V2BX_PATH/V2bX"
    elif [ -f "$V2BX_PATH/V2bX-linux-${ARCH}" ]; then
        mv "$V2BX_PATH/V2bX-linux-${ARCH}" "$V2BX_PATH/V2bX"
        chmod +x "$V2BX_PATH/V2bX"
    fi
    
    # Create service file based on init system
    create_v2bx_service
    
    # Cleanup
    rm -rf /tmp/V2bX.zip /tmp/V2bX_extract
    
    print_success "V2bX installed successfully"
    V2BX_INSTALLED=true
}

create_v2bx_service() {
    # Detect init system
    if command -v systemctl >/dev/null 2>&1; then
        print_status "Creating systemd service for V2bX..."
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
        print_status "Creating OpenRC service for V2bX..."
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
        # Create database directory if needed
        mkdir -p "$VNSTAT_PATH"
        
        # Initialize database for network interfaces
        if command -v vnstat >/dev/null 2>&1; then
            for interface in $(ls /sys/class/net/ | grep -v lo); do
                vnstat -i $interface --add 2>/dev/null || true
            done
        fi
        
        # Start vnstat service
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
    print_status "Starting V2bX service..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start V2bX.service
        systemctl status V2bX.service --no-pager
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service V2bX start
    elif [ -f "$V2BX_PATH/V2bX" ]; then
        # Run directly if no init system
        nohup "$V2BX_PATH/V2bX" server > /var/log/V2bX.log 2>&1 &
    fi
    
    # Check if running
    sleep 2
    if pgrep -f "V2bX" >/dev/null; then
        print_success "V2bX started successfully"
    else
        print_warning "V2bX may not be running, check logs"
    fi
}

stop_v2bx() {
    print_status "Stopping V2bX service..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop V2bX.service
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service V2bX stop
    else
        pkill -f "V2bX" || true
    fi
}

restart_v2bx() {
    print_status "Restarting V2bX service..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart V2bX.service
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service V2bX restart
    else
        stop_v2bx
        sleep 2
        start_v2bx
    fi
}

start_vnstat() {
    print_status "Starting vnstat service..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start vnstat
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service vnstat start
    elif command -v service >/dev/null 2>&1; then
        service vnstat start
    fi
}

stop_vnstat() {
    print_status "Stopping vnstat service..."
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop vnstat
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service vnstat stop
    elif command -v service >/dev/null 2>&1; then
        service vnstat stop
    fi
}

ensure_v2bx_running() {
    if ! pgrep -f "V2bX" >/dev/null; then
        print_warning "V2bX is not running"
        read -p "Do you want to start V2bX? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            start_v2bx
        fi
    else
        print_success "V2bX is running"
    fi
}

ensure_vnstat_running() {
    if command -v vnstat >/dev/null 2>&1; then
        if ! pgrep -f "vnstat" >/dev/null; then
            print_warning "vnstat is not running"
            read -p "Do you want to start vnstat? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                start_vnstat
            fi
        else
            print_success "vnstat is running"
        fi
    fi
}

# ============================================
# Pre-Restore Installation Check
# ============================================

ensure_v2bx_installed() {
    if [ "$V2BX_INSTALLED" = false ]; then
        print_warning "V2bX is not installed"
        read -p "Do you want to install V2bX before restoring? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_v2bx
            if [ "$V2BX_INSTALLED" = false ]; then
                print_error "Failed to install V2bX. Cannot proceed with restore."
                return 1
            fi
        else
            print_error "V2bX is required for restore. Exiting."
            return 1
        fi
    fi
    return 0
}

ensure_vnstat_installed() {
    if [ "$VNSTAT_INSTALLED" = false ]; then
        print_warning "vnstat is not installed"
        read -p "Do you want to install vnstat before restoring? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_vnstat
            if [ "$VNSTAT_INSTALLED" = false ]; then
                print_warning "Failed to install vnstat. Continuing without vnstat restore."
                return 1
            fi
        else
            print_warning "Skipping vnstat restore"
            return 1
        fi
    fi
    return 0
}

# ============================================
# Backup Functions
# ============================================

backup_v2bx() {
    local backup_path="$1"
    print_status "Backing up V2bX from $V2BX_PATH..."
    
    if [ -d "$V2BX_PATH" ]; then
        tar -rf "$backup_path" "$V2BX_PATH" 2>/dev/null || {
            print_error "Failed to backup V2bX"
            return 1
        }
        print_success "V2bX backed up successfully"
    else
        print_warning "V2bX directory not found"
        return 1
    fi
}

backup_vnstat() {
    local backup_path="$1"
    
    if [ -d "$VNSTAT_PATH" ]; then
        print_status "Backing up vnstat from $VNSTAT_PATH..."
        tar -rf "$backup_path" "$VNSTAT_PATH" 2>/dev/null || {
            print_error "Failed to backup vnstat"
            return 1
        }
        print_success "vnstat backed up successfully"
    else
        print_warning "vnstat not found, skipping"
    fi
}

create_backup() {
    local domain=$(get_domain)
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$BACKUP_DIR/v2bx_vnstat_${domain}_${timestamp}.tar.gz"
    local temp_file="/tmp/v2bx_backup_${timestamp}.tar"
    
    print_status "Creating backup: $backup_file"
    
    # Create temporary tar file
    touch "$temp_file"
    
    # Backup components
    backup_v2bx "$temp_file" || {
        rm -f "$temp_file"
        return 1
    }
    
    backup_vnstat "$temp_file"
    
    # Compress the backup
    if [ -s "$temp_file" ]; then
        gzip -c "$temp_file" > "$backup_file"
        rm -f "$temp_file"
        
        # Show backup info
        local size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup created successfully: $backup_file"
        print_status "Backup size: $size"
    else
        rm -f "$temp_file"
        print_error "Backup failed: no data to backup"
        return 1
    fi
}

list_backups() {
    print_status "Available backups:"
    echo ""
    
    local backups=($(ls -t "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_warning "No backups found in $BACKUP_DIR"
        return
    fi
    
    printf "%-5s %-40s %-10s %-20s\n" "ID" "Filename" "Size" "Date"
    echo "--------------------------------------------------------------------------------"
    
    local id=1
    for backup in "${backups[@]}"; do
        local filename=$(basename "$backup" | sed 's/^v2bx_vnstat_//; s/_[0-9]\{8\}-[0-9]\{6\}\.tar\.gz$//')
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" 2>/dev/null | cut -d. -f1 || stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$backup" 2>/dev/null)
        printf "%-5s %-40s %-10s %-20s\n" "$id" "$filename" "$size" "$date"
        ((id++))
    done
}

# ============================================
# Restore Functions
# ============================================

restore_v2bx() {
    local backup_file="$1"
    local temp_dir="$2"
    
    print_status "Restoring V2bX..."
    
    # Stop V2bX before restore
    stop_v2bx
    
    if [ -d "$V2BX_PATH" ]; then
        local backup_v2bx="$V2BX_PATH.backup.$(date +%Y%m%d_%H%M%S)"
        print_status "Backing up current V2bX to $backup_v2bx"
        mv "$V2BX_PATH" "$backup_v2bx"
    fi
    
    if [ -d "$temp_dir/etc/V2bX" ]; then
        cp -r "$temp_dir/etc/V2bX" "$V2BX_PATH"
        print_success "V2bX restored successfully"
        
        # Restart V2bX
        restart_v2bx
    else
        print_error "V2bX not found in backup"
        return 1
    fi
}

restore_vnstat() {
    local backup_file="$1"
    local temp_dir="$2"
    
    if [ -d "$temp_dir/var/lib/vnstat" ]; then
        print_status "Restoring vnstat..."
        
        # Stop vnstat service if running
        stop_vnstat
        
        # Backup current vnstat if exists
        if [ -d "$VNSTAT_PATH" ]; then
            local backup_vnstat="$VNSTAT_PATH.backup.$(date +%Y%m%d_%H%M%S)"
            print_status "Backing up current vnstat to $backup_vnstat"
            mv "$VNSTAT_PATH" "$backup_vnstat"
        fi
        
        # Restore vnstat
        cp -r "$temp_dir/var/lib/vnstat" "$VNSTAT_PATH"
        
        # Fix permissions
        if getent passwd vnstat >/dev/null 2>&1; then
            chown -R vnstat:vnstat "$VNSTAT_PATH" 2>/dev/null || true
        fi
        
        # Restart vnstat service
        start_vnstat
        
        print_success "vnstat restored successfully"
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
    
    print_status "Restoring from: $backup_file"
    
    # Check and install missing components before restore
    ensure_v2bx_installed || return 1
    ensure_vnstat_installed
    
    # Create temporary directory for extraction
    local temp_dir=$(mktemp -d)
    
    # Extract backup
    tar -xzf "$backup_file" -C "$temp_dir" || {
        print_error "Failed to extract backup"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Confirm restore
    echo ""
    print_warning "This will replace your current V2bX configuration"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Restore cancelled"
        rm -rf "$temp_dir"
        return
    fi
    
    # Restore components
    restore_v2bx "$backup_file" "$temp_dir"
    restore_vnstat "$backup_file" "$temp_dir"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    print_success "Restore completed successfully"
    print_warning "Please verify that both services are running correctly"
}

interactive_restore() {
    list_backups
    
    local backups=($(ls -t "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        return
    fi
    
    echo ""
    read -p "Enter backup ID to restore (or 0 to cancel): " backup_id
    
    if [ "$backup_id" -eq 0 ] 2>/dev/null; then
        print_status "Restore cancelled"
        return
    fi
    
    if [ "$backup_id" -ge 1 ] && [ "$backup_id" -le ${#backups[@]} ] 2>/dev/null; then
        local selected_backup="${backups[$((backup_id-1))]}"
        restore_backup "$selected_backup"
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
    
    print_status "Backup information:"
    echo "  File: $(basename "$backup_file")"
    echo "  Size: $(du -h "$backup_file" | cut -f1)"
    echo "  Created: $(stat -c %y "$backup_file" 2>/dev/null | cut -d. -f1 || stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null)"
    
    # List contents
    echo ""
    print_status "Backup contents:"
    tar -tzf "$backup_file" | head -20
    local total=$(tar -tzf "$backup_file" | wc -l)
    if [ $total -gt 20 ]; then
        echo "  ... and $((total - 20)) more files"
    fi
}

# ============================================
# Installation Status Functions
# ============================================

show_installation_status() {
    echo ""
    print_status "Current Installation Status:"
    echo "=========================================="
    
    if [ -d "$V2BX_PATH" ]; then
        print_success "V2bX: Installed at $V2BX_PATH"
        if pgrep -f "V2bX" >/dev/null; then
            print_success "V2bX: Running"
        else
            print_warning "V2bX: Not running"
        fi
    else
        print_error "V2bX: Not installed"
    fi
    
    if command -v vnstat >/dev/null 2>&1; then
        print_success "vnstat: Installed"
        if pgrep -f "vnstat" >/dev/null; then
            print_success "vnstat: Running"
        else
            print_warning "vnstat: Not running"
        fi
    else
        print_error "vnstat: Not installed"
    fi
    
    if [ -d "$VNSTAT_PATH" ]; then
        print_success "vnstat database: Present at $VNSTAT_PATH"
    else
        print_warning "vnstat database: Not found"
    fi
    echo "=========================================="
}

# ============================================
# Main Menu
# ============================================

show_menu() {
    echo ""
    echo "=========================================="
    echo "   V2bX & vnstat Backup/Restore Tool"
    echo "=========================================="
    echo "1. Create backup"
    echo "2. Restore backup (interactive)"
    echo "3. List backups"
    echo "4. Cleanup old backups"
    echo "5. Show backup info"
    echo "6. Show installation status"
    echo "7. Install V2bX (if missing)"
    echo "8. Install vnstat (if missing)"
    echo "9. Start/restart services"
    echo "10. Exit"
    echo "=========================================="
}

manage_services_menu() {
    echo ""
    echo "Service Management"
    echo "=========================================="
    echo "1. Start V2bX"
    echo "2. Stop V2bX"
    echo "3. Restart V2bX"
    echo "4. Start vnstat"
    echo "5. Stop vnstat"
    echo "6. Restart vnstat"
    echo "7. Back to main menu"
    echo "=========================================="
    
    read -p "Choose an option [1-7]: " svc_choice
    
    case $svc_choice in
        1) start_v2bx ;;
        2) stop_v2bx ;;
        3) restart_v2bx ;;
        4) start_vnstat ;;
        5) stop_vnstat ;;
        6) 
            stop_vnstat
            sleep 2
            start_vnstat
            ;;
        7) return ;;
        *) print_error "Invalid option" ;;
    esac
}

main() {
    check_root
    detect_os
    detect_package_manager
    install_dependencies
    check_services
    
    while true; do
        show_menu
        read -p "Choose an option [1-10]: " choice
        
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
                echo ""
                read -p "Enter backup ID to inspect: " backup_id
                local backups=($(ls -t "$BACKUP_DIR"/v2bx_vnstat_*.tar.gz 2>/dev/null))
                if [ "$backup_id" -ge 1 ] 2>/dev/null && [ "$backup_id" -le ${#backups[@]} ] 2>/dev/null; then
                    show_backup_info "${backups[$((backup_id-1))]}"
                else
                    print_error "Invalid backup ID"
                fi
                ;;
            6)
                show_installation_status
                ;;
            7)
                if [ "$V2BX_INSTALLED" = false ]; then
                    install_v2bx
                else
                    print_warning "V2bX is already installed"
                fi
                ;;
            8)
                if [ "$VNSTAT_INSTALLED" = false ]; then
                    install_vnstat
                else
                    print_warning "vnstat is already installed"
                fi
                ;;
            9)
                manage_services_menu
                ;;
            10)
                print_success "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
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
        check_services
        show_installation_status
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
    *)
        main
        ;;
esac
