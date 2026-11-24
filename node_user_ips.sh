#!/usr/bin/env bash
# ipcheck.sh - run ON the node. Panel IPs via SSH (refresh 60s) -> local per-IP traffic (every 30s)
# Layout: CONFIG | LIB | PANEL SSH | PANEL REMOTE FUNC | NODE FUNCS | MODULES | MAIN

# v2

# how to run
# FILE='node_user_ips.sh'; sed -i 's/\r$//' $FILE && chmod +x $FILE && ./$FILE

########################## CONFIG ##########################
# leave empty to be prompted
PANEL_HOST=""; PANEL_USER="root"; PANEL_PORT="22"; PANEL_PASS=""
PANEL_ENV_PATH=""

ENVF="$PANEL_ENV_PATH"
REDIS_KEY_PREFIX="xboard_database_user_devices"
REDIS_DB=0
INT=60                 # node check interval (s)
PANEL_EVERY=2          # refresh panel every N ticks (2 x 30s = 60s)
PROC_RE='sing-box|xray'  # process names used for port auto-detect
SKIP_PORTS='22'        # excluded in fallback port detect
LOG_DIR=/tmp

########################## LIB ##########################
ask(){ # ask VAR "prompt" [secret]
  local v=$1 p=$2 s=$3
  [ -n "${!v}" ] && return
  if [ -n "$s" ]; then read -rsp "$p: " "$v"; echo; else read -rp "$p: " "$v"; fi
}
log(){ echo "$*"; }

########################## PANEL SSH ##########################
SSH_OPTS=(-o ControlPath="/tmp/ipcheck-%C" -o ControlMaster=auto -o ControlPersist=10m
          -o StrictHostKeyChecking=accept-new -o PubkeyAuthentication=no)
pssh(){ ssh -p "$PANEL_PORT" "${SSH_OPTS[@]}" "$PANEL_USER@$PANEL_HOST" "$@"; }

ssh_askpass_init(){  # SSH_ASKPASS helper (OpenSSH >= 8.4)
  AP=$(mktemp /tmp/ipc_ap.XXXXXX)
  printf '#!/bin/sh\nprintf "%%s\\n" "$IPC_PW"\n' > "$AP"; chmod 700 "$AP"
}
panel_login(){  # opens persistent master connection
  IPC_PW="$PANEL_PASS" SSH_ASKPASS="$AP" SSH_ASKPASS_REQUIRE=force pssh true </dev/null \
    || { log "panel login failed"; exit 1; }
  pssh test -f "$ENVF" || { log "panel env not found: $ENVF"; exit 1; }
}
rexec(){  # rexec "<funcs to ship>" <entry fn> [args...]  -> runs on panel
  local funcs=$1 fn=$2; shift 2
  { declare -f $funcs; echo "$fn \"\$@\""; } | pssh bash -s -- "$@"
}
cleanup(){
  rm -rf "$STATE"
  ssh -p "$PANEL_PORT" "${SSH_OPTS[@]}" -O exit "$PANEL_USER@$PANEL_HOST" 2>/dev/null
  rm -f "$AP"
}

########################## PANEL REMOTE FUNC ##########################
panel_devices(){  # envf key_id prefix db -> "ip age_s node name"
  local envf=$1 id=$2 prefix=$3 db=$4 pass now
  local dbh dbp dbn dbu dbpwd mysql
  getenv(){ grep -E "^$1=" "$envf" | head -1 | cut -d= -f2- | tr -d '\r' | sed -E "s/^(['\"])(.*)\1\$/\2/"; }
  pass=$(getenv REDIS_PASSWORD)
  dbh=$(getenv DB_HOST); dbp=$(getenv DB_PORT); dbn=$(getenv DB_DATABASE); dbu=$(getenv DB_USERNAME)
  MYSQL_PWD=$(getenv DB_PASSWORD) export MYSQL_PWD
  mysql=(mysql -N -h "${dbh:-127.0.0.1}" -P "${dbp:-3306}" -u "$dbu" -D "$dbn")
  now=$(date +%s)
  # node id -> name map
  declare -A NN
  while IFS=$'\t' read -r nid nname; do [ -n "$nid" ] && NN["$nid"]="$nname"; done \
    < <("${mysql[@]}" -e "SELECT id, name FROM v2_server")
  # HGETALL: field=node:ip value=ts
  redis-cli -a "$pass" --no-auth-warning -n "$db" HGETALL "$prefix:$id" \
    | paste - - | while read -r field ts; do
        node="${field%%:*}"; ip="${field#*:}"
        printf '%s %s %s %s\n' "$ip" "$(( now - ts ))" "$node" "${NN[$node]:-unknown}"
      done
}

########################## NODE FUNCS (local) ##########################
node_detect_ports(){  # proc_re skip_re
  local p
  p=$(ss -tlnpH | grep -Ei "$1" | awk '{n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')
  [ -z "$p" ] && p=$(ss -tlnH | awk '{n=split($4,a,":"); print a[n]}' | sort -un \
                     | grep -vxE "$2" | tr '\n' ' ')
  echo "$p"
}
node_snap(){  # ports -> "ip clientport t bytes"
  ss -tinH state established | awk -v P="$1" '
    BEGIN{n=split(P,a," "); for(i=1;i<=n;i++) w[a[i]]=1}
    !/^[ \t]/ {lp=$(NF-1); sub(/.*:/,"",lp); peer=$NF; port=peer; sub(/.*:/,"",port)
               ip=peer; sub(/:[0-9]+$/,"",ip); gsub(/[\[\]]/,"",ip); sub(/^::ffff:/,"",ip); ok=(lp in w); next}
    ok{b=0
       if (match($0,/bytes_received:[0-9]+/)) b+=substr($0,RSTART+15,RLENGTH-15)
       if (match($0,/bytes_sent:[0-9]+/))     b+=substr($0,RSTART+11,RLENGTH-11)
       print ip, port, "t", b, lp}'
}
node_delta(){  # prev cur -> "ip KB conns"
  awk 'FILENAME==ARGV[1]{pr[$1" "$2" "$3]=$4;next}
    {k=$1" "$2" "$3; d=$4-((k in pr)?pr[k]:0); if(d<0)d=0; kb[$1]+=d/1024; c[$1]++
     if(index(","pt[$1]",", ","$5",")==0) pt[$1]=pt[$1] ((pt[$1]=="")?"":",") $5}
    END{for(i in kb) print i, kb[i], c[i], pt[i]}' "$1" "$2"
}
node_report(){  # list interval dprev dcur
  awk -v L="$1" -v I="$2" '
   BEGIN{n=split(L,a," "); for(i=1;i<=n;i++) want[a[i]]=1}
   FILENAME==ARGV[1]{p[$1]=$2; all[$1]=1; next}
   {c[$1]=$2; f[$1]=$3; q[$1]=$4; all[$1]=1}
   END{cmd="sort -nr"
    for(i in all){ if(!(i in want)) continue
      s30=(i in c)?c[i]:0; s60=s30+((i in p)?p[i]:0)
      if(s60>0) printf "%10.1f KB/60s %9.1f KB/%ds conns=%-3d ports=%-12s %s\n",s60,s30,I,f[i]+0,q[i],i | cmd
      tot+=s30; if(s60>=100)n100++; if(s60>=500)n500++; if(s60>0)nany++}
    close(cmd)
    printf "-- IPs with traffic=%d  >=100KB/60s=%d  >=500KB/60s=%d  total=%.1f KB/%ds\n",nany,n100,n500,tot,I}
  ' "$3" "$4"
}
node_tick(){  # one iteration, stateful in $STATE
  local ports=$PORT d=$STATE
  mkdir -p "$d"
  [ -z "$ports" ] && { ports=$(node_detect_ports "$PROC_RE" "$SKIP_PORTS"); echo "ports: $ports"; }
  node_snap "$ports" > "$d/cur"
  if [ ! -f "$d/prev" ]; then mv "$d/cur" "$d/prev"; : > "$d/dprev"; echo "baseline set"; return; fi
  node_delta "$d/prev" "$d/cur" > "$d/dcur"
  node_report "$LIST" "$INT" "$d/dprev" "$d/dcur"
  mv "$d/cur" "$d/prev"; mv "$d/dcur" "$d/dprev"
}

########################## MODULES ##########################
panel_refresh(){
  PANEL_OUT=$(rexec panel_devices panel_devices "$ENVF" "$KEY_ID" "$REDIS_KEY_PREFIX" "$REDIS_DB")
  LIST=$(echo "$PANEL_OUT" | awk 'NF{print $1}' | sort -u | tr '\n' ' ')
  log "### $(date '+%F %T') panel: user=$KEY_ID ips=$(echo $LIST | wc -w)"
  # ip age node name  ->  "   ip   [node] name   age_s ago"
  echo "$PANEL_OUT" | sort -k2 -n | awk 'NF{printf "   %-40s [%s] %-16s %ss ago\n",$1,$3,$4,$2}'
}
node_check(){ log "== $(date +%T) node"; node_tick; }

########################## MAIN ##########################
prompt_inputs(){
  ask PANEL_HOST "Panel IP"; ask PANEL_PASS "Panel password" s
  PANEL_PORT=${PANEL_PORT:-22}
  ask PANEL_ENV_PATH "Panel .env path (e.g. /var/www/website/.env)"
  [ -z "$PANEL_ENV_PATH" ] && { log "PANEL_ENV_PATH is required"; exit 1; }
  ENVF="$PANEL_ENV_PATH"
  read -rp "User ID: " KEY_ID
  read -rp "Port (blank = auto-detect active ports): " PORT
}
run_loop(){
  local tick=0
  while true; do
    (( tick % PANEL_EVERY == 0 )) && panel_refresh
    node_check
    tick=$((tick+1)); sleep "$INT"
  done
}
main(){
  STATE="/tmp/ipcheck_$$"; trap cleanup EXIT
  prompt_inputs
  ssh_askpass_init; panel_login
  run_loop | tee "$LOG_DIR/ipcheck_${KEY_ID}.log"
}
main
