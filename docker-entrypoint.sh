#!/usr/bin/env sh

set -eu

log() {
  printf '%s\n' "$*"
}

normalize_web_path() {
  path="$1"
  path="${path#/}"
  path="${path%/}"
  if [ -z "$path" ]; then
    path="panel"
  fi
  printf '%s' "$path"
}

generate_password() {
  head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16
}

find_xray_bin() {
  for candidate in \
    /app/bin/xray-linux-amd64 \
    /app/bin/xray-linux-arm64 \
    /app/bin/xray-linux-arm \
    /usr/local/x-ui/bin/xray-linux-amd64 \
    /usr/local/x-ui/bin/xray-linux-arm64 \
    /usr/local/x-ui/bin/xray-linux-arm \
    /usr/bin/xray
  do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

gen_hex() {
  bytes="$1"
  chars="$2"
  head -c "$bytes" /dev/urandom | xxd -p | tr -d '\n' | cut -c1-"$chars"
}

XUI_ADMIN_USER="${XUI_ADMIN_USER:-admin}"
XUI_ADMIN_PASS="${XUI_ADMIN_PASS:-}"
XUI_PORT="${XUI_PORT:-2053}"
XUI_WEB_BASE_PATH_RAW="${XUI_WEB_BASE_PATH:-/panel/}"
XRAY_PORT="${XRAY_PORT:-443}"
XRAY_REALITY_DOMAIN="${XRAY_REALITY_DOMAIN:-www.samsung.com}"
XRAY_REMARK="${XRAY_REMARK:-vless-reality}"
XRAY_CLIENT_EMAIL="${XRAY_CLIENT_EMAIL:-client-1}"
XUI_FORCE_RECREATE_INBOUND="${XUI_FORCE_RECREATE_INBOUND:-false}"

if [ -z "$XUI_ADMIN_PASS" ]; then
  XUI_ADMIN_PASS="$(generate_password)"
  log "[xray-vpn] XUI_ADMIN_PASS не задан, сгенерирован автоматически: $XUI_ADMIN_PASS"
fi

WEB_BASE_PATH="$(normalize_web_path "$XUI_WEB_BASE_PATH_RAW")"
DB="/etc/x-ui/x-ui.db"

if [ ! -d /etc/x-ui ]; then
  mkdir -p /etc/x-ui
fi

log "[xray-vpn] Запуск bootstrap-процесса x-ui для инициализации БД..."
/app/x-ui &
bootstrap_pid=$!

for _ in $(seq 1 30); do
  if [ -f "$DB" ]; then
    break
  fi
  sleep 1
done

if [ ! -f "$DB" ]; then
  log "[xray-vpn] Ошибка: файл БД $DB не появился"
  kill "$bootstrap_pid" 2>/dev/null || true
  wait "$bootstrap_pid" 2>/dev/null || true
  exit 1
fi

log "[xray-vpn] Применение настроек панели..."
x-ui setting -username "$XUI_ADMIN_USER" -password "$XUI_ADMIN_PASS" -port "$XUI_PORT" -webBasePath "$WEB_BASE_PATH" >/dev/null 2>&1 || true

if ! XRAY_BIN="$(find_xray_bin)"; then
  log "[xray-vpn] Ошибка: не удалось найти бинарник xray"
  kill "$bootstrap_pid" 2>/dev/null || true
  wait "$bootstrap_pid" 2>/dev/null || true
  exit 1
fi

if [ "$XUI_FORCE_RECREATE_INBOUND" = "true" ]; then
  sqlite3 "$DB" "DELETE FROM inbounds WHERE remark='$XRAY_REMARK'"
fi

existing_count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM inbounds WHERE remark='$XRAY_REMARK';")"

if [ "$existing_count" = "0" ]; then
  log "[xray-vpn] Создание inbound '$XRAY_REMARK' (VLESS Reality)..."

  KEYS="$($XRAY_BIN x25519)"
  PRIVATE_KEY="$(printf '%s\n' "$KEYS" | awk '/PrivateKey:/ {print $2}')"
  PUBLIC_KEY="$(printf '%s\n' "$KEYS" | awk '/PublicKey:/ {print $2}')"

  CLIENT_ID="$(cat /proc/sys/kernel/random/uuid)"
  SUB_ID="$(gen_hex 8 8)"

  S1="$(gen_hex 3 6)"
  S2="$(gen_hex 4 8)"
  S3="$(gen_hex 6 12)"
  S4="$(gen_hex 2 4)"
  S5="$(gen_hex 5 10)"
  S6="$(gen_hex 8 16)"
  S7="$(gen_hex 7 14)"
  S8="$(gen_hex 1 2)"

  SHORT_IDS="$(jq -nc --arg s1 "$S1" --arg s2 "$S2" --arg s3 "$S3" --arg s4 "$S4" --arg s5 "$S5" --arg s6 "$S6" --arg s7 "$S7" --arg s8 "$S8" '[$s1,$s2,$s3,$s4,$s5,$s6,$s7,$s8]')"

  SETTINGS="$(jq -nc --arg id "$CLIENT_ID" --arg email "$XRAY_CLIENT_EMAIL" --arg sub "$SUB_ID" '{clients:[{id:$id,flow:"xtls-rprx-vision",email:$email,limitIp:0,totalGB:0,expiryTime:0,enable:true,tgId:"",subId:$sub,comment:"",reset:0}],decryption:"none",encryption:"none"}')"

  STREAM_SETTINGS="$(jq -nc --arg domain "$XRAY_REALITY_DOMAIN" --arg target "${XRAY_REALITY_DOMAIN}:443" --arg pk "$PRIVATE_KEY" --arg pubk "$PUBLIC_KEY" --argjson sids "$SHORT_IDS" '{network:"tcp",security:"reality",externalProxy:[],realitySettings:{show:false,xver:0,target:$target,serverNames:[$domain],privateKey:$pk,minClientVer:"",maxClientVer:"",maxTimediff:0,shortIds:$sids,mldsa65Seed:"",settings:{publicKey:$pubk,fingerprint:"chrome",serverName:"",spiderX:"/",mldsa65Verify:""}},tcpSettings:{acceptProxyProtocol:false,header:{type:"none"}}}')"

  SNIFFING='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'

  COLUMNS="$(sqlite3 "$DB" "PRAGMA table_info(inbounds)" | cut -d'|' -f2 | tr '\n' ',')"

  SQL_COLS="user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing"
  SQL_VALS="1, 0, 0, 0, '$XRAY_REMARK', 1, 0, '', $XRAY_PORT, 'vless', '$(printf '%s' "$SETTINGS" | sed "s/'/''/g")', '$(printf '%s' "$STREAM_SETTINGS" | sed "s/'/''/g")', 'inbound-$XRAY_PORT', '$(printf '%s' "$SNIFFING" | sed "s/'/''/g")'"

  echo "$COLUMNS" | grep -q "all_time" && SQL_COLS="$SQL_COLS, all_time" && SQL_VALS="$SQL_VALS, 0"
  echo "$COLUMNS" | grep -q "traffic_reset" && SQL_COLS="$SQL_COLS, traffic_reset" && SQL_VALS="$SQL_VALS, 'never'"
  echo "$COLUMNS" | grep -q "last_traffic_reset_time" && SQL_COLS="$SQL_COLS, last_traffic_reset_time" && SQL_VALS="$SQL_VALS, 0"
  echo "$COLUMNS" | grep -q "node_id" && SQL_COLS="$SQL_COLS, node_id" && SQL_VALS="$SQL_VALS, 0"
  echo "$COLUMNS" | grep -q "allocate" && SQL_COLS="$SQL_COLS, allocate" && SQL_VALS="$SQL_VALS, '{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}'"

  sqlite3 "$DB" "INSERT INTO inbounds ($SQL_COLS) VALUES ($SQL_VALS)"

  FIRST_SID="$(printf '%s' "$SHORT_IDS" | jq -r '.[0]')"
  cat > /etc/x-ui/vpn_credentials.txt << EOF
=== Xray VPN Credentials ===
Admin user: $XUI_ADMIN_USER
Admin pass: $XUI_ADMIN_PASS
WebBasePath: /$WEB_BASE_PATH/
Panel port (container): $XUI_PORT
Reality domain: $XRAY_REALITY_DOMAIN
Reality port: $XRAY_PORT
Public key: $PUBLIC_KEY
Client id: $CLIENT_ID
Short id: $FIRST_SID
EOF
  chmod 600 /etc/x-ui/vpn_credentials.txt

  log "[xray-vpn] inbound '$XRAY_REMARK' создан."
else
  log "[xray-vpn] inbound '$XRAY_REMARK' уже существует, пропускаю создание."
fi

kill "$bootstrap_pid" 2>/dev/null || true
wait "$bootstrap_pid" 2>/dev/null || true

log "[xray-vpn] Контейнер готов."
log "[xray-vpn] Панель: user=$XUI_ADMIN_USER webPath=/$WEB_BASE_PATH/"

exec "$@"
