#!/bin/bash
set -e

#################################
# IDENTIFICATION
#################################
APP_NAME="aaPanel Migration Tool"
VERSION="1.1.4"

#################################
# CONFIG
#################################
BACKUP_DIR="/root/aapanel_backup"
LOG_FILE="/root/aapanel_backup/aapanel-migrate.log"
META_FILE="migration.json"
PREFIX="aapanel"
DRY_RUN=false

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

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

command -v jq >/dev/null 2>&1 || {
  log "jq not found, installing..."
  apt update -y && apt install -y jq
}

#################################
# DETECTION
#################################
detect_os() { . /etc/os-release; echo "$NAME $VERSION_ID"; }
detect_mysql() { mysql -V 2>/dev/null | awk '{print $5}' | tr -d ',' || echo "NONE"; }
detect_php_versions() { ls /www/server/php 2>/dev/null | grep -E '^php[0-9]+' || true; }
detect_php_exts() { /www/server/php/$1/bin/php -m 2>/dev/null | tr 'A-Z' 'a-z'; }

#################################
# FIREWALL CHECK
#################################
check_firewall() {
  log "Firewall port check (22, 80, 443, 8888)"
  for p in 22 80 443 8888; do
    if ss -tulpn | grep -q ":$p "; then
      log "Port $p: OK"
    else
      log "Port $p: NOT LISTENING (may be blocked)"
    fi
  done
}

#################################
# BACKUP
#################################
make_backup() {
  log "Starting backup process"

  PHP_VERSIONS=($(detect_php_versions))
  PHP_JSON=$(printf '"%s",' "${PHP_VERSIONS[@]}")
  PHP_JSON="[${PHP_JSON%,}]"

  cat > "$BACKUP_DIR/$META_FILE" <<EOF
{
  "app_name": "$APP_NAME",
  "version": "$VERSION",
  "os": "$(detect_os)",
  "database": {
    "engine": "mysql",
    "version": "$(detect_mysql)"
  },
  "php": {
    "versions": $PHP_JSON
  },
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

  # ✅ AUTO-CHECKSUM (NEW IN v1.1.4)
  sha256sum "$FILE" > "$FILE.sha256"

  echo
  echo "===================================="
  echo "✅ BACKUP COMPLETED SUCCESSFULLY"
  echo "------------------------------------"
  echo "Backup file   : $FILE"
  echo "Checksum file : $FILE.sha256"
  echo "Metadata file : $BACKUP_DIR/$META_FILE"
  echo "===================================="
  echo

  log "Backup + checksum created successfully"
}

#################################
# VERIFY BACKUP
#################################
verify_backup() {
  echo
  echo "=== Backup Verification ==="

  FILE=$(ls -t "$BACKUP_DIR"/${PREFIX}_*.tar.gz 2>/dev/null | head -n1)
  [ -f "$FILE" ] || die "No backup archive found"
  [ -f "$FILE.sha256" ] || die "Checksum file missing"

  sha256sum -c "$FILE.sha256" || die "Checksum verification FAILED"

  tar -tzf "$FILE" >/dev/null || die "Archive corrupted"

  tar -tzf "$FILE" | grep -q "www/wwwroot" || die "Missing wwwroot"
  tar -tzf "$FILE" | grep -q "www/server/panel" || die "Missing aaPanel config"
  tar -tzf "$FILE" | grep -q "www/server/data" || die "Missing database data"

  echo
  echo "===================================="
  echo "✅ BACKUP VERIFICATION PASSED"
  echo "Backup is SAFE to restore"
  echo "===================================="
  echo

  log "Backup verification passed"
}

#################################
# RESTORE
#################################
restore_backup() {
  check_firewall

  FILE=$(ls -t "$BACKUP_DIR"/${PREFIX}_*.tar.gz | head -n1)
  [ -f "$FILE" ] || die "No backup found"
  [ -f "$FILE.sha256" ] || die "Checksum file missing"

  sha256sum -c "$FILE.sha256" || die "Checksum verification FAILED"

  tar -xzf "$FILE" -C "$BACKUP_DIR" "$META_FILE"

  DB_VERSION=$(jq -r '.database.version' "$BACKUP_DIR/$META_FILE")
  PHP_VERSIONS=$(jq -r '.php.versions[]' "$BACKUP_DIR/$META_FILE")

  echo
  echo "⚠ Snapshot recommended before restore"
  read -rp "Press ENTER to continue..."

  INSTALLED_DB=$(detect_mysql)

  if [ "$INSTALLED_DB" = "NONE" ]; then
    confirm "Install MySQL $DB_VERSION?"
    run "bt install mysql57"
  elif [ "$INSTALLED_DB" != "$DB_VERSION" ]; then
    echo "Installed DB: $INSTALLED_DB"
    echo "Required DB : $DB_VERSION"
    echo "1) Uninstall and install required"
    echo "2) Abort"
    read -rp "Choose [1/2]: " c
    [ "$c" = "1" ] || die "Aborted"
    run "bt uninstall mysql"
    run "bt install mysql57"
  fi

  for php in $PHP_VERSIONS; do
    [ -d "/www/server/php/$php" ] || run "bt install $php"

    exts=$(detect_php_exts "$php")
    echo
    echo "PHP $php extensions detected:"
    echo "$exts"

    confirm "Install detected extensions?"
    for e in $exts; do
      run "bt install ${php}-${e}"
    done
  done

  run "tar -xzf $FILE -C /"
  run "systemctl restart nginx mysql php*-fpm aaPanel || true"

  bt default || true

  echo
  echo "=== Health Check ==="
  systemctl is-active nginx && echo "nginx OK"
  systemctl is-active mysql && echo "mysql OK"
  systemctl is-active aaPanel && echo "aaPanel OK"
  [ -d /www/wwwroot ] && echo "Website files OK"

  log "Restore completed"
}

#################################
# DOWNLOAD
#################################

ensure_rsync() {
  command -v rsync >/dev/null 2>&1 || {
    echo "Installing rsync locally..."
    apt update -y && apt install -y rsync
  }
}


download_backup() {
  echo
  read -rp "Old server SSH user (example: root): " OLD_USER
  read -rp "Old server host/IP (example: 1.2.3.4): " OLD_HOST
  read -rp "Backup directory on old server (example: /root): " OLD_DIR

  SSH_OPTS="-o ControlMaster=auto -o ControlPersist=10m -o ControlPath=/tmp/ssh-%r@%h:%p"
  USE_RSYNC=true

  echo
  echo "Searching for latest backup on remote server..."
  REMOTE_FILE=$(ssh $SSH_OPTS "${OLD_USER}@${OLD_HOST}" \
    "ls -t ${OLD_DIR}/aapanel_*.tar.gz 2>/dev/null | head -n1") \
    || die "Unable to connect to remote server"

  [ -n "$REMOTE_FILE" ] || die "No backup files found in $OLD_DIR"

  BASENAME=$(basename "$REMOTE_FILE")

  echo
  echo "Found backup:"
  echo "$REMOTE_FILE"

  echo
  echo "Checking rsync on local server..."
  if ! command -v rsync >/dev/null 2>&1; then
    echo "⚠ rsync not installed locally."
    read -rp "Install rsync locally? (YES to install): " ans
    [ "$ans" = "YES" ] || USE_RSYNC=false
    [ "$ans" = "YES" ] && apt update -y && apt install -y rsync
  fi

  echo
  echo "Checking rsync on remote server..."
  if [ "$USE_RSYNC" = true ] && ! ssh $SSH_OPTS "${OLD_USER}@${OLD_HOST}" "command -v rsync >/dev/null 2>&1"; then
    echo "⚠ rsync not installed on remote server."
    echo "1) Install rsync on remote server (recommended)"
    echo "2) Continue using SCP (no progress bar)"
    echo "3) Abort"
    read -rp "Choose [1-3]: " choice

    case "$choice" in
      1)
        ssh $SSH_OPTS "${OLD_USER}@${OLD_HOST}" "apt update -y && apt install -y rsync" \
          || die "Failed to install rsync on remote server"
        ;;
      2)
        USE_RSYNC=false
        ;;
      *)
        die "Aborted by user"
        ;;
    esac
  fi

  echo
  if [ "$USE_RSYNC" = true ]; then
    echo "Downloading backup using rsync (with progress)..."
    rsync -avz --progress -e "ssh $SSH_OPTS" \
      "${OLD_USER}@${OLD_HOST}:${REMOTE_FILE}" "$BACKUP_DIR/" \
      || die "Backup download failed"

    echo
    echo "Downloading checksum..."
    rsync -avz --progress -e "ssh $SSH_OPTS" \
      "${OLD_USER}@${OLD_HOST}:${REMOTE_FILE}.sha256" "$BACKUP_DIR/" \
      || die "Checksum download failed"
  else
    echo "Downloading backup using SCP..."
    scp -v "${OLD_USER}@${OLD_HOST}:${REMOTE_FILE}" "$BACKUP_DIR/" \
      || die "Backup download failed"

    echo
    echo "Downloading checksum..."
    scp -v "${OLD_USER}@${OLD_HOST}:${REMOTE_FILE}.sha256" "$BACKUP_DIR/" \
      || die "Checksum download failed"
  fi

  echo
  echo "Verifying checksum locally..."
  (cd "$BACKUP_DIR" && sha256sum -c "${BASENAME}.sha256") \
    || die "Checksum verification failed"

  echo
  echo "===================================="
  echo "✅ DOWNLOAD COMPLETED SUCCESSFULLY"
  echo "------------------------------------"
  echo "Backup file   : $BACKUP_DIR/$BASENAME"
  echo "Checksum file : $BACKUP_DIR/$BASENAME.sha256"
  echo "===================================="
  echo

  log "Backup downloaded and verified from $OLD_HOST"
}


#################################
# MAIN
#################################
main() {
  echo "===================================="
  echo "$APP_NAME v$VERSION"
  echo "===================================="
  echo "1) Make backup"
  echo "2) Restore backup"
  echo "3) Dry-run / audit"
  echo "4) Download backup from old server"
  echo "5) Verify backup integrity"
  read -rp "Choose [1-5]: " opt

  case "$opt" in
    1) make_backup ;;
    2) restore_backup ;;
    3) DRY_RUN=true; restore_backup ;;
    4) download_backup ;;
    5) verify_backup ;;
    *) die "Invalid option" ;;
  esac
}

main "$@"
