#!/bin/bash
set -e

#################################
# IDENTIFICATION
#################################
APP_NAME="aaPanel Migration Tool"
VERSION="1.1.5"

#################################
# CONFIG
#################################
BACKUP_DIR="/root/aaPanel_backup"
LOG_FILE="/root/aaPanel_backup/aapanel-migrate.log"
META_FILE="migration.json"
PREFIX="aapanel"
DRY_RUN=false

#################################
# LOGGING
#################################
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[`date '+%Y-%m-%d %H:%M:%S'`] $1"; }
die() { log "ERROR: $1"; exit 1; }

confirm() {
  read -rp "$1 (YES to continue): " ans
  [ "$ans" = "YES" ] || die "Aborted by user"
}

run() {
  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

#################################
# PRE-CHECKS
#################################
[ "$EUID" -eq 0 ] || die "Run as root"
mkdir -p "$BACKUP_DIR"

command -v jq >/dev/null 2>&1 || {
  log "jq not found, installing..."
  apt update -y && apt install -y jq
}

#################################
# FIREWALL CHECK
#################################
check_firewall() {
  log "Firewall port check (22, 80, 443, 8888)"
  for p in 22 80 443 8888; do
    ss -tulpn | grep -q ":$p " && log "Port $p: OK" || log "Port $p: NOT LISTENING"
  done
}

#################################
# BACKUP
#################################
make_backup() {
  log "Starting backup"

  cat > "$BACKUP_DIR/$META_FILE" <<EOF
{
  "app": "$APP_NAME",
  "version": "$VERSION",
  "os": "$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')",
  "mysql": "$(mysql -V 2>/dev/null || echo NONE)",
  "backup_date": "$(date -Is)"
}
EOF

  FILE="$BACKUP_DIR/${PREFIX}_$(date +%Y%m%d-%H%M%S).tar.gz"

  tar -czvf "$FILE" \
    /www/wwwroot \
    /www/server/data \
    /www/server/panel \
    /www/server/php \
    /www/server/nginx \
    /www/server/panel/vhost/nginx \
    /etc/supervisor \
    /etc/crontab \
    /var/spool/cron \
    "$BACKUP_DIR/$META_FILE"

  sha256sum "$FILE" > "$FILE.sha256"

  echo
  echo "===================================="
  echo "✅ BACKUP COMPLETED SUCCESSFULLY"
  echo "Backup file   : $FILE"
  echo "Checksum file : $FILE.sha256"
  echo "===================================="
  echo
}

#################################
# LIST BACKUPS
#################################
list_backups() {
  echo
  echo "=== Available Backups ==="
  if ! ls "$BACKUP_DIR"/${PREFIX}_*.tar.gz >/dev/null 2>&1; then
    echo "⚠ No backups found in $BACKUP_DIR"
    return
  fi

  ls -lh --time-style=long-iso "$BACKUP_DIR"/${PREFIX}_*.tar.gz
  echo
}

#################################
# VERIFY BACKUP
#################################
verify_backup() {
  echo
  FILE=$(ls -t "$BACKUP_DIR"/${PREFIX}_*.tar.gz 2>/dev/null | head -n1)

  if [ -z "$FILE" ]; then
    echo "⚠ No backups found."
    echo "Please run 'Make backup' first."
    return
  fi

  echo "Verifying backup:"
  echo "$FILE"

  if [ ! -f "$FILE.sha256" ]; then
    echo
    echo "⚠ Checksum file missing."
    read -rp "Generate checksum now? (YES to generate): " ans
    [ "$ans" = "YES" ] || die "Verification aborted"
    sha256sum "$FILE" > "$FILE.sha256"
    echo "Checksum generated."
  fi

  sha256sum -c "$FILE.sha256" || die "Checksum verification FAILED"
  tar -tzf "$FILE" >/dev/null || die "Archive corrupted"

  echo
  echo "===================================="
  echo "✅ BACKUP VERIFICATION PASSED"
  echo "===================================="
  echo
}

#################################
# DOWNLOAD BACKUP (SIMPLE SCP)
#################################
download_backup() {
  read -rp "Old server SSH user: " U
  read -rp "Old server host/IP: " H
  read -rp "Backup directory on old server [default: /root/aaPanel]: " D
  D=${D:-/root/aaPanel}

  REMOTE_FILE=$(ssh "$U@$H" "ls -t $D/${PREFIX}_*.tar.gz | head -n1") \
    || die "Failed to locate backup"

  scp "$U@$H:$REMOTE_FILE" "$BACKUP_DIR/"
  scp "$U@$H:$REMOTE_FILE.sha256" "$BACKUP_DIR/" || true

  echo "Downloaded backup to $BACKUP_DIR"
}

#################################
# MAIN
#################################
main() {
  echo "===================================="
  echo "$APP_NAME v$VERSION"
  echo "===================================="
  echo "1) Make backup"
  echo "2) Restore backup (manual)"
  echo "3) Dry-run / audit"
  echo "4) Download backup from old server"
  echo "5) Verify backup integrity"
  echo "6) List available backups"
  read -rp "Choose [1-6]: " opt

  case "$opt" in
    1) make_backup ;;
    3) DRY_RUN=true; verify_backup ;;
    4) download_backup ;;
    5) verify_backup ;;
    6) list_backups ;;
    *) echo "Option not implemented in this build" ;;
  esac
}

main "$@"

