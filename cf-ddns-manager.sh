#!/usr/bin/env bash
# =========================================================
# Cloudflare DDNS Manager (NAT Friendly)
# Auto-fetch Record ID
# Version: 1.1.0
# =========================================================

set -e

### GLOBALS ###
CF_API="https://api.cloudflare.com/client/v4"
BIN_PATH="/usr/local/bin/cf-ddns.sh"
CRON_INTERVAL="*/10 * * * *"

### COLORS ###
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

### UTIL ###
log() { echo -e "${GREEN}[+]${RESET} $1"; }
warn() { echo -e "${YELLOW}[!]${RESET} $1"; }
err() { echo -e "${RED}[-]${RESET} $1"; exit 1; }

### ROOT CHECK ###
check_root() {
  [[ $EUID -ne 0 ]] && err "Run as root"
}

### DEPENDENCIES ###
install_deps() {
  log "Installing dependencies"
  apt update -qq
  apt install -y curl jq cron dnsutils
  systemctl enable --now cron
}

### INPUT ###
collect_inputs() {
  read -rp "Cloudflare API Token: " CF_TOKEN
  read -rp "Zone ID: " ZONE_ID
  read -rp "Record Name (sub.domain.com): " RECORD_NAME

  echo
  read -rp "Cron interval (10 / 15 / 30 minutes) [10]: " MIN
  case "$MIN" in
    15) CRON_INTERVAL="*/15 * * * *" ;;
    30) CRON_INTERVAL="*/30 * * * *" ;;
    *)  CRON_INTERVAL="*/10 * * * *" ;;
  esac
}

### FETCH RECORD ID ###
fetch_record_id() {
  log "Fetching Record ID from Cloudflare"

  RECORD_ID=$(curl -s -X GET \
    "$CF_API/zones/$ZONE_ID/dns_records?type=A&name=$RECORD_NAME" \
    -H "Authorization: Bearer $CF_TOKEN" \
    -H "Content-Type: application/json" \
    | jq -r '.result[0].id')

  if [[ -z "$RECORD_ID" || "$RECORD_ID" == "null" ]]; then
    err "DNS record not found. Create the A record first in Cloudflare."
  fi

  log "Record ID found: $RECORD_ID"
}

### CREATE DDNS SCRIPT ###
create_ddns_script() {
  log "Creating DDNS updater script"

  cat > "$BIN_PATH" <<EOF
#!/usr/bin/env bash

CF_TOKEN="$CF_TOKEN"
ZONE_ID="$ZONE_ID"
RECORD_ID="$RECORD_ID"
RECORD_NAME="$RECORD_NAME"
API="$CF_API"

IP=\$(curl -4 -s https://ifconfig.me)
[ -z "\$IP" ] && exit 0

OLD_IP=\$(curl -s -X GET "\$API/zones/\$ZONE_ID/dns_records/\$RECORD_ID" \\
  -H "Authorization: Bearer \$CF_TOKEN" \\
  -H "Content-Type: application/json" | jq -r .result.content)

[ "\$IP" = "\$OLD_IP" ] && exit 0

curl -s -X PUT "\$API/zones/\$ZONE_ID/dns_records/\$RECORD_ID" \\
  -H "Authorization: Bearer \$CF_TOKEN" \\
  -H "Content-Type: application/json" \\
  --data '{
    "type":"A",
    "name":"'\$RECORD_NAME'",
    "content":"'\$IP'",
    "ttl":120,
    "proxied":false
  }' >/dev/null
EOF

  sed -i 's/\r$//' "$BIN_PATH"
  chmod +x "$BIN_PATH"
}

### CRON ###
setup_cron() {
  log "Installing cron job"

  crontab -l 2>/dev/null | grep -v cf-ddns.sh > /tmp/cron.tmp || true
  echo "$CRON_INTERVAL $BIN_PATH >/dev/null 2>&1" >> /tmp/cron.tmp
  crontab /tmp/cron.tmp
  rm -f /tmp/cron.tmp
}

### TEST ###
test_run() {
  log "Testing DDNS update"
  bash "$BIN_PATH"
  sleep 1
  dig "$RECORD_NAME" +short || warn "DNS check skipped"
}

### MAIN ###
main() {
  check_root
  install_deps
  collect_inputs
  fetch_record_id
  create_ddns_script
  setup_cron
  test_run

  echo
  log "DDNS fully configured!"
  echo "Subdomain : $RECORD_NAME"
  echo "Record ID : $RECORD_ID"
  echo "Cron      : $CRON_INTERVAL"
}

main
