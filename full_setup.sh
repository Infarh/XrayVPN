#!/bin/bash

# Автор автоматических скриптов настройки: Александр Платоненков (https://github.com/Platonenkov)
# https://gist.github.com/Platonenkov/b3c556e15edecc1c3a624d9a048ed903

# ============================================================
# Полная автоматическая настройка Xray VPN (VLESS Reality)
# Запускать на чистом VPS Ubuntu 24.04+ под root
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "============================================"
echo "  Xray VPN (VLESS Reality) — Full Setup"
echo "============================================"
echo -e "${NC}"

# --- Проверка root ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Запускай под root!${NC}"
  exit 1
fi

# --- Ввод параметров ---
echo -e "${YELLOW}=== Параметры настройки ===${NC}"
echo ""

read -p "Порт панели 3X-UI (по умолчанию 1406): " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-1406}

read -p "Логин панели (по умолчанию admin): " PANEL_USER
PANEL_USER=${PANEL_USER:-admin}

read -sp "Пароль панели (по умолчанию auto): " PANEL_PASS
echo ""
if [ -z "$PANEL_PASS" ]; then
  PANEL_PASS=$(head -c 12 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)
  echo -e "Сгенерирован пароль: ${GREEN}$PANEL_PASS${NC}"
fi

read -p "Web Base Path (по умолчанию /panel/): " PANEL_PATH
PANEL_PATH=${PANEL_PATH:-/panel/}
# Добавить слэши если забыли
[[ "$PANEL_PATH" != /* ]] && PANEL_PATH="/$PANEL_PATH"
[[ "$PANEL_PATH" != */ ]] && PANEL_PATH="$PANEL_PATH/"

read -p "Домен для Reality (по умолчанию auto — сканирование): " REALITY_DOMAIN
REALITY_DOMAIN=${REALITY_DOMAIN:-auto}

XRAY_PORT=443

echo ""
echo -e "${YELLOW}=== Начинаем установку ===${NC}"
echo ""

# ============================================================
# 1. Обновление системы
# ============================================================
echo -e "${CYAN}[1/7] Обновление системы...${NC}"
apt update -y && apt upgrade -y
echo -e "${GREEN}[1/7] Готово${NC}"

# ============================================================
# 2. Установка зависимостей
# ============================================================
echo -e "${CYAN}[2/7] Установка зависимостей...${NC}"
apt install -y curl openssl sqlite3 jq golang xxd
echo -e "${GREEN}[2/7] Готово${NC}"

# ============================================================
# 3. Установка 3X-UI
# ============================================================
echo -e "${CYAN}[3/6] Установка 3X-UI...${NC}"

# Скачиваем и запускаем установщик с автоответами:
# y (customize port) → порт → (username задаётся позже через БД)
# 4 (skip SSL) → N (не привязывать к 127.0.0.1)
printf "y\n${PANEL_PORT}\n4\nN\n" | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# Ждём запуск
sleep 3

# Настраиваем через БД
DB="/etc/x-ui/x-ui.db"

# Ждём пока БД появится
for i in $(seq 1 10); do
  [ -f "$DB" ] && break
  sleep 2
done

if [ ! -f "$DB" ]; then
  echo -e "${RED}Ошибка: БД 3X-UI не найдена${NC}"
  exit 1
fi

# Смена логина/пароля (таблица users, пароль в bcrypt)
apt install -y python3 >/dev/null 2>&1
PASS_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'$PANEL_PASS', bcrypt.gensalt()).decode())" 2>/dev/null)

# Если bcrypt недоступен — ставим через pip
if [ -z "$PASS_HASH" ]; then
  pip3 install bcrypt -q 2>/dev/null || apt install -y python3-bcrypt >/dev/null 2>&1
  PASS_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'$PANEL_PASS', bcrypt.gensalt()).decode())")
fi

sqlite3 "$DB" "UPDATE users SET username='$PANEL_USER', password='$PASS_HASH' WHERE id=1"

# Web Base Path
sqlite3 "$DB" "DELETE FROM settings WHERE key='webBasePath'"
sqlite3 "$DB" "INSERT INTO settings (key, value) VALUES ('webBasePath', '$PANEL_PATH')"

x-ui restart >/dev/null 2>&1
sleep 3

echo -e "${GREEN}[3/6] 3X-UI установлена${NC}"

# ============================================================
# 4. Поиск домена для Reality
# ============================================================
XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"

if [ "$REALITY_DOMAIN" = "auto" ]; then
  echo -e "${CYAN}[4/6] Сканирование доменов для Reality...${NC}"

  go install github.com/xtls/RealiTLScanner@latest 2>/dev/null

  SERVER_IP=$(curl -s4 ifconfig.me)
  SUBNET=$(echo "$SERVER_IP" | sed 's/\.[0-9]*$/.0/')

  SCAN_RESULT=$(~/go/bin/RealiTLScanner -addr "$SUBNET/24" -thread 10 -timeout 5 2>&1 | grep "feasible=true" | grep -v 'cert-domain=\*' | head -20)

  if [ -z "$SCAN_RESULT" ]; then
    echo -e "${YELLOW}Сканирование не нашло доменов, используем www.samsung.com${NC}"
    REALITY_DOMAIN="www.samsung.com"
  else
    echo -e "${GREEN}Найденные домены:${NC}"
    echo "$SCAN_RESULT" | while read -r line; do
      DOMAIN=$(echo "$line" | grep -oP 'cert-domain=\K[^ ]+')
      echo "  $DOMAIN"
    done

    # Выбираем первый подходящий крупный домен или просто первый
    for PREFERRED in "ozon.ru" "forbes.ru" "rutube.ru" "vk.com" "yahoo.com" "samsung.com"; do
      FOUND=$(echo "$SCAN_RESULT" | grep "$PREFERRED" | head -1)
      if [ -n "$FOUND" ]; then
        REALITY_DOMAIN=$(echo "$FOUND" | grep -oP 'cert-domain=\K[^ ]+')
        break
      fi
    done

    # Если ни один предпочтительный не найден — берём первый
    if [ "$REALITY_DOMAIN" = "auto" ]; then
      REALITY_DOMAIN=$(echo "$SCAN_RESULT" | head -1 | grep -oP 'cert-domain=\K[^ ]+')
    fi
  fi
fi

echo -e "${GREEN}[4/6] Домен Reality: $REALITY_DOMAIN${NC}"

# ============================================================
# 5. Создание VLESS Reality подключения
# ============================================================
echo -e "${CYAN}[5/6] Создание VLESS Reality подключения...${NC}"

# Генерация ключей
KEYS=$("$XRAY_BIN" x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep "PublicKey" | awk '{print $NF}')

# UUID клиента
CLIENT_ID=$(cat /proc/sys/kernel/random/uuid)

# Short IDs
gen_hex() { head -c 32 /dev/urandom | xxd -p | head -c "$1"; }
SHORT_IDS=$(jq -n \
  --arg s1 "$(gen_hex 6)" \
  --arg s2 "$(gen_hex 8)" \
  --arg s3 "$(gen_hex 12)" \
  --arg s4 "$(gen_hex 4)" \
  --arg s5 "$(gen_hex 10)" \
  --arg s6 "$(gen_hex 16)" \
  --arg s7 "$(gen_hex 14)" \
  --arg s8 "$(gen_hex 2)" \
  '[$s1, $s2, $s3, $s4, $s5, $s6, $s7, $s8]')

SUB_ID=$(head -c 8 /dev/urandom | xxd -p)

# JSON конфигов
SETTINGS=$(jq -nc \
  --arg id "$CLIENT_ID" \
  --arg sub "$SUB_ID" \
  '{clients:[{id:$id,flow:"xtls-rprx-vision",email:"client-1",limitIp:0,totalGB:0,expiryTime:0,enable:true,tgId:"",subId:$sub,comment:"",reset:0}],decryption:"none",encryption:"none"}')

STREAM_SETTINGS=$(jq -nc \
  --arg domain "$REALITY_DOMAIN" \
  --arg target "${REALITY_DOMAIN}:443" \
  --arg pk "$PRIVATE_KEY" \
  --arg pubk "$PUBLIC_KEY" \
  --argjson sids "$SHORT_IDS" \
  '{network:"tcp",security:"reality",externalProxy:[],realitySettings:{show:false,xver:0,target:$target,serverNames:[$domain],privateKey:$pk,minClientVer:"",maxClientVer:"",maxTimediff:0,shortIds:$sids,mldsa65Seed:"",settings:{publicKey:$pubk,fingerprint:"chrome",serverName:"",spiderX:"/",mldsa65Verify:""}},tcpSettings:{acceptProxyProtocol:false,header:{type:"none"}}}')

SNIFFING='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'

# Удаляем старое подключение
sqlite3 "$DB" "DELETE FROM inbounds WHERE remark='vless-reality'"

# Вставляем новое
# Получаем список колонок таблицы
COLUMNS=$(sqlite3 "$DB" "PRAGMA table_info(inbounds)" | cut -d'|' -f2 | tr '\n' ',')

# Базовые значения (всегда присутствуют)
SQL_COLS="user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing"
SQL_VALS="1, 0, 0, 0, 'vless-reality', 1, 0, '', $XRAY_PORT, 'vless', '$(echo "$SETTINGS" | sed "s/'/''/g")', '$(echo "$STREAM_SETTINGS" | sed "s/'/''/g")', 'inbound-$XRAY_PORT', '$(echo "$SNIFFING" | sed "s/'/''/g")'"

# Опциональные колонки (зависят от версии 3X-UI)
echo "$COLUMNS" | grep -q "all_time" && SQL_COLS="$SQL_COLS, all_time" && SQL_VALS="$SQL_VALS, 0"
echo "$COLUMNS" | grep -q "traffic_reset" && SQL_COLS="$SQL_COLS, traffic_reset" && SQL_VALS="$SQL_VALS, 'never'"
echo "$COLUMNS" | grep -q "last_traffic_reset_time" && SQL_COLS="$SQL_COLS, last_traffic_reset_time" && SQL_VALS="$SQL_VALS, 0"
echo "$COLUMNS" | grep -q "node_id" && SQL_COLS="$SQL_COLS, node_id" && SQL_VALS="$SQL_VALS, 0"
echo "$COLUMNS" | grep -q "allocate" && SQL_COLS="$SQL_COLS, allocate" && SQL_VALS="$SQL_VALS, '{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}'"

sqlite3 "$DB" "INSERT INTO inbounds ($SQL_COLS) VALUES ($SQL_VALS)"

x-ui restart >/dev/null 2>&1
sleep 3

echo -e "${GREEN}[5/6] Подключение создано${NC}"

# ============================================================
# 6. Итоговый вывод
# ============================================================
echo -e "${CYAN}[6/6] Генерация ссылки для клиента...${NC}"

SERVER_IP=$(curl -s4 ifconfig.me)
FIRST_SID=$(echo "$SHORT_IDS" | jq -r '.[0]')
VLESS_LINK="vless://${CLIENT_ID}@${SERVER_IP}:${XRAY_PORT}?type=tcp&security=reality&pbk=${PUBLIC_KEY}&fp=chrome&sni=${REALITY_DOMAIN}&sid=${FIRST_SID}&spx=%2F&flow=xtls-rprx-vision#vless-reality"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  УСТАНОВКА ЗАВЕРШЕНА!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}--- Панель 3X-UI ---${NC}"
echo -e "URL:          http://$SERVER_IP:$PANEL_PORT$PANEL_PATH"
echo -e "Логин:        $PANEL_USER"
echo -e "Пароль:       $PANEL_PASS"
echo ""
echo -e "${YELLOW}--- VPN подключение ---${NC}"
echo -e "Домен:        $REALITY_DOMAIN"
echo -e "Порт:         $XRAY_PORT"
echo -e "Public Key:   $PUBLIC_KEY"
echo ""
echo -e "${YELLOW}--- Ссылка для клиента (Throne/Nekoray/Hiddify) ---${NC}"
echo -e "${GREEN}$VLESS_LINK${NC}"
echo ""
echo -e "${YELLOW}--- Настройка DNS в клиенте (для российского VPS) ---${NC}"
echo -e "Remote DNS:   https://77.88.8.8/dns-query"
echo -e "Direct DNS:   77.88.8.8"
echo ""
echo -e "${RED}ВАЖНО: Сохрани эти данные! Они больше не будут показаны.${NC}"
echo ""

# Сохраняем в файл
cat > /root/vpn_credentials.txt <<EOF
=== Xray VPN Credentials ===
Дата установки: $(date)

Панель 3X-UI:
  URL:    http://$SERVER_IP:$PANEL_PORT$PANEL_PATH
  Логин:  $PANEL_USER
  Пароль: $PANEL_PASS

VPN:
  Домен Reality: $REALITY_DOMAIN
  Public Key:    $PUBLIC_KEY

Ссылка для клиента:
$VLESS_LINK

DNS для клиента:
  Remote: https://77.88.8.8/dns-query
  Direct: 77.88.8.8
EOF

chmod 600 /root/vpn_credentials.txt
echo -e "Данные сохранены в ${CYAN}/root/vpn_credentials.txt${NC}"
