#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 ]]; then
  cat << 'EOF'
Usage:
  ./deploy-vps.sh <host> <admin_password> <reality_domain> [ssh_user] [image_tag] [panel_port] [xray_port]

Example:
  ./deploy-vps.sh 203.0.113.10 "MyStrongPass123" "www.samsung.com" root latest 1406 443
EOF
  exit 1
fi

HOST="$1"
ADMIN_PASSWORD="$2"
REALITY_DOMAIN="$3"
SSH_USER="${4:-root}"
IMAGE_TAG="${5:-latest}"
PANEL_PORT="${6:-1406}"
XRAY_PORT="${7:-443}"

IMAGE="infarh/xray-vpn:${IMAGE_TAG}"
CONTAINER_NAME="xray-vpn"

SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
)

echo "[deploy] Deploying ${IMAGE} to ${SSH_USER}@${HOST} ..."

ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HOST}" bash -s -- \
  "$IMAGE" \
  "$CONTAINER_NAME" \
  "$ADMIN_PASSWORD" \
  "$REALITY_DOMAIN" \
  "$PANEL_PORT" \
  "$XRAY_PORT" << 'REMOTE_SCRIPT'
set -euo pipefail

IMAGE="$1"
CONTAINER_NAME="$2"
ADMIN_PASSWORD="$3"
REALITY_DOMAIN="$4"
PANEL_PORT="$5"
XRAY_PORT="$6"

if ! command -v docker >/dev/null 2>&1; then
  echo "[deploy] Docker not found. Install Docker first."
  exit 1
fi

mkdir -p /opt/xray-vpn/data

echo "[deploy] Pulling image ${IMAGE} ..."
docker pull "${IMAGE}"

echo "[deploy] Recreating container ${CONTAINER_NAME} ..."
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p "${PANEL_PORT}:2053" \
  -p "${XRAY_PORT}:443" \
  -v /opt/xray-vpn/data:/etc/x-ui \
  -e XUI_ADMIN_USER=admin \
  -e XUI_ADMIN_PASS="${ADMIN_PASSWORD}" \
  -e XUI_PORT=2053 \
  -e XUI_WEB_BASE_PATH=/panel/ \
  -e XRAY_PORT=443 \
  -e XRAY_REALITY_DOMAIN="${REALITY_DOMAIN}" \
  "${IMAGE}"

echo "[deploy] Container started."
docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo "[deploy] Credentials file inside volume: /opt/xray-vpn/data/vpn_credentials.txt"
REMOTE_SCRIPT

echo "[deploy] Done."
