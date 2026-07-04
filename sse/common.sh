#!/usr/bin/env bash
#
# common.sh - Shared utilities, logging, variables, and OS detection

# Strict variable naming convention (global variables prefixed with SSE_)
SSE_SESSION_IPV4_ONLINE=""
SSE_SESSION_IPV6_ONLINE=""
SSE_SESSION_IPV6_LOCAL=""
SSE_SESSION_BBR_STATUS=""
SSE_SESSION_QDISC_STATUS=""
SSE_SESSION_VNSTAT_VERSION=""
SSE_SESSION_VNSTAT_OUTPUT=""
SSE_SESSION_HOSTNAME=""
SSE_SESSION_OS=""
SSE_SESSION_KERNEL=""
SSE_SESSION_CPU=""
SSE_SESSION_CORES=""
SSE_SESSION_DISK_TYPE=""
SSE_SESSION_CACHE_READY=0

readonly SSE_SWAPFILE="/swapfile"
readonly SSE_MIN_SAFE_RAM_MB=100
readonly SSE_DEFAULT_TIMEZONE="Asia/Shanghai"
SSE_LOG_DIR="/root/server-setup-logs/"
readonly SSE_LOG_FILE="${SSE_LOG_DIR}/server-setup.log"

mkdir -p "$SSE_LOG_DIR"

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

###### Logging Functions ######
# With configurable log levels
log_msg() {
    local level=$1
    local color=$2
    local icon=$3
    shift 3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] ${color}${BOLD}[$level]${RESET} ${color}${icon} $*${RESET}" | tee -a "$SSE_LOG_FILE"
}

log_debug()   { log_msg "DEBUG" "$GRAY" "🐛" "$*"; }
log_info()    { log_msg "INFO" "$CYAN" "ℹ️" "$*"; }
log_ok()      { log_msg "SUCCESS" "$GREEN" "✅" "$*"; }
log_warn()    { log_msg "WARN" "$YELLOW" "⚠️" "$*"; }
log_error()   { log_msg "ERROR" "$RED" "❌" "$*"; }

###### System Best Practices ######
backup_file() {
    local target_file="$1"
    if [[ -f "$target_file" ]]; then
        local backup="${target_file}.bak-$(date +%Y%m%d-%H%M%S)"
        log_info "Creating backup of ${target_file} -> ${backup}"
        cp "$target_file" "$backup" && log_ok "Backup created successfully" || log_error "Failed to create backup"
    fi
}

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
    echo -e "${BOLD}${CYAN}║              SERVER SETUP ESSENTIALS ${SSE_VERSION:-v2.5.7}                    ║${RESET}"
    echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════╣${RESET}"
}

section_title() {
    banner
    if type display_system_status >/dev/null 2>&1; then
        display_system_status
    fi
    echo
    echo -e "${BOLD}${MAGENTA}🎯 $*${RESET}"
}

sub_section() {
    echo
    echo -e "${BOLD}${CYAN}🔹 $*${RESET}"
}

ensure_command() {
    local cmd="$1"
    local pkg="${2:-$1}"
    
    if ! command -v "$cmd" &>/dev/null; then
        log_info "Command '$cmd' not found, installing '$pkg'..."
        pkg_install "$pkg"
    fi
}

install_script_dependencies() {
    ensure_command "bc" "bc"
    if [[ "$SSE_OS_TYPE" == "debian" ]]; then
        ensure_command "lsb_release" "lsb-release"
    fi
}

###### OS Detection & Package Manager ######
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

SSE_OS_TYPE=$(detect_os)
SSE_PKG_MANAGER=$(detect_package_manager)

init_package_lists() {
    if [[ "$SSE_OS_TYPE" == "alpine" ]]; then
        SSE_BASE_PACKAGES=("curl" "wget" "nano" "htop" "vnstat" "jq" "bc" "tzdata")
        SSE_NETWORK_PACKAGES=("vnstat" "net-tools" "bind-tools" "iputils" "traceroute")
        SSE_LOG_OPTIMIZATION_PACKAGES=()
        SSE_EXTRA_PACKAGES=("git" "unzip" "screen" "speedtest-cli" "coreutils")
    elif [[ "$SSE_OS_TYPE" == "debian" ]]; then
        SSE_BASE_PACKAGES=("curl" "wget" "nano" "htop" "vnstat" "jq")
        SSE_NETWORK_PACKAGES=("vnstat" "net-tools" "dnsutils" "iputils-ping" "traceroute")
        SSE_LOG_OPTIMIZATION_PACKAGES=("systemd-journal-remote" "logrotate")
        SSE_EXTRA_PACKAGES=("git" "unzip" "screen" "speedtest-cli" "bc")
    else
        SSE_BASE_PACKAGES=("curl" "wget" "nano" "htop" "vnstat" "jq" "bc")
        SSE_NETWORK_PACKAGES=("vnstat" "net-tools" "bind-utils" "iputils" "traceroute")
        SSE_LOG_OPTIMIZATION_PACKAGES=()
        SSE_EXTRA_PACKAGES=("git" "unzip" "screen" "speedtest" "epel-release")
    fi
    readonly SSE_BASE_PACKAGES
    readonly SSE_NETWORK_PACKAGES
    readonly SSE_LOG_OPTIMIZATION_PACKAGES
    readonly SSE_EXTRA_PACKAGES
}
init_package_lists

###### Package Management Wrappers ######
pkg_update() {
    log_info "Updating package lists (quiet)..."
    case "$SSE_PKG_MANAGER" in
        apk) apk update ;;
        apt) apt-get update -qq -y ;;
        yum) yum check-update -q -y || true ;;
        dnf) dnf check-update -q -y || true ;;
    esac
}

pkg_upgrade() {
    log_info "Upgrading packages..."
    case "$SSE_PKG_MANAGER" in
        apk) apk upgrade ;;
        apt) DEBIAN_FRONTEND=noninteractive apt-get upgrade -y ;;
        yum|dnf) $SSE_PKG_MANAGER update -y ;;
    esac
}

pkg_install() {
    local packages=("$@")
    log_info "Installing packages: ${packages[*]}"
    case "$SSE_PKG_MANAGER" in
        apk)
            apk update
            apk add "${packages[@]}"
            ;;
        apt)
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
            ;;
        yum|dnf) $SSE_PKG_MANAGER install -y "${packages[@]}" ;;
    esac
}

pkg_remove() {
    local packages=("$@")
    log_info "Removing packages: ${packages[*]}"
    case "$SSE_PKG_MANAGER" in
        apk) apk del "${packages[@]}" ;;
        apt) apt-get remove -y "${packages[@]}" ;;
        yum|dnf) $SSE_PKG_MANAGER remove -y "${packages[@]}" ;;
    esac
}

pkg_autoremove() {
    log_info "Cleaning up unnecessary packages..."
    case "$SSE_PKG_MANAGER" in
        apk) apk cache clean ;;
        apt) apt-get autoremove -y --purge ;;
        yum) yum autoremove -y ;;
        dnf) dnf autoremove -y ;;
    esac
}

