#!/usr/bin/env bash
set -euo pipefail

# 记录脚本开始时间
SCRIPT_START_TIME=$(date +%s)
SCRIPT_NAME=$(basename "$0")

# 在脚本退出时显示运行时长
cleanup_and_show_duration() {
  local exit_code=$?
  local end_time=$(date +%s)
  local duration=$((end_time - SCRIPT_START_TIME))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))
  
  echo ""
  if [ $minutes -gt 0 ]; then
    echo "[$SCRIPT_NAME] 运行时长: ${minutes}m ${seconds}s"
  else
    echo "[$SCRIPT_NAME] 运行时长: ${seconds}s"
  fi
  
  exit $exit_code
}

trap cleanup_and_show_duration EXIT

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
fi

GCP_PROJECT_ID=${GCP_PROJECT_ID:-}
GCP_ZONE=${GCP_ZONE:-asia-northeast1-a}
LABEL_KEY=${LABEL_KEY:-devbox}
LABEL_VALUE=${LABEL_VALUE:-yes}

PROJECT_FLAGS=()
if [[ -n "$GCP_PROJECT_ID" ]]; then
  PROJECT_FLAGS+=(--project "$GCP_PROJECT_ID")
fi

TARGET_INSTANCE=${1:-}

if [[ -z "$TARGET_INSTANCE" && -f "$ROOT_DIR/.state/last_instance_name" ]]; then
  TARGET_INSTANCE=$(cat "$ROOT_DIR/.state/last_instance_name")
fi

if [[ -n "$TARGET_INSTANCE" ]]; then
  echo "[destroy] deleting instance: $TARGET_INSTANCE"
  gcloud "${PROJECT_FLAGS[@]}" compute instances delete "$TARGET_INSTANCE" --zone "$GCP_ZONE" --quiet || true
  exit 0
fi

echo "[destroy] no explicit instance specified, deleting labeled instances"
mapfile -t INSTANCES < <(gcloud "${PROJECT_FLAGS[@]}" compute instances list \
  --filter="labels.${LABEL_KEY}=${LABEL_VALUE} AND status~'RUNNING|PROVISIONING'" \
  --format='get(name)')

if (( ${#INSTANCES[@]} == 0 )); then
  echo "[destroy] nothing to delete"
  exit 0
fi

for name in "${INSTANCES[@]}"; do
  echo "[destroy] deleting $name"
  gcloud "${PROJECT_FLAGS[@]}" compute instances delete "$name" --zone "$GCP_ZONE" --quiet || true
done

echo "[destroy] done"

