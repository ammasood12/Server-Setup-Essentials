#!/usr/bin/env bash
# ==============================================================================
# Cloudflare DNS Manager + DDNS + Cron Manager
# Version: 2.0.0
#
# What this does:
#   - Manage Cloudflare DNS records (list/add/update/delete)
#   - DDNS updater (update A record to current public IPv4)
#   - Cron install/remove for DDNS
#
# Where to get values:
#   API Token:
#     Cloudflare Dashboard → My Profile → API Tokens → Create Token
#     Template: Edit zone DNS
#     Permissions:
#       - Zone → DNS → Edit
#       - Zone → Zone → Read
#     Zone Resources:
#       - Include → Specific zone → select your domain
#
#   Zone ID:
#     Cloudflare Dashboard → Websites → (your domain) → Overview → Zone ID
#
# Notes:
#   - Config saved in: /etc/cf-manager.conf
#   - Updater script installed to: /usr/local/bin/cf-ddns.sh
#   - Cron log (optional): /var/log/cf-ddns.log
# ==============================================================================

set -euo pipefail

VERSION="v2.0"
APP_NAME="Cloudflare Manager"

# ---------------------------- Defaults / Paths ------------------------------
CF_API="https://api.cloudflare.com/client/v4"
CONF_PATH="/etc/cf-manager.conf"
UPDATER_PATH="/usr/local/bin/cf-ddns.sh"
CRON_LOG="/var/log/cf-ddns.log"

# Defaults for new records / updates
DEFAULT_TTL=120
DEFAULT_PROXIED=false

# ------------------------------- Colors -------------------------------------
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m"
MAGENTA="\033[35m"; CYAN="\033[36m"; WHITE="\033[37m"; RESET="\033[0m"
BOLD="\033[1m"; DIM="\033[2m"; UNDERLINE="\033[4m"

log()  { echo -e "${GREEN}[+]${RESET} $1"; }
warn() { echo -e "${YELLOW}[!]${RESET} $1"; }
err()  { echo -e "${RED}[-]${RESET} $1"; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then err "Run as root (sudo)."; fi
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || err "Missing dependency: $1. Install it (apt install -y $1)."
}

install_deps() {
  log "Installing dependencies (curl, jq, cron, dnsutils)"
  apt update -qq
  apt install -y curl jq cron dnsutils
  systemctl enable --now cron >/dev/null 2>&1 || true
}

# ------------------------------ Config --------------------------------------
load_conf() {
  if [[ -f "$CONF_PATH" ]]; then
    # shellcheck disable=SC1090
    source "$CONF_PATH"
  fi

  CF_TOKEN="${CF_TOKEN:-}"
  ZONE_ID="${ZONE_ID:-}"
}

save_conf() {
  umask 077
  cat > "$CONF_PATH" <<EOF
# Cloudflare Manager config
CF_TOKEN='$CF_TOKEN'
ZONE_ID='$ZONE_ID'
EOF
  log "Saved config to $CONF_PATH"
}

prompt_conf() {
  echo
  echo "=== Cloudflare Config ==="
  read -rp "Cloudflare API Token: " CF_TOKEN
  read -rp "Zone ID: " ZONE_ID
  [[ -z "$CF_TOKEN" || -z "$ZONE_ID" ]] && err "Token and Zone ID cannot be empty."
  save_conf
}

ensure_conf() {
  load_conf
  if [[ -z "${CF_TOKEN:-}" || -z "${ZONE_ID:-}" ]]; then
    prompt_conf
  fi
}

# ------------------------- Public IP (IPv4) ---------------------------------
get_public_ipv4() {
  local ip=""
  for u in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://ipv4.icanhazip.com" \
    "https://checkip.amazonaws.com"
  do
    ip="$(curl -4 -fsS --max-time 10 "$u" 2>/dev/null | tr -d ' \n\r' || true)"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { echo "$ip"; return 0; }
  done
  return 1
}

# -------------------------- Cloudflare API ----------------------------------
cf_get() {
  curl -fsS -X GET "$1" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json"
}

cf_post() {
  curl -fsS -X POST "$1" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$2"
}

cf_put() {
  curl -fsS -X PUT "$1" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$2"
}

cf_delete() {
  curl -fsS -X DELETE "$1" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json"
}

cf_ok_or_die() {
  local resp="$1"
  local ok
  ok="$(echo "$resp" | jq -r '.success')"
  if [[ "$ok" != "true" ]]; then
    warn "Cloudflare response:"
    echo "$resp" | jq .
    err "Cloudflare API call failed (token perms / zone scope / zone id?)."
  fi
}

# --------------------------- DNS Operations ---------------------------------
dns_list() {
  ensure_conf
  echo
  read -rp "Filter by name (blank for all): " NAME
  local url="$CF_API/zones/$ZONE_ID/dns_records?per_page=100"
  [[ -n "${NAME:-}" ]] && url="$url&name=$NAME"

  local resp
  resp="$(cf_get "$url")"
  cf_ok_or_die "$resp"

  echo
  echo "=== DNS Records ==="
  echo "$resp" | jq -r '.result[] | "\(.type)\t\(.name)\t\(.content)\tTTL=\(.ttl)\tproxied=\(.proxied)\tID=\(.id)"' \
    | sed '/^$/d' || true
}

dns_find_id() {
  # args: type name
  local type="$1" name="$2"
  local resp id
  resp="$(cf_get "$CF_API/zones/$ZONE_ID/dns_records?type=$type&name=$name&per_page=1" || true)"
  id="$(echo "$resp" | jq -r '.result[0].id // empty')"
  echo "$id"
}

dns_get_record() {
  # args: record_id
  local rid="$1"
  cf_get "$CF_API/zones/$ZONE_ID/dns_records/$rid"
}

dns_create() {
  ensure_conf
  echo
  echo "=== Create DNS Record ==="
  read -rp "Type (A/AAAA/CNAME/TXT) [A]: " TYPE
  TYPE="${TYPE:-A}"
  read -rp "Name (full hostname, e.g. sub.example.com): " NAME
  read -rp "Content (IP/target/text): " CONTENT
  read -rp "TTL seconds [${DEFAULT_TTL}]: " TTL
  TTL="${TTL:-$DEFAULT_TTL}"
  read -rp "Proxied (true/false) [${DEFAULT_PROXIED}]: " PROXIED
  PROXIED="${PROXIED:-$DEFAULT_PROXIED}"

  [[ -z "$NAME" || -z "$CONTENT" ]] && err "Name and Content required."

  local payload resp
  payload="$(jq -nc \
    --arg type "$TYPE" \
    --arg name "$NAME" \
    --arg content "$CONTENT" \
    --argjson ttl "$TTL" \
    --argjson proxied "$PROXIED" \
    '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"

  resp="$(cf_post "$CF_API/zones/$ZONE_ID/dns_records" "$payload")"
  cf_ok_or_die "$resp"
  log "Created: $TYPE $NAME -> $CONTENT"
}

dns_update() {
  ensure_conf
  echo
  echo "=== Update DNS Record ==="
  read -rp "Record ID (preferred) OR press Enter to search by name: " RID

  if [[ -z "${RID:-}" ]]; then
    read -rp "Type (A/AAAA/CNAME/TXT) [A]: " TYPE
    TYPE="${TYPE:-A}"
    read -rp "Name (full hostname): " NAME
    [[ -z "$NAME" ]] && err "Name required."
    RID="$(dns_find_id "$TYPE" "$NAME")"
    [[ -z "$RID" ]] && err "Record not found."
  fi

  local current content type name ttl prox
  current="$(dns_get_record "$RID")"
  cf_ok_or_die "$current"

  type="$(echo "$current" | jq -r '.result.type')"
  name="$(echo "$current" | jq -r '.result.name')"
  content="$(echo "$current" | jq -r '.result.content')"
  ttl="$(echo "$current" | jq -r '.result.ttl')"
  prox="$(echo "$current" | jq -r '.result.proxied')"

  echo
  echo "Current: $type $name -> $content (TTL=$ttl proxied=$prox)"
  read -rp "New Content (blank keep current): " NEW_CONTENT
  read -rp "New TTL (blank keep $ttl): " NEW_TTL
  read -rp "New Proxied true/false (blank keep $prox): " NEW_PROX

  NEW_CONTENT="${NEW_CONTENT:-$content}"
  NEW_TTL="${NEW_TTL:-$ttl}"
  NEW_PROX="${NEW_PROX:-$prox}"

  local payload resp
  payload="$(jq -nc \
    --arg type "$type" \
    --arg name "$name" \
    --arg content "$NEW_CONTENT" \
    --argjson ttl "$NEW_TTL" \
    --argjson proxied "$NEW_PROX" \
    '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"

  resp="$(cf_put "$CF_API/zones/$ZONE_ID/dns_records/$RID" "$payload")"
  cf_ok_or_die "$resp"
  log "Updated: $name -> $NEW_CONTENT"
}

dns_delete() {
  ensure_conf
  echo
  echo "=== Delete DNS Record ==="
  read -rp "Record ID (preferred) OR press Enter to search by name: " RID

  if [[ -z "${RID:-}" ]]; then
    read -rp "Type (A/AAAA/CNAME/TXT) [A]: " TYPE
    TYPE="${TYPE:-A}"
    read -rp "Name (full hostname): " NAME
    [[ -z "$NAME" ]] && err "Name required."
    RID="$(dns_find_id "$TYPE" "$NAME")"
    [[ -z "$RID" ]] && err "Record not found."
  fi

  local current name type
  current="$(dns_get_record "$RID")"
  cf_ok_or_die "$current"
  type="$(echo "$current" | jq -r '.result.type')"
  name="$(echo "$current" | jq -r '.result.name')"

  echo "About to delete: $type $name (ID=$RID)"
  read -rp "Type DELETE to confirm: " CONFIRM
  [[ "$CONFIRM" != "DELETE" ]] && err "Cancelled."

  local resp
  resp="$(cf_delete "$CF_API/zones/$ZONE_ID/dns_records/$RID")"
  cf_ok_or_die "$resp"
  log "Deleted: $type $name"
}

# --------------------------- DDNS Operations --------------------------------
ddns_ensure_record() {
  # Ensures A record exists; returns RECORD_ID via stdout
  # args: hostname
  local hostname="$1"
  local rid
  rid="$(dns_find_id "A" "$hostname")"
  if [[ -n "$rid" ]]; then
    echo "$rid"; return 0
  fi

  warn "A record not found for $hostname. Creating it..."
  local ip payload resp new_id
  ip="$(get_public_ipv4 || true)"
  [[ -z "${ip:-}" ]] && ip="0.0.0.0"

  payload="$(jq -nc \
    --arg type "A" \
    --arg name "$hostname" \
    --arg content "$ip" \
    --argjson ttl "$DEFAULT_TTL" \
    --argjson proxied "$DEFAULT_PROXIED" \
    '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"

  resp="$(cf_post "$CF_API/zones/$ZONE_ID/dns_records" "$payload")"
  cf_ok_or_die "$resp"
  new_id="$(echo "$resp" | jq -r '.result.id')"
  log "Created A record: $hostname (ID=$new_id)"
  echo "$new_id"
}

ddns_write_updater() {
  ensure_conf
  echo
  echo "=== Install/Update DDNS Updater ==="
  read -rp "Hostname to DDNS (A record) e.g. home.example.com: " HOST
  [[ -z "$HOST" ]] && err "Hostname required."

  local rid
  rid="$(ddns_ensure_record "$HOST")"

  cat > "$UPDATER_PATH" <<EOF
#!/usr/bin/env bash
set -euo pipefail

CF_API="$CF_API"
CF_TOKEN="$CF_TOKEN"
ZONE_ID="$ZONE_ID"
RECORD_ID="$rid"
RECORD_NAME="$HOST"

get_public_ipv4() {
  local ip=""
  for u in "https://api.ipify.org" "https://ifconfig.me/ip" "https://ipv4.icanhazip.com" "https://checkip.amazonaws.com"
  do
    ip=\$(curl -4 -fsS --max-time 10 "\$u" 2>/dev/null | tr -d ' \\n\\r' || true)
    [[ "\$ip" =~ ^([0-9]{1,3}\\.){3}[0-9]{1,3}\$ ]] && { echo "\$ip"; return 0; }
  done
  return 1
}

IP=\$(get_public_ipv4 || true)
[[ -z "\${IP:-}" ]] && exit 0

OLD_IP=\$(curl -fsS -X GET "\$CF_API/zones/\$ZONE_ID/dns_records/\$RECORD_ID" \\
  -H "Authorization: Bearer \$CF_TOKEN" \\
  -H "Content-Type: application/json" | jq -r '.result.content')

[[ "\$IP" == "\$OLD_IP" ]] && exit 0

payload=\$(jq -nc --arg type "A" --arg name "\$RECORD_NAME" --arg content "\$IP" --argjson ttl $DEFAULT_TTL --argjson proxied $DEFAULT_PROXIED \\
  '{type:\$type,name:\$name,content:\$content,ttl:\$ttl,proxied:\$proxied}')

curl -fsS -X PUT "\$CF_API/zones/\$ZONE_ID/dns_records/\$RECORD_ID" \\
  -H "Authorization: Bearer \$CF_TOKEN" \\
  -H "Content-Type: application/json" \\
  --data "\$payload" >/dev/null
EOF

  chmod +x "$UPDATER_PATH"
  log "Updater written to $UPDATER_PATH"
  log "DDNS target: $HOST (Record ID: $rid)"
}

ddns_run_once() {
  [[ -x "$UPDATER_PATH" ]] || err "Updater not installed yet. Choose: DDNS → Install/Update Updater"
  log "Running updater once..."
  bash "$UPDATER_PATH"
  log "Done."
}

# ---------------------------- Cron Operations --------------------------------
cron_install() {
  [[ -x "$UPDATER_PATH" ]] || err "Updater not installed yet. Install it first."
  echo
  echo "=== Install Cron for DDNS ==="
  read -rp "Interval minutes (10/15/30) [10]: " MIN
  MIN="${MIN:-10}"
  case "$MIN" in 10|15|30) ;; *) err "Only 10/15/30 supported." ;; esac

  local line="*/$MIN * * * * $UPDATER_PATH >> $CRON_LOG 2>&1"
  crontab -l 2>/dev/null | grep -v "$UPDATER_PATH" > /tmp/cron.tmp || true
  echo "$line" >> /tmp/cron.tmp
  crontab /tmp/cron.tmp
  rm -f /tmp/cron.tmp

  log "Cron installed: every $MIN minutes"
  log "Log file: $CRON_LOG"
}

cron_view() {
  echo
  echo "=== Current Crontab ==="
  crontab -l 2>/dev/null || echo "(no crontab)"
}

cron_remove() {
  echo
  echo "=== Remove DDNS Cron ==="
  crontab -l 2>/dev/null | grep -v "$UPDATER_PATH" > /tmp/cron.tmp || true
  crontab /tmp/cron.tmp || true
  rm -f /tmp/cron.tmp
  log "Removed cron entries for: $UPDATER_PATH"
}

# ------------------------------- Menu ---------------------------------------
menu() {
echo
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════"
echo -e "              	$APP_NAME $VERSION"
echo -e "════════════════════════════════════════════════════════════════${RESET}"
echo
# Show current public IP
echo -n "  Current Public IP: "
curl -4 -s --max-time 3 https://ifconfig.me 2>/dev/null || echo "Could not fetch"
echo
# echo -e "==================== Cloudflare DNS / DDNS Manager ===================="
  cat <<'EOF'
1) Configure (Token + Zone ID)

Configure DNS
2) List records        4) Update record
3) Create record       5) Delete record

Configure DDNS (AUTO update ip to cloudflare)
6) Install/Update updater script
7) Run updater once

CRON Job
8) Install DDNS cron
9) View crontab       10) Remove DDNS cron

0) Exit

EOF
echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
}

main() {
  require_root
  need_bin curl
  need_bin jq

  while true; do
    menu
    read -rp "Choose: " CH
    case "$CH" in
      1) prompt_conf ;;
      2) dns_list ;;
      3) dns_create ;;
      4) dns_update ;;
      5) dns_delete ;;
      6) ddns_write_updater ;;
      7) ensure_conf; ddns_run_once ;;
      8) ensure_conf; cron_install ;;
      9) cron_view ;;
      10) cron_remove ;;
      0) exit 0 ;;
      *) warn "Invalid option." ;;
    esac
  done
}

main
