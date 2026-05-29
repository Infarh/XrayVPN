# Настройка Xray VPN (VLESS Reality) на VPS

## Требования

- VPS с Ubuntu 24.04+ (1 core, 2 GB RAM минимум)
- SSH-доступ под root
- Клиент: Throne / Nekoray / Hiddify

---

## 1. Автоматическая установка

Подключиться к серверу по SSH и выполнить:

```bash
bash <(curl -Ls https://gist.githubusercontent.com/Platonenkov/b3c556e15edecc1c3a624d9a048ed903/raw/full_setup.sh)
```

Скрипт спросит параметры (Enter — значение по умолчанию):

| Параметр | По умолчанию | Описание |
|----------|-------------|----------|
| Порт панели | `1406` | Порт веб-панели 3X-UI |
| Логин | `admin` | Логин для входа в панель |
| Пароль | авто | Если не задать — сгенерируется случайный |
| Web Base Path | `/panel/` | Секретный путь к панели |
| Домен Reality | авто | Сканирует подсеть и выбирает подходящий |

Скрипт автоматически:
- Обновляет систему и ставит зависимости
- Устанавливает 3X-UI панель
- Сканирует подсеть для поиска домена Reality
- Создаёт VLESS Reality подключение
- Выводит готовую ссылку `vless://...` для клиента
- Сохраняет все данные в `/root/vpn_credentials.txt`

---

## 2. Клиенты — скачивание и установка

### Windows

| Клиент | Скачать | Описание |
|--------|---------|----------|
| **Hiddify** | [GitHub Releases](https://github.com/hiddify/hiddify-app/releases) | Простой, рекомендуется для новичков. Скачать `Hiddify-Windows-Setup-x64.exe` |
| **Throne** | [GitHub Releases](https://github.com/nicezar/Throne/releases) | Форк Nekoray с улучшениями. Скачать `Throne-*-windows-x64.zip` |
| **Nekoray** | [GitHub Releases](https://github.com/MatsuriDayo/nekoray/releases) | Продвинутый, больше настроек. Скачать `nekoray-*-windows64.zip` |

### Android

| Клиент | Скачать | Описание |
|--------|---------|----------|
| **Hiddify** | [GitHub Releases](https://github.com/hiddify/hiddify-app/releases) / [Google Play](https://play.google.com/store/apps/details?id=app.hiddify.com) | Универсальный, простой |
| **v2rayNG** | [GitHub Releases](https://github.com/2dust/v2rayNG/releases) / [Google Play](https://play.google.com/store/apps/details?id=com.v2ray.ang) | Популярный, стабильный |
| **NekoBox** | [GitHub Releases](https://github.com/MatsuriDayo/NekoBoxForAndroid/releases) | Продвинутый, гибкая маршрутизация |

### iOS

| Клиент | Скачать | Описание |
|--------|---------|----------|
| **Hiddify** | [App Store](https://apps.apple.com/app/hiddify-proxy-vpn/id6596777532) | Бесплатный |
| **Streisand** | [App Store](https://apps.apple.com/app/streisand/id6450534064) | Бесплатный, простой |
| **V2Box** | [App Store](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) | Бесплатный |

### macOS / Linux

| Клиент | Скачать | Описание |
|--------|---------|----------|
| **Hiddify** | [GitHub Releases](https://github.com/hiddify/hiddify-app/releases) | macOS и Linux |
| **Nekoray** | [GitHub Releases](https://github.com/MatsuriDayo/nekoray/releases) | Linux |

---

## 3. Настройка клиента

### Hiddify (Windows / Android / iOS / macOS)

1. Открыть приложение
2. Нажать **+** (добавить профиль) → **Добавить из буфера обмена**
3. Вставить ссылку `vless://...` из вывода скрипта
4. Нажать на кнопку подключения (большая круглая кнопка)

Hiddify автоматически настроит DNS и маршрутизацию.

### Throne / Nekoray (Windows / Linux)

1. При первом запуске выбрать ядро **sing-box**
2. **Profiles → Add Profile from Clipboard** (или Ctrl+V)
3. Правый клик на профиле → **Start**
4. Включить **Tun Mode** (галочка вверху)

#### Настройка DNS (важно для российского VPS!)

**Routing → DNS:**

| Параметр | Значение |
|----------|----------|
| Remote DNS | `https://77.88.8.8/dns-query` |
| Direct DNS | `77.88.8.8` |

Google DNS over TLS (`tls://8.8.8.8`) заблокирован в России — использовать Яндекс DNS.

### v2rayNG (Android)

1. Нажать **+** → **Импорт из буфера обмена**
2. Вставить ссылку `vless://...`
3. Нажать кнопку ▶ для подключения
4. При первом запуске разрешить VPN-соединение

### Streisand / V2Box (iOS)

1. Скопировать ссылку `vless://...`
2. Открыть приложение → **+** → **Импорт из буфера**
3. Выбрать сервер и нажать **Подключить**
4. Разрешить добавление VPN-конфигурации

---

## 4. Проверка

Зайти на сайт проверки IP (например whatismyipaddress.com).
Должен показать IP VPS-сервера и соответствующую локацию.

---

## Управление сервером

### Полезные команды

```bash
x-ui                 # интерактивное меню
x-ui status          # статус панели
x-ui restart         # перезапуск
x-ui log             # логи
x-ui settings        # текущие настройки

# Проверить что Xray слушает порт
ss -tlnp | grep 443

# Текущий конфиг подключения
sqlite3 /etc/x-ui/x-ui.db "SELECT stream_settings FROM inbounds WHERE remark='vless-reality'" | jq .
```

### Интерактивное меню (x-ui)

- `6` — сброс логина/пароля
- `7` — сброс Web Base Path (генерирует случайный)
- `9` — смена порта панели
- `10` — просмотр текущих настроек

### Смена Web Base Path на свой

```bash
sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='/mypath/' WHERE key='webBasePath'"
x-ui restart
```

### Смена домена Reality через консоль

```bash
apt install sqlite3 jq -y
DOMAIN="www.ozon.ru"
CURRENT=$(sqlite3 /etc/x-ui/x-ui.db "SELECT stream_settings FROM inbounds WHERE remark='vless-reality'")
UPDATED=$(echo "$CURRENT" | jq \
  --arg domain "$DOMAIN" \
  --arg target "${DOMAIN}:443" \
  '.realitySettings.target = $target | .realitySettings.serverNames = [$domain]')
sqlite3 /etc/x-ui/x-ui.db "UPDATE inbounds SET stream_settings='$(echo "$UPDATED" | tr -d '\n')' WHERE remark='vless-reality'"
x-ui restart
```

После смены домена — переэкспортировать ссылку и переимпортировать в клиенте.

### Сканирование доменов для Reality

```bash
go install github.com/xtls/RealiTLScanner@latest
~/go/bin/RealiTLScanner -addr <IP_ПОДСЕТЬ>/24 -thread 10 -timeout 5
```

---

## Защита SSH (опционально)

### Смена порта

```bash
nano /etc/ssh/sshd_config
```

Заменить `Port 22` на кастомный (10000–65535):

```
Port 43921
```

```bash
systemctl restart sshd
```

**Не закрывать текущую сессию!** Проверить вход через новый порт в отдельном терминале.

---

## Примечания

- **Госуслуги** — блокируют IP дата-центров, работают только с резидентными (домашними) IP
- **Торренты** — рекомендуется заблокировать в настройках Xray, чтобы избежать abuse от хостера
- При смене домена Reality — обязательно переэкспортировать ссылку и переимпортировать в клиенте
- Данные доступа сохраняются на сервере в `/root/vpn_credentials.txt`

---

## Docker-режим (образ `infarh/xray-vpn`)

В репозитории добавлены файлы:

- `Dockerfile`
- `docker-entrypoint.sh`
- `build-linux.sh`
- `build-windows.ps1`
- `deploy-vps.sh`

### Сборка образа (Linux)

```bash
chmod +x build-linux.sh
./build-linux.sh latest

# Сборка + отправка в Docker Registry
./build-linux.sh latest --push
```

### Сборка образа (Windows PowerShell)

```powershell
.\build-windows.ps1 -Tag latest

# Сборка + отправка в Docker Registry
.\build-windows.ps1 -Tag latest -Push
```

### Ручной запуск контейнера

```bash
docker run -d \
  --name xray-vpn \
  --restart unless-stopped \
  -p 1406:2053 \
  -p 443:443 \
  -v /opt/xray-vpn/data:/etc/x-ui \
  -e XUI_ADMIN_USER=admin \
  -e XUI_ADMIN_PASS='СЮДА_ВАШ_ПАРОЛЬ' \
  -e XUI_WEB_BASE_PATH=/panel/ \
  -e XRAY_REALITY_DOMAIN=www.samsung.com \
  infarh/xray-vpn:latest
```

`XUI_ADMIN_PASS` задаётся при старте контейнера. Если не передать, пароль будет сгенерирован автоматически и выведен в лог контейнера.

### Автодеплой на VPS через SSH (Linux)

```bash
chmod +x deploy-vps.sh
./deploy-vps.sh <VPS_IP> '<ADMIN_PASSWORD>' <REALITY_DOMAIN> [SSH_USER] [IMAGE_TAG] [PANEL_PORT] [XRAY_PORT]
```

Пример:

```bash
./deploy-vps.sh 203.0.113.10 'StrongPass123' www.samsung.com root latest 1406 443
```

После запуска контейнера файл с ключевыми данными сохраняется в volume:

```bash
/opt/xray-vpn/data/vpn_credentials.txt
```
