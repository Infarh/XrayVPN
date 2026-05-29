#!/usr/bin/env bash

set -euo pipefail

IMAGE_NAME="infarh/xray-vpn"
TAG="${1:-latest}"
PUSH="${2:-}"

FULL_IMAGE="${IMAGE_NAME}:${TAG}"

echo "[build] Building ${FULL_IMAGE}..."
docker build -t "${FULL_IMAGE}" .

echo "[build] Build done: ${FULL_IMAGE}"

if [[ "${PUSH}" == "--push" ]]; then
  echo "[build] Pushing ${FULL_IMAGE}..."
  docker push "${FULL_IMAGE}"
  echo "[build] Push done"
fi
