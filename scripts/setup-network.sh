#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
fi

GCP_PROJECT_ID=${GCP_PROJECT_ID:-}
GCP_REGION=${GCP_REGION:-asia-northeast1}
ADDRESS_NAME=${ADDRESS_NAME:-dev-ip}
FIREWALL_RULE_NAME=${FIREWALL_RULE_NAME:-allow-ssh}
SOURCE_RANGES_SSH=${SOURCE_RANGES_SSH:-0.0.0.0/0}
NETWORK_TAGS=${NETWORK_TAGS:-ssh}

PROJECT_FLAGS=()
if [[ -n "$GCP_PROJECT_ID" ]]; then
  PROJECT_FLAGS+=(--project "$GCP_PROJECT_ID")
fi

echo "[network] region=$GCP_REGION address=$ADDRESS_NAME"

# 1) 静态 IP（区域级）
if gcloud "${PROJECT_FLAGS[@]}" compute addresses describe "$ADDRESS_NAME" --region "$GCP_REGION" >/dev/null 2>&1; then
  echo "[network] address '$ADDRESS_NAME' already exists"
else
  gcloud "${PROJECT_FLAGS[@]}" compute addresses create "$ADDRESS_NAME" --region "$GCP_REGION"
  echo "[network] address '$ADDRESS_NAME' created"
fi

# 2) SSH 防火墙（基于 network tags）
if gcloud "${PROJECT_FLAGS[@]}" compute firewall-rules describe "$FIREWALL_RULE_NAME" >/dev/null 2>&1; then
  echo "[network] firewall '$FIREWALL_RULE_NAME' already exists"
else
  gcloud "${PROJECT_FLAGS[@]}" compute firewall-rules create "$FIREWALL_RULE_NAME" \
    --allow=tcp:22 \
    --target-tags="$NETWORK_TAGS" \
    --source-ranges="$SOURCE_RANGES_SSH"
  echo "[network] firewall '$FIREWALL_RULE_NAME' created"
fi

echo "[network] done"

