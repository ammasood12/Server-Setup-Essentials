#!/bin/bash
# =============================================================================
# phi-nginx — PhiCloud Nginx WS Setup Tool
# Version : 2.0.0
# Author  : PhiCloud
# =============================================================================
#
# DESCRIPTION
#   Automates the setup of Nginx as a reverse proxy on bare VPS servers,
#   enabling VLESS-WS (and Trojan-WS) nodes to run behind a convincing
#   fake SaaS website on port 443. Designed to work alongside an existing
#   V2bX installation managed by Xboard.
#
# WHAT THIS SCRIPT DOES
#   - Installs and configures Nginx on Ubuntu 22/24 LTS
#   - Generates a randomized fake SaaS landing page (company, colors,
#     features, pricing — different on every server)
#   - Configures Nginx to serve the fake site on / and proxy WebSocket
#     traffic on a secret path (e.g. /xk9m2p/data?ed=2048) to V2bX
#   - Manages SSL certificates (V2bX cert, Certbot standalone/nginx, manual)
#   - Adds and edits V2bX node blocks in config.json with correct defaults
#     per node type (WS nodes forced to ListenIP 127.0.0.1, CertMode none)
#   - Sets up a systemd hook to reload Nginx after V2bX restarts
#   - Installs itself as a system command: phi-nginx
#
# ARCHITECTURE
#   [Client]
#     ├── TCP 443  → Nginx → fake website (browser visits)
#     │                    → /secret-path (WS) → 127.0.0.1:10001 → V2bX
#     ├── TCP 8443 → V2bX directly → VLESS-Reality
#     └── UDP 8444 → V2bX directly → Hysteria2
#
# REQUIREMENTS
#   - Ubuntu 22.04 or 24.04 LTS
#   - Root access
#   - V2bX already installed with at least one node working
#   - Domain DNS A record pointing to this server (grey cloud, no CF proxy)
#   - python3 available (for JSON manipulation)
#
# MENU STRUCTURE
#   1  Full Setup              — runs all modules in sequence
#   2  Website Management      — regenerate, edit company/colors/tagline
#   3  Add WS Path             — add another secret path + V2bX node
#   4  Certificate Management  — V2bX cert / Certbot / manual
#   5  V2bX Node Manager       — add, edit (all fields), remove, restart
#   6  Nginx Manager           — status, reload, restart, edit config
#   7  Status & Verification   — service checks + Xboard config output
#   8  Uninstall               — domain only / nginx / V2bX node / full
#   9  Environment Info        — detect OS, ports, certs, existing setup
#   10 Install as system cmd   — copies to /usr/local/bin/phi-nginx
#
# V2BX NODE DEFAULTS APPLIED BY THIS SCRIPT
#   VLESS-WS / Trojan-WS  → Core: xray, ListenIP: 127.0.0.1, CertMode: none
#   VLESS-Reality         → Core: xray, ListenIP: 0.0.0.0,   CertMode: none
#   Hysteria2 / AnyTLS    → Core: sing, ListenIP: ::,        CertMode: dns
#
# IMPORTANT — XBOARD WORKFLOW
#   When adding a WS node, always:
#     1. Add the node in Xboard admin panel first → get the NodeID
#     2. Run this script → V2bX Node Manager → Add node → enter NodeID
#     3. Script will ask if Xboard is configured before restarting V2bX
#   V2bX will fail to start if it tries to fetch a NodeID that does
#   not exist in Xboard yet.
#
# FILES CREATED BY THIS SCRIPT
#   /etc/phi-nginx/config.conf              — persistent settings
#   /etc/nginx/sites-available/phi-DOMAIN  — nginx server block
#   /etc/nginx/sites-enabled/phi-DOMAIN    — symlink
#   /var/www/phi-fake/DOMAIN/              — fake website root
#   /var/www/phi-fake/DOMAIN/index.html    — generated SaaS page
#   /var/www/phi-fake/DOMAIN/robots.txt
#   /var/www/phi-fake/DOMAIN/sitemap.xml
#   /var/www/phi-fake/DOMAIN/.well-known/security.txt
#   /etc/systemd/system/V2bX.service.d/nginx-reload.conf
#   /usr/local/bin/phi-nginx                — system command
#
# USAGE
#   bash phi-nginx.sh          — run interactively
#   phi-nginx                  — after installing as system command
#
# =============================================================================

VERSION="2.0.0"
CONFIG_DIR="/etc/phi-nginx"
CONFIG_FILE="$CONFIG_DIR/config.conf"
NGINX_SITES="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
V2BX_CONFIG="/etc/V2bX/config.json"
V2BX_CONFIG_BAK="/etc/V2bX/config.json.bak"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# =============================================================================
# UTILITIES
# =============================================================================

print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ██████╗ ██╗  ██╗██╗    ███╗   ██╗ ██████╗ ██╗███╗   ██╗██╗  ██╗"
    echo "  ██╔══██╗██║  ██║██║    ████╗  ██║██╔════╝ ██║████╗  ██║╚██╗██╔╝"
    echo "  ██████╔╝███████║██║    ██╔██╗ ██║██║  ███╗██║██╔██╗ ██║ ╚███╔╝ "
    echo "  ██╔═══╝ ██╔══██║██║    ██║╚██╗██║██║   ██║██║██║╚██╗██║ ██╔██╗ "
    echo "  ██║     ██║  ██║██║    ██║ ╚████║╚██████╔╝██║██║ ╚████║██╔╝ ██╗"
    echo "  ╚═╝     ╚═╝  ╚═╝╚═╝    ╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}PhiCloud Nginx WS Setup Tool${NC} ${YELLOW}v${VERSION}${NC}"
    echo -e "  ─────────────────────────────────────────────────────────────"
    echo ""
}

info()    { echo -e "  ${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "  ${RED}[ERROR]${NC} $1"; }
step()    { echo -e "\n  ${CYAN}${BOLD}>> $1${NC}"; }
divider() { echo -e "  ${CYAN}─────────────────────────────────────────────────────────────${NC}"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root."
        exit 1
    fi
}

pause() {
    echo ""
    read -rp "  Press Enter to continue..." _
}

confirm() {
    local msg="${1:-Are you sure?}"
    read -rp "  ${msg} [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
    # Ensure arrays exist
    WS_PATHS=("${WS_PATHS[@]}")
    WS_PORTS=("${WS_PORTS[@]}")
    WS_TYPES=("${WS_TYPES[@]}")
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
DOMAIN="${DOMAIN}"
WS_PATHS=($(printf '"%s" ' "${WS_PATHS[@]}"))
WS_PORTS=($(printf '"%s" ' "${WS_PORTS[@]}"))
WS_TYPES=($(printf '"%s" ' "${WS_TYPES[@]}"))
CERT_MODE="${CERT_MODE}"
CERT_FULLCHAIN="${CERT_FULLCHAIN}"
CERT_KEY="${CERT_KEY}"
FAKE_SITE_ROOT="${FAKE_SITE_ROOT}"
SITE_COMPANY="${SITE_COMPANY}"
SITE_TAGLINE="${SITE_TAGLINE}"
SITE_SLUG="${SITE_SLUG}"
SITE_SUB="${SITE_SUB}"
SITE_SCHEME="${SITE_SCHEME}"
SETUP_DATE="$(date +%Y-%m-%d)"
EOF
}

# =============================================================================
# MODULE 1: ENVIRONMENT DETECTION
# =============================================================================

module_detect() {
    print_banner
    step "Environment Detection"
    divider
    echo ""

    local os_name
    os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
    info "OS: ${os_name:-unknown}"

    if command -v nginx &>/dev/null; then
        local nv; nv=$(nginx -v 2>&1 | grep -o '[0-9.]*$')
        success "Nginx: installed (v${nv})"
        if systemctl is-active --quiet nginx; then
            success "Nginx: running"
        else
            warn "Nginx: stopped"
        fi
    else
        warn "Nginx: NOT installed"
    fi

    if [[ -f "$V2BX_CONFIG" ]]; then
        success "V2bX: config found"
        local node_count
        node_count=$(python3 -c "
import json
try:
    d=json.load(open('$V2BX_CONFIG'))
    print(len(d.get('Nodes',[])))
except:
    print('?')
" 2>/dev/null)
        info "V2bX nodes: $node_count configured"
        if systemctl is-active --quiet V2bX; then
            success "V2bX: running"
        else
            warn "V2bX: stopped"
        fi
    else
        warn "V2bX: config NOT found at $V2BX_CONFIG"
    fi

    if ss -tlnp | grep -q ':443'; then
        local proc
        proc=$(ss -tlnp | grep ':443' | grep -oP 'users:\(\("\K[^"]+' | head -1)
        warn "Port 443: IN USE by ${proc:-unknown}"
    else
        success "Port 443: FREE"
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        load_config
        success "phi-nginx: config found"
        info "Domain: ${DOMAIN:-not set}"
        info "WS paths: ${#WS_PATHS[@]} configured"
        info "Site: ${SITE_COMPANY:-not generated}"
    else
        info "phi-nginx: no existing config"
    fi

    if [[ -f "/etc/V2bX/fullchain.cer" ]]; then
        local cert_cn cert_exp
        cert_cn=$(openssl x509 -in /etc/V2bX/fullchain.cer -noout -subject 2>/dev/null | sed 's/.*CN = //')
        cert_exp=$(openssl x509 -in /etc/V2bX/fullchain.cer -noout -enddate 2>/dev/null | sed 's/notAfter=//')
        success "V2bX cert: CN=${cert_cn}, expires ${cert_exp}"
    else
        info "V2bX cert: not found"
    fi

    echo ""
    divider
    pause
}

# =============================================================================
# MODULE 2: DOMAIN & PATH CONFIG
# =============================================================================

generate_path() {
    local prefixes=("cdn" "assets" "api" "static" "sync" "data" "feed" "stream" "push" "info" "update" "fetch" "relay" "edge")
    local suffixes=("data" "sync" "feed" "stream" "push" "info" "update" "fetch" "index" "load" "pull" "recv")
    local rand_a; rand_a=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 4)
    local rand_b; rand_b=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 3)
    local prefix="${prefixes[$RANDOM % ${#prefixes[@]}]}"
    local suffix="${suffixes[$RANDOM % ${#suffixes[@]}]}"
    echo "/${rand_a}${rand_b}/${suffix}?ed=2048"
}

module_config() {
    print_banner
    step "Domain & Path Configuration"
    divider
    echo ""

    load_config

    # Domain
    if [[ -n "$DOMAIN" ]]; then
        read -rp "  Domain [${DOMAIN}]: " input_domain
        DOMAIN="${input_domain:-$DOMAIN}"
    else
        read -rp "  Domain (e.g. sg2.phicloudapp.com): " DOMAIN
        while [[ -z "$DOMAIN" ]]; do
            error "Domain cannot be empty."
            read -rp "  Domain: " DOMAIN
        done
    fi

    # Default internal port
    local default_port=10001
    if [[ ${#WS_PORTS[@]} -gt 0 ]]; then
        default_port=$((${WS_PORTS[-1]//\"/} + 1))
    fi
    read -rp "  Internal WS port [${default_port}]: " input_port
    local ws_port="${input_port:-$default_port}"

    # Node type
    echo ""
    echo "  Node type:"
    echo "    1) VLESS-WS"
    echo "    2) Trojan-WS"
    read -rp "  Select [1]: " node_type_sel
    local node_type
    case "${node_type_sel:-1}" in
        2) node_type="trojan" ;;
        *) node_type="vless" ;;
    esac

    # Path
    echo ""
    echo "  WS path:"
    echo "    1) Auto-generate random"
    echo "    2) Enter custom"
    read -rp "  Select [1]: " path_sel
    local ws_path
    if [[ "${path_sel:-1}" == "2" ]]; then
        read -rp "  Path (e.g. /mypath/data?ed=2048): " ws_path
        while [[ -z "$ws_path" ]]; do
            error "Path cannot be empty."
            read -rp "  Path: " ws_path
        done
    else
        ws_path=$(generate_path)
        success "Generated: $ws_path"
    fi

    WS_PATHS+=("$ws_path")
    WS_PORTS+=("$ws_port")
    WS_TYPES+=("$node_type")
    FAKE_SITE_ROOT="/var/www/phi-fake/${DOMAIN}"

    echo ""
    success "Configuration saved:"
    info "Domain:  $DOMAIN"
    info "Path:    $ws_path"
    info "Port:    $ws_port"
    info "Type:    $node_type"

    save_config
    pause
}

# =============================================================================
# MODULE 3: CERTIFICATE
# =============================================================================

validate_v2bx_cert() {
    local cert="/etc/V2bX/fullchain.cer"
    [[ ! -f "$cert" ]] && return 1
    local cert_cn
    cert_cn=$(openssl x509 -in "$cert" -noout -subject 2>/dev/null | sed 's/.*CN = //')
    if [[ "$cert_cn" == "$DOMAIN" ]]; then return 0; fi
    if [[ "$cert_cn" == \*.* ]]; then
        local base="${cert_cn#\*.}"
        local dbase="${DOMAIN#*.}"
        [[ "$dbase" == "$base" ]] && return 0
    fi
    return 1
}

module_cert() {
    print_banner
    step "Certificate Management"
    divider
    echo ""
    load_config

    echo "  Options:"
    echo "    1) View current cert info"
    echo "    2) Use V2bX cert"
    echo "    3) Certbot — standalone mode"
    echo "    4) Certbot — nginx mode"
    echo "    5) Manual — provide paths"
    echo "    6) Renew existing cert"
    echo "    7) Back"
    echo ""
    read -rp "  Select: " sel

    case "$sel" in
        1)
            echo ""
            if [[ -n "$CERT_FULLCHAIN" && -f "$CERT_FULLCHAIN" ]]; then
                info "File:    $CERT_FULLCHAIN"
                info "Mode:    $CERT_MODE"
                local cn exp
                cn=$(openssl x509 -in "$CERT_FULLCHAIN" -noout -subject 2>/dev/null | sed 's/.*CN = //')
                exp=$(openssl x509 -in "$CERT_FULLCHAIN" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
                info "CN:      $cn"
                info "Expires: $exp"
            else
                warn "No cert configured yet"
            fi
            ;;
        2)
            step "Using V2bX cert"
            if [[ ! -f "/etc/V2bX/fullchain.cer" ]]; then
                error "V2bX cert not found at /etc/V2bX/fullchain.cer"
                pause; return
            fi
            if validate_v2bx_cert; then
                success "Cert matches domain $DOMAIN"
            else
                local v2bx_cn
                v2bx_cn=$(openssl x509 -in /etc/V2bX/fullchain.cer -noout -subject 2>/dev/null | sed 's/.*CN = //')
                warn "Cert CN ($v2bx_cn) does not match $DOMAIN"
                confirm "Use anyway? (clients with skip-verify only)" || { pause; return; }
            fi
            CERT_MODE="v2bx"
            CERT_FULLCHAIN="/etc/V2bX/fullchain.cer"
            CERT_KEY="/etc/V2bX/cert.key"
            success "V2bX cert configured"
            save_config
            ;;
        3)
            step "Certbot — standalone"
            if ! command -v certbot &>/dev/null; then
                info "Installing certbot..."
                apt-get install -y certbot &>/dev/null
            fi
            if ss -tlnp | grep -q ':80'; then
                warn "Port 80 in use — stopping nginx temporarily"
                systemctl stop nginx 2>/dev/null
            fi
            certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
                -m "admin@${DOMAIN#*.}"
            if [[ $? -eq 0 ]]; then
                CERT_MODE="certbot"
                CERT_FULLCHAIN="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
                CERT_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
                mkdir -p /etc/letsencrypt/renewal-hooks/deploy
                echo '#!/bin/bash
systemctl reload nginx' > /etc/letsencrypt/renewal-hooks/deploy/phi-nginx-reload.sh
                chmod +x /etc/letsencrypt/renewal-hooks/deploy/phi-nginx-reload.sh
                success "Cert issued, auto-reload hook installed"
                save_config
            else
                error "Certbot failed — check DNS A record and port 80"
            fi
            systemctl start nginx 2>/dev/null
            ;;
        4)
            step "Certbot — nginx mode"
            if ! command -v nginx &>/dev/null; then
                error "Nginx not installed. Run Full Setup first."
                pause; return
            fi
            apt-get install -y certbot python3-certbot-nginx &>/dev/null
            certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
                -m "admin@${DOMAIN#*.}"
            if [[ $? -eq 0 ]]; then
                CERT_MODE="certbot"
                CERT_FULLCHAIN="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
                CERT_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
                success "Cert issued"
                save_config
            else
                error "Certbot failed"
            fi
            ;;
        5)
            step "Manual cert paths"
            read -rp "  Fullchain path: " CERT_FULLCHAIN
            read -rp "  Key path: " CERT_KEY
            if [[ ! -f "$CERT_FULLCHAIN" ]]; then
                error "File not found: $CERT_FULLCHAIN"; pause; return
            fi
            if [[ ! -f "$CERT_KEY" ]]; then
                error "File not found: $CERT_KEY"; pause; return
            fi
            CERT_MODE="manual"
            success "Manual cert configured"
            save_config
            ;;
        6)
            step "Renewing cert"
            if [[ "$CERT_MODE" == "certbot" ]]; then
                certbot renew --cert-name "$DOMAIN"
                systemctl reload nginx 2>/dev/null
                success "Renewal attempted"
            elif [[ "$CERT_MODE" == "v2bx" ]]; then
                info "V2bX manages its own cert renewal automatically"
            else
                warn "No renewable cert configured"
            fi
            ;;
        7) return ;;
        *) warn "Invalid option" ;;
    esac
    pause
}

# =============================================================================
# MODULE 4: FAKE WEBSITE GENERATOR
# =============================================================================

# Scheme arrays (index-addressable)
SCHEME_NAMES=("Dark Navy/Blue" "Black/Purple" "Dark Teal/Cyan" "Black/Orange" "White/Green")
declare -a SCHEME_BG=("#0a0f1e" "#0d0d0d" "#0f1923" "#111111" "#f8fafc")
declare -a SCHEME_PRIMARY=("#2563eb" "#7c3aed" "#0891b2" "#ea580c" "#0f766e")
declare -a SCHEME_ACCENT=("#60a5fa" "#a78bfa" "#22d3ee" "#fb923c" "#14b8a6")
declare -a SCHEME_TEXT=("#e2e8f0" "#f3f4f6" "#e0f2fe" "#fff7ed" "#134e4a")
declare -a SCHEME_CARD=("#1e293b" "#1f1f1f" "#164e63" "#1c1917" "#f0fdf4")

declare -a CO_NAMES=("Syncra" "Veltro" "Nexlify" "Dataflux" "Orbita" "Stratum")
declare -a CO_TAGLINES=(
    "Sync infrastructure at scale"
    "The API platform for modern teams"
    "Ship faster with Nexlify"
    "Real-time data, zero config"
    "Cloud-native deployment made simple"
    "Infrastructure you can trust"
)
declare -a CO_SUBS=(
    "The modern platform for teams that move fast"
    "Build, deploy, and scale APIs without the complexity"
    "From code to production in minutes, not days"
    "Stream, transform, and analyze data at any scale"
    "Deploy anywhere. Scale automatically. Sleep at night"
    "Enterprise-grade reliability for teams of all sizes"
)
declare -a CO_SLUGS=("syncra" "veltro" "nexlify" "dataflux" "orbita" "stratum")

declare -a FEATURE_TITLES=(
    "Global Edge Network" "Sub-10ms Latency" "End-to-End Encryption"
    "REST and GraphQL API" "Real-Time Analytics" "Auto-Scaling"
    "Webhook Support" "Role-Based Access" "99.9% Uptime SLA"
    "One-Click Deploy" "SOC 2 Compliant" "24/7 Support"
)
declare -a FEATURE_DESCS=(
    "Deploy to 200+ locations worldwide with automatic routing to the nearest node"
    "Purpose-built for speed. Our infrastructure delivers responses faster than you can measure"
    "Every request encrypted in transit and at rest. AES-256 by default, zero config"
    "One platform, every interface. Consume your data exactly how your application needs it"
    "Live dashboards, custom metrics, and instant alerting. Know what is happening as it happens"
    "Traffic spike? We handle it. Scale from zero to millions of requests without touching a config"
    "Push events to any endpoint the moment they happen. Reliable delivery with automatic retry"
    "Fine-grained permissions for every team member. Audit logs for every action"
    "Contractual uptime guarantees backed by redundant infrastructure across every region"
    "Connect your repo, push your code. We handle builds, deploys, and rollbacks automatically"
    "Security controls audited annually. Export compliance reports in minutes, not months"
    "Real engineers, not bots. Average response time under 4 minutes on any plan"
)
declare -a FEATURE_ICONS=("🌐" "⚡" "🔒" "🔌" "📊" "📈" "🔔" "👥" "✅" "🚀" "🛡️" "💬")

declare -a PRICING_P1=("Hobby" "Starter" "Free" "Basic")
declare -a PRICING_P2=("Pro" "Growth" "Team" "Professional")
declare -a PRICING_P3=("Enterprise" "Business" "Enterprise" "Custom")

declare -a TESTI_QUOTES=(
    "We moved our entire pipeline to this platform and cut deployment time by 80%. The reliability is unmatched."
    "Finally a platform that actually scales. We went from 10k to 10M requests per day without a single incident."
    "The API is the cleanest I have ever worked with. Documentation is excellent, support actually responds."
    "Switched from our old provider and immediately noticed the difference in latency. Our users noticed too."
    "SOC 2 compliance out of the box saved us months of security work. Worth every penny."
)
declare -a TESTI_NAMES=("Sarah K." "Marcus T." "Priya M." "James L." "Chen W.")
declare -a TESTI_TITLES=(
    "CTO at Finbridge" "Lead Engineer at Loopify" "Backend Engineer at Stackr"
    "Co-founder at Driftly" "Head of Infra at Vault Systems"
)

build_site_html() {
    local co_idx=$1
    local scheme_idx=$2

    local CO_NAME="${CO_NAMES[$co_idx]}"
    local CO_TAGLINE="${CO_TAGLINES[$co_idx]}"
    local CO_SUB="${CO_SUBS[$co_idx]}"
    local CO_SLUG="${CO_SLUGS[$co_idx]}"
    local C_BG="${SCHEME_BG[$scheme_idx]}"
    local C_PRIMARY="${SCHEME_PRIMARY[$scheme_idx]}"
    local C_ACCENT="${SCHEME_ACCENT[$scheme_idx]}"
    local C_TEXT="${SCHEME_TEXT[$scheme_idx]}"
    local C_CARD="${SCHEME_CARD[$scheme_idx]}"

    # Pick 6 random non-duplicate features
    local feat_indices=()
    while [[ ${#feat_indices[@]} -lt 6 ]]; do
        local idx=$((RANDOM % 12))
        local dup=0
        for e in "${feat_indices[@]}"; do [[ "$e" == "$idx" ]] && dup=1; done
        [[ $dup -eq 0 ]] && feat_indices+=($idx)
    done

    local pi=$((RANDOM % 4))
    local P1="${PRICING_P1[$pi]}" P2="${PRICING_P2[$pi]}" P3="${PRICING_P3[$pi]}"
    local PRICE1="\$$(( (RANDOM % 3 + 1) * 9 + 9 ))/mo"
    local PRICE2="\$$(( (RANDOM % 5 + 4) * 10 + 9 ))/mo"
    local ti=$((RANDOM % 5))
    local YEAR; YEAR=$(date +%Y)

    local FEAT_HTML=""
    for idx in "${feat_indices[@]}"; do
        FEAT_HTML+="<div class=\"feat-card\"><div class=\"feat-icon\">${FEATURE_ICONS[$idx]}</div>"
        FEAT_HTML+="<h3>${FEATURE_TITLES[$idx]}</h3><p>${FEATURE_DESCS[$idx]}</p></div>"
    done

    cat << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <meta name="description" content="${CO_TAGLINE}. ${CO_SUB}.">
  <meta property="og:title" content="${CO_NAME} — ${CO_TAGLINE}">
  <meta property="og:description" content="${CO_SUB}">
  <meta property="og:type" content="website">
  <meta name="twitter:card" content="summary_large_image">
  <title>${CO_NAME} — ${CO_TAGLINE}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  <style>
    :root{--bg:${C_BG};--primary:${C_PRIMARY};--accent:${C_ACCENT};--text:${C_TEXT};--card:${C_CARD};--border:rgba(255,255,255,0.08);--muted:rgba(255,255,255,0.45)}
    *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}html{scroll-behavior:smooth}
    body{font-family:'Inter',sans-serif;background:var(--bg);color:var(--text);line-height:1.6;overflow-x:hidden}
    nav{position:fixed;top:0;left:0;right:0;z-index:100;display:flex;align-items:center;justify-content:space-between;padding:1rem 2rem;background:${C_BG}dd;backdrop-filter:blur(12px);border-bottom:1px solid var(--border)}
    .nav-logo{font-size:1.1rem;font-weight:700;color:var(--accent);letter-spacing:-0.5px}
    .nav-links{display:flex;gap:2rem;align-items:center}
    .nav-links a{color:var(--muted);text-decoration:none;font-size:.875rem;font-weight:500;transition:color .2s}
    .nav-links a:hover{color:var(--text)}.nav-cta{background:var(--primary);color:#fff!important;padding:.5rem 1.25rem;border-radius:6px;font-weight:600!important}
    .hero{min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:6rem 2rem 4rem;position:relative;overflow:hidden}
    .hero::before{content:'';position:absolute;inset:0;background:radial-gradient(ellipse 80% 60% at 50% 0%,${C_PRIMARY}22 0%,transparent 70%);pointer-events:none}
    .hero-badge{display:inline-flex;align-items:center;gap:.5rem;background:${C_PRIMARY}18;border:1px solid ${C_PRIMARY}44;color:var(--accent);padding:.35rem 1rem;border-radius:999px;font-size:.8rem;font-weight:500;margin-bottom:1.5rem}
    .hero-badge::before{content:'●';font-size:.5rem;animation:pulse 2s infinite}
    @keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}
    h1{font-size:clamp(2.5rem,6vw,4.5rem);font-weight:700;line-height:1.1;letter-spacing:-2px;margin-bottom:1.25rem;max-width:800px}
    h1 span{color:var(--accent)}.hero-sub{font-size:1.125rem;color:var(--muted);max-width:560px;margin-bottom:2.5rem}
    .hero-buttons{display:flex;gap:1rem;flex-wrap:wrap;justify-content:center}
    .btn-primary{background:var(--primary);color:#fff;padding:.875rem 2rem;border-radius:8px;font-size:.95rem;font-weight:600;text-decoration:none;transition:all .2s;box-shadow:0 0 30px ${C_PRIMARY}44}
    .btn-primary:hover{transform:translateY(-1px);box-shadow:0 0 40px ${C_PRIMARY}66}
    .btn-secondary{background:transparent;color:var(--text);padding:.875rem 2rem;border-radius:8px;font-size:.95rem;font-weight:500;text-decoration:none;border:1px solid var(--border);transition:all .2s}
    .btn-secondary:hover{border-color:var(--accent);color:var(--accent)}
    .stats{display:flex;gap:0;flex-wrap:wrap;border:1px solid var(--border);border-radius:12px;overflow:hidden;margin:4rem auto 0;max-width:700px;width:100%}
    .stat{flex:1;min-width:140px;padding:1.5rem 2rem;text-align:center;border-right:1px solid var(--border)}
    .stat:last-child{border-right:none}.stat-num{font-size:2rem;font-weight:700;color:var(--accent);display:block;font-family:'JetBrains Mono',monospace}
    .stat-label{font-size:.8rem;color:var(--muted)}section{padding:6rem 2rem}
    .section-label{text-align:center;font-size:.8rem;font-weight:600;letter-spacing:3px;text-transform:uppercase;color:var(--accent);margin-bottom:1rem}
    h2{text-align:center;font-size:clamp(1.75rem,4vw,2.75rem);font-weight:700;letter-spacing:-1px;margin-bottom:1rem}
    .section-sub{text-align:center;color:var(--muted);max-width:500px;margin:0 auto 3.5rem;font-size:1rem}
    .feat-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:1.25rem;max-width:1100px;margin:0 auto}
    .feat-card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.75rem;transition:border-color .2s,transform .2s}
    .feat-card:hover{border-color:${C_PRIMARY}66;transform:translateY(-2px)}.feat-icon{font-size:1.75rem;margin-bottom:1rem}
    .feat-card h3{font-size:1rem;font-weight:600;margin-bottom:.5rem}.feat-card p{font-size:.875rem;color:var(--muted);line-height:1.6}
    .pricing-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:1.25rem;max-width:900px;margin:0 auto}
    .price-card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:2rem}
    .price-card.featured{border-color:var(--primary);background:${C_PRIMARY}0f;position:relative}
    .price-badge{position:absolute;top:-12px;left:50%;transform:translateX(-50%);background:var(--primary);color:#fff;padding:.25rem 1rem;border-radius:999px;font-size:.75rem;font-weight:600}
    .price-tier{font-size:.85rem;font-weight:600;color:var(--muted);margin-bottom:.5rem;text-transform:uppercase;letter-spacing:1px}
    .price-amount{font-size:2.5rem;font-weight:700;color:var(--text);margin-bottom:.25rem;font-family:'JetBrains Mono',monospace}
    .price-period{font-size:.8rem;color:var(--muted);margin-bottom:1.5rem}
    .price-features{list-style:none;margin-bottom:2rem}
    .price-features li{font-size:.875rem;color:var(--muted);padding:.4rem 0;border-bottom:1px solid var(--border);display:flex;gap:.5rem}
    .price-features li::before{content:'✓';color:var(--accent);font-weight:600}
    .price-btn{display:block;text-align:center;padding:.75rem;border-radius:8px;font-weight:600;font-size:.875rem;text-decoration:none;transition:all .2s;border:1px solid var(--border);color:var(--text)}
    .price-card.featured .price-btn{background:var(--primary);color:#fff;border-color:transparent}.price-btn:hover{opacity:.85}
    .testimonial-wrap{max-width:700px;margin:0 auto;background:var(--card);border:1px solid var(--border);border-radius:16px;padding:2.5rem;text-align:center}
    .testimonial-quote{font-size:1.125rem;line-height:1.7;color:var(--text);margin-bottom:1.5rem;font-style:italic}
    .testimonial-name{font-weight:700;font-size:.95rem}.testimonial-title{font-size:.8rem;color:var(--muted)}
    .cta-section{text-align:center;background:linear-gradient(135deg,${C_PRIMARY}18 0%,transparent 60%);border-top:1px solid var(--border);border-bottom:1px solid var(--border)}
    .cta-section p{color:var(--muted);margin-bottom:2rem}
    footer{padding:3rem 2rem;border-top:1px solid var(--border)}
    .footer-inner{max-width:1100px;margin:0 auto;display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:2rem}
    .footer-brand{font-size:1.1rem;font-weight:700;color:var(--accent);margin-bottom:.5rem}
    .footer-tagline{font-size:.8rem;color:var(--muted);max-width:200px}
    .footer-links-group h4{font-size:.75rem;font-weight:600;text-transform:uppercase;letter-spacing:1px;color:var(--muted);margin-bottom:.75rem}
    .footer-links-group a{display:block;font-size:.85rem;color:var(--muted);text-decoration:none;margin-bottom:.4rem;transition:color .2s}
    .footer-links-group a:hover{color:var(--text)}
    .footer-bottom{max-width:1100px;margin:2rem auto 0;padding-top:1.5rem;border-top:1px solid var(--border);display:flex;justify-content:space-between;flex-wrap:wrap;gap:1rem;font-size:.78rem;color:var(--muted)}
    .code-block{background:#0d1117;border:1px solid var(--border);border-radius:8px;padding:1.5rem;font-family:'JetBrains Mono',monospace;font-size:.8rem;color:#c9d1d9;max-width:600px;margin:2rem auto 0;text-align:left;overflow-x:auto;white-space:pre}
    .kw{color:#ff7b72}.str{color:#a5d6ff}.cm{color:#8b949e}
  </style>
</head>
<body>
<nav>
  <div class="nav-logo">${CO_NAME}</div>
  <div class="nav-links">
    <a href="#features">Features</a><a href="#pricing">Pricing</a>
    <a href="#docs">Docs</a><a href="#" class="nav-cta">Get Started</a>
  </div>
</nav>
<section class="hero">
  <div class="hero-badge">Now in General Availability</div>
  <h1>${CO_TAGLINE} — <span>built different</span></h1>
  <p class="hero-sub">${CO_SUB}. No ops team required.</p>
  <div class="hero-buttons">
    <a href="#" class="btn-primary">Start for free →</a>
    <a href="#docs" class="btn-secondary">Read the docs</a>
  </div>
  <div class="stats">
    <div class="stat"><span class="stat-num">200+</span><span class="stat-label">Edge locations</span></div>
    <div class="stat"><span class="stat-num">99.9%</span><span class="stat-label">Uptime SLA</span></div>
    <div class="stat"><span class="stat-num">&lt;8ms</span><span class="stat-label">Avg latency</span></div>
    <div class="stat"><span class="stat-num">50k+</span><span class="stat-label">Teams</span></div>
  </div>
</section>
<section id="features">
  <div class="section-label">Features</div>
  <h2>Everything you need. Nothing you don't.</h2>
  <p class="section-sub">Built for engineers who value their time and their users experience.</p>
  <div class="feat-grid">${FEAT_HTML}</div>
</section>
<section id="docs" style="padding-top:0">
  <div class="section-label">Quick Start</div>
  <h2>Up and running in minutes</h2>
  <p class="section-sub">Install the CLI and connect your first project in under 60 seconds.</p>
  <div class="code-block"><span class="cm"># Install the ${CO_SLUG} CLI</span>
<span class="kw">npm</span> install -g @${CO_SLUG}/cli

<span class="cm"># Authenticate</span>
<span class="kw">${CO_SLUG}</span> login

<span class="cm"># Deploy your first project</span>
<span class="kw">${CO_SLUG}</span> deploy <span class="str">./my-project</span>

<span class="str">✓ Build complete (2.3s)
✓ Deployed to edge (47 regions)
✓ Live at https://my-project.${CO_SLUG}.app</span></div>
</section>
<section id="pricing">
  <div class="section-label">Pricing</div>
  <h2>Simple, transparent pricing</h2>
  <p class="section-sub">No hidden fees. No surprise bills. Cancel anytime.</p>
  <div class="pricing-grid">
    <div class="price-card">
      <div class="price-tier">${P1}</div><div class="price-amount">${PRICE1}</div>
      <div class="price-period">per month, billed monthly</div>
      <ul class="price-features"><li>Up to 10,000 requests/day</li><li>3 projects</li><li>Community support</li><li>Basic analytics</li></ul>
      <a href="#" class="price-btn">Get started</a>
    </div>
    <div class="price-card featured">
      <div class="price-badge">Most Popular</div>
      <div class="price-tier">${P2}</div><div class="price-amount">${PRICE2}</div>
      <div class="price-period">per month, billed monthly</div>
      <ul class="price-features"><li>Unlimited requests</li><li>Unlimited projects</li><li>Priority support</li><li>Advanced analytics</li><li>Custom domains</li><li>Team collaboration</li></ul>
      <a href="#" class="price-btn">Start free trial</a>
    </div>
    <div class="price-card">
      <div class="price-tier">${P3}</div><div class="price-amount">Custom</div>
      <div class="price-period">contact us for pricing</div>
      <ul class="price-features"><li>Everything in ${P2}</li><li>Dedicated infrastructure</li><li>SLA guarantee</li><li>SSO and SAML</li><li>Custom contracts</li><li>Onboarding support</li></ul>
      <a href="#" class="price-btn">Contact sales</a>
    </div>
  </div>
</section>
<section>
  <div class="section-label">Trusted by engineers</div>
  <h2>Don't take our word for it</h2>
  <p class="section-sub">Teams at fast-moving companies rely on ${CO_NAME} every day.</p>
  <div class="testimonial-wrap">
    <p class="testimonial-quote">${TESTI_QUOTES[$ti]}</p>
    <div class="testimonial-name">${TESTI_NAMES[$ti]}</div>
    <div class="testimonial-title">${TESTI_TITLES[$ti]}</div>
  </div>
</section>
<section class="cta-section">
  <h2>Ready to ship faster?</h2>
  <p>Join 50,000+ engineers already using ${CO_NAME}.</p>
  <a href="#" class="btn-primary">Start for free — no credit card required</a>
</section>
<footer>
  <div class="footer-inner">
    <div><div class="footer-brand">${CO_NAME}</div><div class="footer-tagline">${CO_TAGLINE}</div></div>
    <div class="footer-links-group"><h4>Product</h4><a href="#">Features</a><a href="#">Pricing</a><a href="#">Changelog</a><a href="#">Roadmap</a></div>
    <div class="footer-links-group"><h4>Developers</h4><a href="#">Documentation</a><a href="#">API Reference</a><a href="#">SDKs</a><a href="#">Status</a></div>
    <div class="footer-links-group"><h4>Company</h4><a href="#">About</a><a href="#">Blog</a><a href="#">Careers</a><a href="#">Contact</a></div>
  </div>
  <div class="footer-bottom">
    <span>© ${YEAR} ${CO_NAME}, Inc. All rights reserved.</span>
    <span>Privacy Policy · Terms of Service · Cookie Policy</span>
  </div>
</footer>
<script>
  document.querySelectorAll('a[href^="#"]').forEach(a=>{a.addEventListener('click',e=>{const t=document.querySelector(a.getAttribute('href'));if(t){e.preventDefault();t.scrollIntoView({behavior:'smooth'});}});});
  window.addEventListener('load',()=>{const d={page:location.pathname,ref:document.referrer,t:Date.now()};navigator.sendBeacon&&navigator.sendBeacon('/api/v1/analytics',JSON.stringify(d));});
  const secs=document.querySelectorAll('section[id]'),navAs=document.querySelectorAll('.nav-links a[href^="#"]');
  window.addEventListener('scroll',()=>{let cur='';secs.forEach(s=>{if(window.scrollY>=s.offsetTop-100)cur=s.id;});navAs.forEach(a=>{a.style.color=a.getAttribute('href')==='#'+cur?'var(--accent)':'';});});
</script>
</body>
</html>
HTMLEOF
}

write_site_files() {
    local root="$1"
    local co_idx=$2
    local scheme_idx=$3
    mkdir -p "$root" "${root}/.well-known"
    build_site_html "$co_idx" "$scheme_idx" > "${root}/index.html"
    echo -e "User-agent: *\nAllow: /\nSitemap: https://${DOMAIN}/sitemap.xml" > "${root}/robots.txt"
    local YEAR; YEAR=$(date +%Y)
    cat > "${root}/sitemap.xml" << SEOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://${DOMAIN}/</loc><lastmod>${YEAR}-$(date +%m)-$(date +%d)</lastmod><changefreq>weekly</changefreq><priority>1.0</priority></url>
</urlset>
SEOF
    echo -e "Contact: mailto:security@${DOMAIN}\nExpires: ${YEAR}-12-31T23:59:59.000Z" > "${root}/.well-known/security.txt"
}

# =============================================================================
# MODULE 5: WEBSITE MANAGEMENT
# =============================================================================

module_website() {
    while true; do
        print_banner
        load_config
        step "Website Management"
        divider
        echo ""

        if [[ -n "$SITE_COMPANY" ]]; then
            info "Current: ${SITE_COMPANY} — ${SITE_TAGLINE}"
            info "Scheme:  ${SCHEME_NAMES[${SITE_SCHEME:-0}]}"
            info "Root:    ${FAKE_SITE_ROOT}"
        else
            warn "No site generated yet"
        fi

        echo ""
        echo "    1) Regenerate — new random company + colors"
        echo "    2) Edit company name"
        echo "    3) Edit tagline"
        echo "    4) Edit color scheme"
        echo "    5) Rebuild site (apply current settings)"
        echo "    6) View site info"
        echo "    7) Back"
        echo ""
        read -rp "  Select: " sel

        case "$sel" in
            1)
                local co_idx=$((RANDOM % 6))
                local sc_idx=$((RANDOM % 5))
                SITE_COMPANY="${CO_NAMES[$co_idx]}"
                SITE_TAGLINE="${CO_TAGLINES[$co_idx]}"
                SITE_SUB="${CO_SUBS[$co_idx]}"
                SITE_SLUG="${CO_SLUGS[$co_idx]}"
                SITE_SCHEME="$sc_idx"
                write_site_files "$FAKE_SITE_ROOT" "$co_idx" "$sc_idx"
                save_config
                success "Regenerated: ${SITE_COMPANY} with ${SCHEME_NAMES[$sc_idx]}"
                systemctl reload nginx 2>/dev/null
                ;;
            2)
                echo ""
                echo "  Available companies:"
                for i in "${!CO_NAMES[@]}"; do
                    echo "    $((i+1))) ${CO_NAMES[$i]} — ${CO_TAGLINES[$i]}"
                done
                echo ""
                read -rp "  Select company [1-6] or enter custom name: " inp
                if [[ "$inp" =~ ^[1-6]$ ]]; then
                    local idx=$((inp - 1))
                    SITE_COMPANY="${CO_NAMES[$idx]}"
                    SITE_TAGLINE="${CO_TAGLINES[$idx]}"
                    SITE_SUB="${CO_SUBS[$idx]}"
                    SITE_SLUG="${CO_SLUGS[$idx]}"
                    local sc=$((SITE_SCHEME))
                    write_site_files "$FAKE_SITE_ROOT" "$idx" "$sc"
                elif [[ -n "$inp" ]]; then
                    SITE_COMPANY="$inp"
                    read -rp "  Slug (lowercase, no spaces): " SITE_SLUG
                    local sc=$((SITE_SCHEME))
                    local co_idx=0
                    for i in "${!CO_NAMES[@]}"; do
                        [[ "${CO_NAMES[$i]}" == "$SITE_COMPANY" ]] && co_idx=$i
                    done
                    write_site_files "$FAKE_SITE_ROOT" "$co_idx" "$sc"
                fi
                save_config
                systemctl reload nginx 2>/dev/null
                success "Company updated: $SITE_COMPANY"
                ;;
            3)
                read -rp "  New tagline: " new_tag
                [[ -n "$new_tag" ]] && SITE_TAGLINE="$new_tag"
                local co_idx=0
                for i in "${!CO_NAMES[@]}"; do
                    [[ "${CO_NAMES[$i]}" == "$SITE_COMPANY" ]] && co_idx=$i
                done
                write_site_files "$FAKE_SITE_ROOT" "$co_idx" "${SITE_SCHEME:-0}"
                save_config
                systemctl reload nginx 2>/dev/null
                success "Tagline updated"
                ;;
            4)
                echo ""
                echo "  Color schemes:"
                for i in "${!SCHEME_NAMES[@]}"; do
                    echo "    $((i+1))) ${SCHEME_NAMES[$i]}  (bg:${SCHEME_BG[$i]} primary:${SCHEME_PRIMARY[$i]})"
                done
                echo ""
                read -rp "  Select [1-5]: " sc_sel
                if [[ "$sc_sel" =~ ^[1-5]$ ]]; then
                    SITE_SCHEME=$((sc_sel - 1))
                    local co_idx=0
                    for i in "${!CO_NAMES[@]}"; do
                        [[ "${CO_NAMES[$i]}" == "$SITE_COMPANY" ]] && co_idx=$i
                    done
                    write_site_files "$FAKE_SITE_ROOT" "$co_idx" "$SITE_SCHEME"
                    save_config
                    systemctl reload nginx 2>/dev/null
                    success "Color scheme updated: ${SCHEME_NAMES[$SITE_SCHEME]}"
                fi
                ;;
            5)
                local co_idx=0
                for i in "${!CO_NAMES[@]}"; do
                    [[ "${CO_NAMES[$i]}" == "$SITE_COMPANY" ]] && co_idx=$i
                done
                write_site_files "$FAKE_SITE_ROOT" "$co_idx" "${SITE_SCHEME:-0}"
                systemctl reload nginx 2>/dev/null
                success "Site rebuilt"
                ;;
            6)
                echo ""
                info "Company:  ${SITE_COMPANY:-not set}"
                info "Tagline:  ${SITE_TAGLINE:-not set}"
                info "Slug:     ${SITE_SLUG:-not set}"
                info "Scheme:   ${SCHEME_NAMES[${SITE_SCHEME:-0}]}"
                info "Root:     ${FAKE_SITE_ROOT:-not set}"
                if [[ -f "${FAKE_SITE_ROOT}/index.html" ]]; then
                    local sz; sz=$(wc -c < "${FAKE_SITE_ROOT}/index.html")
                    info "Page size: ${sz} bytes"
                fi
                ;;
            7) return ;;
            *) warn "Invalid option" ;;
        esac
        pause
    done
}

# =============================================================================
# MODULE 6: NGINX
# =============================================================================

build_nginx_config() {
    local location_blocks=""
    local i=0
    for path_raw in "${WS_PATHS[@]}"; do
        local port="${WS_PORTS[$i]//\"/}"
        local path_clean="${path_raw//\"/}"
        path_clean="${path_clean%%\?*}"
        location_blocks+="
    location ${path_clean} {
        if (\$http_upgrade != \"websocket\") { return 404; }
        proxy_pass          http://127.0.0.1:${port};
        proxy_http_version  1.1;
        proxy_set_header    Upgrade    \$http_upgrade;
        proxy_set_header    Connection \"upgrade\";
        proxy_set_header    Host       \$host;
        proxy_set_header    X-Real-IP  \$remote_addr;
        proxy_set_header    X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout  300s;
        proxy_send_timeout  300s;
    }"
        ((i++))
    done

    cat << NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT_FULLCHAIN};
    ssl_certificate_key ${CERT_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header Referrer-Policy no-referrer;

    root  ${FAKE_SITE_ROOT};
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
${location_blocks}
}
NGINXEOF
}

module_nginx_install() {
    step "Nginx Install & Configuration"
    if ! command -v nginx &>/dev/null; then
        info "Installing nginx..."
        apt-get update -qq && apt-get install -y nginx &>/dev/null
        systemctl enable nginx &>/dev/null
        success "Nginx installed"
    else
        success "Nginx already installed"
    fi

    # Generate site with random values if not yet done
    if [[ -z "$SITE_COMPANY" ]]; then
        local co_idx=$((RANDOM % 6))
        local sc_idx=$((RANDOM % 5))
        SITE_COMPANY="${CO_NAMES[$co_idx]}"
        SITE_TAGLINE="${CO_TAGLINES[$co_idx]}"
        SITE_SUB="${CO_SUBS[$co_idx]}"
        SITE_SLUG="${CO_SLUGS[$co_idx]}"
        SITE_SCHEME="$sc_idx"
    fi

    write_site_files "$FAKE_SITE_ROOT" \
        "$(for i in "${!CO_NAMES[@]}"; do [[ "${CO_NAMES[$i]}" == "$SITE_COMPANY" ]] && echo $i; done)" \
        "${SITE_SCHEME:-0}"

    # Write nginx config
    local cfg="${NGINX_SITES}/phi-${DOMAIN}"
    build_nginx_config > "$cfg"
    ln -sf "$cfg" "${NGINX_ENABLED}/phi-${DOMAIN}" 2>/dev/null
    rm -f "${NGINX_ENABLED}/default" 2>/dev/null

    if nginx -t &>/dev/null; then
        systemctl reload nginx
        success "Nginx configured and reloaded"
        success "Site: ${SITE_COMPANY} — ${SITE_TAGLINE}"
    else
        error "Nginx config invalid:"
        nginx -t
    fi
    save_config
}

module_nginx_manager() {
    while true; do
        print_banner
        step "Nginx Manager"
        divider
        echo ""
        echo "    1) Status"
        echo "    2) Reload"
        echo "    3) Restart"
        echo "    4) Edit domain config"
        echo "    5) View current config"
        echo "    6) Rebuild config from settings"
        echo "    7) Back"
        echo ""
        read -rp "  Select: " sel

        case "$sel" in
            1)
                echo ""
                systemctl status nginx --no-pager -l | head -20
                ;;
            2)
                nginx -t && systemctl reload nginx && success "Nginx reloaded"
                ;;
            3)
                systemctl restart nginx && success "Nginx restarted"
                ;;
            4)
                local cfg="${NGINX_SITES}/phi-${DOMAIN}"
                if [[ -f "$cfg" ]]; then
                    ${EDITOR:-nano} "$cfg"
                    nginx -t && systemctl reload nginx
                else
                    error "Config not found: $cfg"
                fi
                ;;
            5)
                local cfg="${NGINX_SITES}/phi-${DOMAIN}"
                if [[ -f "$cfg" ]]; then
                    echo ""
                    cat "$cfg"
                else
                    warn "No config file found at $cfg"
                fi
                ;;
            6)
                load_config
                local cfg="${NGINX_SITES}/phi-${DOMAIN}"
                build_nginx_config > "$cfg"
                ln -sf "$cfg" "${NGINX_ENABLED}/phi-${DOMAIN}" 2>/dev/null
                nginx -t && systemctl reload nginx && success "Config rebuilt and reloaded"
                ;;
            7) return ;;
            *) warn "Invalid" ;;
        esac
        pause
    done
}

# =============================================================================
# MODULE 7: V2BX NODE MANAGER
# =============================================================================

v2bx_list_nodes() {
    python3 -c "
import json, sys
try:
    d = json.load(open('$V2BX_CONFIG'))
    nodes = d.get('Nodes', [])
    if not nodes:
        print('  No nodes configured')
    for i, n in enumerate(nodes):
        print(f\"  [{i+1}] NodeID={n.get('NodeID','?'):>4}  Type={n.get('NodeType','?'):<12}  Core={n.get('Core','?'):<5}  ListenIP={n.get('ListenIP','?')}\")
except Exception as e:
    print(f'  Error reading config: {e}')
" 2>/dev/null
}

v2bx_get_node_by_id() {
    local node_id="$1"
    python3 -c "
import json
d = json.load(open('$V2BX_CONFIG'))
for n in d.get('Nodes', []):
    if str(n.get('NodeID')) == '$node_id':
        print(json.dumps(n, indent=2))
        break
" 2>/dev/null
}

v2bx_default_node_block() {
    local node_id="$1"
    local node_type="$2"
    local listen_ip="${3:-127.0.0.1}"
    local core="${4:-xray}"
    local cert_mode="${5:-none}"

    # Inherit ApiHost and ApiKey from first existing node
    local api_host api_key
    api_host=$(python3 -c "
import json
try:
    d=json.load(open('$V2BX_CONFIG'))
    print(d['Nodes'][0].get('ApiHost','https://web2.phicloudapp.com'))
except: print('https://web2.phicloudapp.com')
" 2>/dev/null)
    api_key=$(python3 -c "
import json
try:
    d=json.load(open('$V2BX_CONFIG'))
    print(d['Nodes'][0].get('ApiKey','YOUR_API_KEY'))
except: print('YOUR_API_KEY')
" 2>/dev/null)

    cat << BLOCKEOF
{
  "Core": "${core}",
  "ApiHost": "${api_host}",
  "ApiKey": "${api_key}",
  "NodeID": ${node_id},
  "NodeType": "${node_type}",
  "Timeout": 30,
  "ListenIP": "${listen_ip}",
  "SendIP": "0.0.0.0",
  "DeviceOnlineMinTraffic": 1024,
  "MinReportTraffic": 64,
  "EnableProxyProtocol": false,
  "EnableUot": true,
  "EnableTFO": true,
  "DNSType": "UseIPv4",
  "CertConfig": {
    "CertMode": "${cert_mode}",
    "RejectUnknownSni": false,
    "CertDomain": "example.com",
    "CertFile": "/etc/V2bX/fullchain.cer",
    "KeyFile": "/etc/V2bX/cert.key",
    "Email": "v2bx@github.com",
    "Provider": "cloudflare",
    "DNSEnv": {"EnvName": "env1"}
  }
}
BLOCKEOF
}

v2bx_write_node() {
    # Write or replace a node block by NodeID
    local node_json="$1"
    local node_id
    node_id=$(echo "$node_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['NodeID'])" 2>/dev/null)

    cp "$V2BX_CONFIG" "$V2BX_CONFIG_BAK"

    python3 -c "
import json, sys

with open('$V2BX_CONFIG') as f:
    d = json.load(f)

new_node = json.loads(sys.argv[1])
nid = new_node['NodeID']

# Replace if exists, else append
replaced = False
for i, n in enumerate(d.get('Nodes', [])):
    if n.get('NodeID') == nid:
        d['Nodes'][i] = new_node
        replaced = True
        break
if not replaced:
    d.setdefault('Nodes', []).append(new_node)

with open('$V2BX_CONFIG', 'w') as f:
    json.dump(d, f, indent=2)
print('ok')
" "$node_json" 2>/dev/null

    if python3 -m json.tool "$V2BX_CONFIG" &>/dev/null; then
        success "config.json updated (NodeID: $node_id)"
        return 0
    else
        error "JSON validation failed — restoring backup"
        cp "$V2BX_CONFIG_BAK" "$V2BX_CONFIG"
        return 1
    fi
}

v2bx_edit_node_interactive() {
    local node_id="$1"
    local node_json
    node_json=$(v2bx_get_node_by_id "$node_id")

    if [[ -z "$node_json" ]]; then
        error "NodeID $node_id not found"
        return
    fi

    while true; do
        print_banner
        step "Editing NodeID: $node_id"
        divider
        echo ""

        # Parse current values
        local cur_core cur_apihost cur_apikey cur_nodetype cur_listenip cur_sendip
        local cur_timeout cur_certmode cur_certdomain cur_certfile cur_keyfile
        local cur_email cur_provider cur_cf_email cur_cf_key
        eval "$(python3 -c "
import json
n = json.loads('''${node_json}''')
cc = n.get('CertConfig', {})
env = cc.get('DNSEnv', {})
print(f\"cur_core='{n.get('Core','xray')}'\")
print(f\"cur_apihost='{n.get('ApiHost','')}'\" )
print(f\"cur_apikey='{n.get('ApiKey','')}'\" )
print(f\"cur_nodetype='{n.get('NodeType','vless')}'\")
print(f\"cur_listenip='{n.get('ListenIP','0.0.0.0')}'\")
print(f\"cur_sendip='{n.get('SendIP','0.0.0.0')}'\")
print(f\"cur_timeout='{n.get('Timeout',30)}'\")
print(f\"cur_certmode='{cc.get('CertMode','none')}'\")
print(f\"cur_certdomain='{cc.get('CertDomain','')}'\" )
print(f\"cur_certfile='{cc.get('CertFile','')}'\" )
print(f\"cur_keyfile='{cc.get('KeyFile','')}'\" )
print(f\"cur_email='{cc.get('Email','')}'\" )
print(f\"cur_provider='{cc.get('Provider','cloudflare')}'\")
print(f\"cur_cf_email='{env.get('CLOUDFLARE_EMAIL','')}'\" )
print(f\"cur_cf_key='{env.get('CLOUDFLARE_API_KEY','')}'\" )
" 2>/dev/null)"

        echo "   1)  Core          [${cur_core}]"
        echo "   2)  ApiHost       [${cur_apihost}]"
        echo "   3)  ApiKey        [${cur_apikey:0:8}...]"
        echo "   4)  NodeType      [${cur_nodetype}]"
        echo "   5)  ListenIP      [${cur_listenip}]"
        echo "   6)  SendIP        [${cur_sendip}]"
        echo "   7)  Timeout       [${cur_timeout}]"
        echo "   8)  CertMode      [${cur_certmode}]"
        echo "   9)  CertDomain    [${cur_certdomain}]"
        echo "  10)  CertFile      [${cur_certfile}]"
        echo "  11)  KeyFile       [${cur_keyfile}]"
        echo "  12)  Email         [${cur_email}]"
        echo "  13)  Provider      [${cur_provider}]"
        echo "  14)  CF Email      [${cur_cf_email}]"
        echo "  15)  CF API Key    [${cur_cf_key:0:8}...]"
        echo "  16)  Save & Exit"
        echo "  17)  Cancel"
        echo ""
        read -rp "  Field to edit: " field_sel

        case "$field_sel" in
            1)  read -rp "  Core [xray/sing] (${cur_core}): " v; [[ -n "$v" ]] && cur_core="$v" ;;
            2)  read -rp "  ApiHost (${cur_apihost}): " v; [[ -n "$v" ]] && cur_apihost="$v" ;;
            3)  read -rp "  ApiKey: " v; [[ -n "$v" ]] && cur_apikey="$v" ;;
            4)  read -rp "  NodeType [vless/trojan/hysteria2/anytls] (${cur_nodetype}): " v; [[ -n "$v" ]] && cur_nodetype="$v" ;;
            5)  read -rp "  ListenIP (${cur_listenip}): " v; [[ -n "$v" ]] && cur_listenip="$v" ;;
            6)  read -rp "  SendIP (${cur_sendip}): " v; [[ -n "$v" ]] && cur_sendip="$v" ;;
            7)  read -rp "  Timeout (${cur_timeout}): " v; [[ -n "$v" ]] && cur_timeout="$v" ;;
            8)  read -rp "  CertMode [none/dns/http/file] (${cur_certmode}): " v; [[ -n "$v" ]] && cur_certmode="$v" ;;
            9)  read -rp "  CertDomain (${cur_certdomain}): " v; [[ -n "$v" ]] && cur_certdomain="$v" ;;
            10) read -rp "  CertFile (${cur_certfile}): " v; [[ -n "$v" ]] && cur_certfile="$v" ;;
            11) read -rp "  KeyFile (${cur_keyfile}): " v; [[ -n "$v" ]] && cur_keyfile="$v" ;;
            12) read -rp "  Email (${cur_email}): " v; [[ -n "$v" ]] && cur_email="$v" ;;
            13) read -rp "  Provider (${cur_provider}): " v; [[ -n "$v" ]] && cur_provider="$v" ;;
            14) read -rp "  CF Email (${cur_cf_email}): " v; [[ -n "$v" ]] && cur_cf_email="$v" ;;
            15) read -rp "  CF API Key: " v; [[ -n "$v" ]] && cur_cf_key="$v" ;;
            16)
                # Build updated JSON
                node_json=$(python3 -c "
import json
n = {
  'Core': '${cur_core}',
  'ApiHost': '${cur_apihost}',
  'ApiKey': '${cur_apikey}',
  'NodeID': ${node_id},
  'NodeType': '${cur_nodetype}',
  'Timeout': ${cur_timeout},
  'ListenIP': '${cur_listenip}',
  'SendIP': '${cur_sendip}',
  'DeviceOnlineMinTraffic': 1024,
  'MinReportTraffic': 64,
  'EnableProxyProtocol': False,
  'EnableUot': True,
  'EnableTFO': True,
  'DNSType': 'UseIPv4',
  'CertConfig': {
    'CertMode': '${cur_certmode}',
    'RejectUnknownSni': False,
    'CertDomain': '${cur_certdomain}',
    'CertFile': '${cur_certfile}',
    'KeyFile': '${cur_keyfile}',
    'Email': '${cur_email}',
    'Provider': '${cur_provider}',
    'DNSEnv': {
      'CLOUDFLARE_EMAIL': '${cur_cf_email}',
      'CLOUDFLARE_API_KEY': '${cur_cf_key}'
    }
  }
}
print(json.dumps(n, indent=2))
" 2>/dev/null)
                v2bx_write_node "$node_json"
                return
                ;;
            17) return ;;
            *) warn "Invalid" ;;
        esac
    done
}

module_v2bx_manager() {
    while true; do
        print_banner
        load_config
        step "V2bX Node Manager"
        divider
        echo ""

        if [[ ! -f "$V2BX_CONFIG" ]]; then
            error "V2bX config not found at $V2BX_CONFIG"
            pause; return
        fi

        echo "  Current nodes:"
        v2bx_list_nodes
        echo ""
        echo "    1) Add new node"
        echo "    2) Edit existing node"
        echo "    3) Remove node"
        echo "    4) Restart V2bX"
        echo "    5) View raw config.json"
        echo "    6) Back"
        echo ""
        read -rp "  Select: " sel

        case "$sel" in
            1)
                echo ""
                read -rp "  NodeID (from Xboard): " node_id
                while [[ -z "$node_id" || ! "$node_id" =~ ^[0-9]+$ ]]; do
                    error "NodeID must be a number"
                    read -rp "  NodeID: " node_id
                done

                echo ""
                echo "  Node type:"
                echo "    1) VLESS-WS  (ListenIP: 127.0.0.1, CertMode: none)"
                echo "    2) Trojan-WS (ListenIP: 127.0.0.1, CertMode: none)"
                echo "    3) VLESS-Reality (ListenIP: 0.0.0.0, CertMode: none)"
                echo "    4) Hysteria2 (ListenIP: ::, CertMode: dns)"
                echo "    5) AnyTLS    (ListenIP: ::, CertMode: dns)"
                echo "    6) Custom"
                read -rp "  Select [1]: " ntype_sel

                local node_type listen_ip core cert_mode
                case "${ntype_sel:-1}" in
                    1) node_type="vless";     listen_ip="127.0.0.1"; core="xray"; cert_mode="none" ;;
                    2) node_type="trojan";    listen_ip="127.0.0.1"; core="xray"; cert_mode="none" ;;
                    3) node_type="vless";     listen_ip="0.0.0.0";   core="xray"; cert_mode="none" ;;
                    4) node_type="hysteria2"; listen_ip="::";        core="sing"; cert_mode="dns"  ;;
                    5) node_type="anytls";    listen_ip="::";        core="sing"; cert_mode="dns"  ;;
                    6)
                        read -rp "  NodeType: " node_type
                        read -rp "  ListenIP [0.0.0.0]: " listen_ip; listen_ip="${listen_ip:-0.0.0.0}"
                        read -rp "  Core [xray/sing]: " core; core="${core:-xray}"
                        read -rp "  CertMode [none/dns]: " cert_mode; cert_mode="${cert_mode:-none}"
                        ;;
                esac

                local node_json
                node_json=$(v2bx_default_node_block "$node_id" "$node_type" "$listen_ip" "$core" "$cert_mode")

                echo ""
                info "Node to be added:"
                echo "$node_json"
                echo ""

                if confirm "Add this node to config.json?"; then
                    if v2bx_write_node "$node_json"; then
                        echo ""
                        warn "IMPORTANT: Add NodeID ${node_id} in Xboard BEFORE restarting V2bX"
                        warn "V2bX will fail to start if the node does not exist in Xboard"
                        echo ""
                        if confirm "Have you already added NodeID ${node_id} in Xboard?"; then
                            systemctl restart V2bX
                            sleep 2
                            if systemctl is-active --quiet V2bX; then
                                success "V2bX restarted successfully"
                            else
                                error "V2bX failed — check: journalctl -u V2bX -n 30"
                            fi
                        else
                            info "Node added to config.json — restart V2bX after adding in Xboard"
                            info "Restart command: systemctl restart V2bX"
                        fi
                    fi
                fi
                ;;
            2)
                echo ""
                read -rp "  Enter NodeID to edit: " edit_id
                [[ -n "$edit_id" ]] && v2bx_edit_node_interactive "$edit_id"
                ;;
            3)
                echo ""
                read -rp "  Enter NodeID to remove: " del_id
                if [[ -n "$del_id" ]]; then
                    confirm "Remove NodeID ${del_id} from config.json?" || { pause; continue; }
                    cp "$V2BX_CONFIG" "$V2BX_CONFIG_BAK"
                    python3 -c "
import json
with open('$V2BX_CONFIG') as f: d = json.load(f)
d['Nodes'] = [n for n in d.get('Nodes',[]) if str(n.get('NodeID')) != '$del_id']
with open('$V2BX_CONFIG','w') as f: json.dump(d, f, indent=2)
print('ok')
" && success "NodeID $del_id removed"
                    confirm "Restart V2bX now?" && systemctl restart V2bX
                fi
                ;;
            4)
                systemctl restart V2bX
                sleep 2
                if systemctl is-active --quiet V2bX; then
                    success "V2bX running"
                else
                    error "V2bX failed — check: journalctl -u V2bX -n 30"
                fi
                ;;
            5)
                echo ""
                python3 -m json.tool "$V2BX_CONFIG" 2>/dev/null || cat "$V2BX_CONFIG"
                ;;
            6) return ;;
            *) warn "Invalid" ;;
        esac
        pause
    done
}

# =============================================================================
# MODULE 8: STATUS & VERIFICATION
# =============================================================================

module_status() {
    print_banner
    load_config
    step "Status & Verification"
    divider
    echo ""

    # Services
    for svc in nginx V2bX; do
        if systemctl is-active --quiet $svc 2>/dev/null; then
            success "$svc: running"
        else
            error "$svc: NOT running"
        fi
    done

    # Port 443
    if ss -tlnp | grep -q ':443'; then
        local proc; proc=$(ss -tlnp | grep ':443' | grep -oP 'users:\(\("\K[^"]+' | head -1)
        success "Port 443: listening (${proc})"
    else
        error "Port 443: NOT listening"
    fi

    # Cert expiry
    if [[ -n "$CERT_FULLCHAIN" && -f "$CERT_FULLCHAIN" ]]; then
        local exp; exp=$(openssl x509 -in "$CERT_FULLCHAIN" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
        info "Cert expires: $exp"
    fi

    # Internal ports
    echo ""
    local i=0
    for path_raw in "${WS_PATHS[@]}"; do
        local port="${WS_PORTS[$i]//\"/}"
        local type="${WS_TYPES[$i]//\"/}"
        local path_clean="${path_raw//\"/}"
        if ss -tlnp | grep -q ":${port}"; then
            success "Internal port ${port} (${type}): listening"
        else
            warn "Internal port ${port} (${type}): NOT listening — V2bX node may not be registered"
        fi
        ((i++))
    done

    # Test HTTPS
    echo ""
    local http_code
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
        --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/" 2>/dev/null)
    info "Fake site HTTP status: ${http_code:-curl failed}"

    # Xboard config summary
    echo ""
    divider
    echo -e "  ${BOLD}${GREEN}XBOARD NODE CONFIG — COPY THESE${NC}"
    divider
    i=0
    for path_raw in "${WS_PATHS[@]}"; do
        local port="${WS_PORTS[$i]//\"/}"
        local type="${WS_TYPES[$i]//\"/}"
        local path="${path_raw//\"/}"
        echo ""
        echo -e "  ${CYAN}Node $((i+1)) — ${type^^}-WS${NC}"
        echo "  ┌──────────────────────────────────────────────────"
        echo "  │ Type:          ${type}"
        echo "  │ Domain:        ${DOMAIN}"
        echo "  │ Port:          443"
        echo "  │ Transport:     WebSocket"
        echo "  │ Path:          ${path}"
        echo "  │ TLS:           ON"
        echo "  │ Listen IP:     127.0.0.1  ← set in V2bX config"
        echo "  │ Server Port:   ${port}  ← Xboard server port field"
        echo "  └──────────────────────────────────────────────────"
        ((i++))
    done
    echo ""
    divider
    pause
}

# =============================================================================
# MODULE 9: HOOKS
# =============================================================================

module_hooks() {
    mkdir -p /etc/systemd/system/V2bX.service.d/
    cat > /etc/systemd/system/V2bX.service.d/nginx-reload.conf << 'EOF'
[Service]
ExecStartPost=/bin/sh -c 'sleep 3 && systemctl reload nginx'
EOF
    systemctl daemon-reload
    success "Auto-reload hook: nginx reloads 3s after V2bX starts"
}

# =============================================================================
# MODULE 10: UNINSTALL
# =============================================================================

module_uninstall() {
    while true; do
        print_banner
        load_config
        step "Uninstall"
        divider
        echo ""
        echo "    1) Remove this domain config only"
        echo "       (nginx site config + fake site, nginx stays installed)"
        echo ""
        echo "    2) Remove nginx completely"
        echo "       (purge nginx, all configs, all fake sites)"
        echo ""
        echo "    3) Remove a V2bX node from config.json"
        echo ""
        echo "    4) Full cleanup"
        echo "       (everything above + phi-nginx command + config dir)"
        echo ""
        echo "    5) Back"
        echo ""
        read -rp "  Select: " sel

        case "$sel" in
            1)
                confirm "Remove domain config for ${DOMAIN}?" || { pause; continue; }
                rm -f "${NGINX_SITES}/phi-${DOMAIN}" "${NGINX_ENABLED}/phi-${DOMAIN}"
                [[ -n "$FAKE_SITE_ROOT" ]] && rm -rf "$FAKE_SITE_ROOT"
                nginx -t &>/dev/null && systemctl reload nginx
                success "Domain config removed. Nginx still running."
                ;;
            2)
                confirm "REMOVE NGINX COMPLETELY? This affects ALL sites on this server." || { pause; continue; }
                local purge=false
                confirm "Purge nginx (remove config files too)?" && purge=true
                systemctl stop nginx 2>/dev/null
                if $purge; then
                    apt-get purge -y nginx nginx-common &>/dev/null
                    rm -rf /etc/nginx
                else
                    apt-get remove -y nginx &>/dev/null
                fi
                rm -rf /var/www/phi-fake
                rm -f /etc/systemd/system/V2bX.service.d/nginx-reload.conf
                systemctl daemon-reload
                success "Nginx removed"
                ;;
            3)
                echo ""
                echo "  Current nodes:"
                v2bx_list_nodes
                echo ""
                read -rp "  NodeID to remove: " del_id
                if [[ -n "$del_id" ]]; then
                    confirm "Remove NodeID ${del_id}?" || { pause; continue; }
                    cp "$V2BX_CONFIG" "$V2BX_CONFIG_BAK"
                    python3 -c "
import json
with open('$V2BX_CONFIG') as f: d=json.load(f)
d['Nodes']=[n for n in d.get('Nodes',[]) if str(n.get('NodeID'))!='$del_id']
with open('$V2BX_CONFIG','w') as f: json.dump(d,f,indent=2)
" && success "NodeID $del_id removed"
                    confirm "Restart V2bX?" && systemctl restart V2bX
                fi
                ;;
            4)
                confirm "FULL CLEANUP — remove everything phi-nginx installed?" || { pause; continue; }
                # Domain config
                [[ -n "$DOMAIN" ]] && rm -f "${NGINX_SITES}/phi-${DOMAIN}" "${NGINX_ENABLED}/phi-${DOMAIN}"
                # Fake sites
                rm -rf /var/www/phi-fake
                # Hooks
                rm -f /etc/systemd/system/V2bX.service.d/nginx-reload.conf
                systemctl daemon-reload
                # Certbot hook
                rm -f /etc/letsencrypt/renewal-hooks/deploy/phi-nginx-reload.sh
                # Config dir
                rm -rf "$CONFIG_DIR"
                # System command
                rm -f /usr/local/bin/phi-nginx
                # Reload nginx if still running
                systemctl is-active --quiet nginx && nginx -t &>/dev/null && systemctl reload nginx
                success "Full cleanup complete"
                warn "Nginx itself was NOT removed — use option 2 if you want to remove it"
                ;;
            5) return ;;
            *) warn "Invalid" ;;
        esac
        pause
    done
}

# =============================================================================
# FULL SETUP
# =============================================================================

full_setup() {
    print_banner
    step "Full Setup"
    divider
    echo ""
    info "Runs all modules in sequence: Config → Cert → Nginx → V2bX → Hooks"
    echo ""
    confirm "Start full setup?" || return

    WS_PATHS=(); WS_PORTS=(); WS_TYPES=()
    SITE_COMPANY=""; SITE_SCHEME=""

    module_config
    module_cert
    module_nginx_install
    module_v2bx_manager
    module_hooks
    module_status
}

# =============================================================================
# INSTALL AS SYSTEM COMMAND
# =============================================================================

install_command() {
    local src; src=$(realpath "$0")
    cp "$src" /usr/local/bin/phi-nginx
    chmod +x /usr/local/bin/phi-nginx
    success "Installed: phi-nginx"
    info "Run from anywhere: phi-nginx"
}

# =============================================================================
# MAIN MENU
# =============================================================================

main_menu() {
    while true; do
        print_banner
        load_config

        echo -e "  ${BOLD}Main Menu${NC}"
        echo ""
        echo "    1)  Full Setup"
        echo "    2)  Website Management"
        echo "    3)  Add WS Path"
        echo "    4)  Certificate Management"
        echo "    5)  V2bX Node Manager"
        echo "    6)  Nginx Manager"
        echo "    7)  Status & Verification"
        echo "    8)  Uninstall"
        echo "    9)  Environment Info"
        echo "    10) Install as system command"
        echo "    0)  Exit"
        echo ""

        if [[ -n "$DOMAIN" ]]; then
            echo -e "  ${YELLOW}Domain: ${DOMAIN}${NC}"
            [[ -n "$SITE_COMPANY" ]] && echo -e "  ${YELLOW}Site:   ${SITE_COMPANY} — ${SITE_TAGLINE}${NC}"
            echo -e "  ${YELLOW}Paths:  ${#WS_PATHS[@]} configured${NC}"
            echo ""
        fi

        read -rp "  Select: " choice
        echo ""

        case "$choice" in
            1)  full_setup ;;
            2)  module_website ;;
            3)
                load_config
                local old_count=${#WS_PATHS[@]}
                module_config
                # Rebuild nginx with new path
                if [[ ${#WS_PATHS[@]} -gt $old_count ]]; then
                    local cfg="${NGINX_SITES}/phi-${DOMAIN}"
                    build_nginx_config > "$cfg"
                    nginx -t &>/dev/null && systemctl reload nginx && success "Nginx updated with new path"
                fi
                ;;
            4)  module_cert ;;
            5)  module_v2bx_manager ;;
            6)  module_nginx_manager ;;
            7)  module_status ;;
            8)  module_uninstall ;;
            9)  module_detect ;;
            10) install_command; pause ;;
            0)  echo "  Goodbye."; exit 0 ;;
            *)  warn "Invalid option" ;;
        esac
    done
}

# =============================================================================
# ENTRY
# =============================================================================

require_root
main_menu
