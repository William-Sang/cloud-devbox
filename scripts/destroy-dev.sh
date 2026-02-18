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

# 持久 boot disk 配置
BOOT_DISK_NAME=${BOOT_DISK_NAME:-dev-boot}

PROJECT_FLAGS=()
if [[ -n "$GCP_PROJECT_ID" ]]; then
  PROJECT_FLAGS+=(--project "$GCP_PROJECT_ID")
fi

run_gcloud() {
  if [[ ${#PROJECT_FLAGS[@]} -gt 0 ]]; then
    gcloud "${PROJECT_FLAGS[@]}" "$@"
  else
    gcloud "$@"
  fi
}

# 解析参数
PURGE_BOOT=false
TARGET_INSTANCE=""

for arg in "$@"; do
  case "$arg" in
    --purge-boot)
      PURGE_BOOT=true
      ;;
    --help|-h)
      echo "用法: $(basename "$0") [实例名] [--purge-boot]"
      echo ""
      echo "选项:"
      echo "  实例名       要删除的实例名称（可选，默认从 .state 读取或按标签删除）"
      echo "  --purge-boot 同时删除持久 boot disk（$BOOT_DISK_NAME）"
      echo ""
      echo "示例:"
      echo "  $(basename "$0")                  # 删除上次创建的实例"
      echo "  $(basename "$0") --purge-boot     # 删除实例并清理 boot disk"
      echo "  $(basename "$0") dev-spot-xxx     # 删除指定实例"
      exit 0
      ;;
    *)
      if [[ -z "$TARGET_INSTANCE" && ! "$arg" =~ ^-- ]]; then
        TARGET_INSTANCE="$arg"
      fi
      ;;
  esac
done

if [[ -z "$TARGET_INSTANCE" && -f "$ROOT_DIR/.state/last_instance_name" ]]; then
  TARGET_INSTANCE=$(cat "$ROOT_DIR/.state/last_instance_name")
fi

# 删除实例的函数
delete_instances() {
  local deleted=false
  
  if [[ -n "$TARGET_INSTANCE" ]]; then
    echo "[destroy] deleting instance: $TARGET_INSTANCE"
    if ! run_gcloud compute instances delete "$TARGET_INSTANCE" --zone "$GCP_ZONE" --quiet; then
      echo "[destroy] ⚠ 删除实例 '$TARGET_INSTANCE' 失败（可能已不存在或权限不足）" >&2
    else
      deleted=true
    fi
  else
    echo "[destroy] no explicit instance specified, deleting labeled instances"
    INSTANCE_LIST=$(run_gcloud compute instances list \
      --filter="labels.${LABEL_KEY}=${LABEL_VALUE} AND zone:${GCP_ZONE} AND status:(RUNNING PROVISIONING)" \
      --format='get(name)')

    if [[ -z "${INSTANCE_LIST//[[:space:]]/}" ]]; then
      echo "[destroy] no instances to delete"
    else
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        echo "[destroy] deleting $name"
        if ! run_gcloud compute instances delete "$name" --zone "$GCP_ZONE" --quiet; then
          echo "[destroy] ⚠ 删除实例 '$name' 失败" >&2
        else
          deleted=true
        fi
      done <<< "$INSTANCE_LIST"
    fi
  fi
  
  echo "$deleted"
}

# 执行实例删除
delete_instances

# 如果指定了 --purge-boot，同时删除持久 boot disk
if [[ "$PURGE_BOOT" == "true" ]]; then
  echo ""
  echo "[destroy] --purge-boot 已指定，检查 boot disk: $BOOT_DISK_NAME"
  
  if run_gcloud compute disks describe "$BOOT_DISK_NAME" --zone "$GCP_ZONE" >/dev/null 2>&1; then
    echo "[destroy] 正在删除 boot disk: $BOOT_DISK_NAME"
    if ! run_gcloud compute disks delete "$BOOT_DISK_NAME" --zone "$GCP_ZONE" --quiet; then
      echo "[destroy] ⚠ 删除 boot disk '$BOOT_DISK_NAME' 失败" >&2
    fi
    echo "[destroy] ✓ boot disk '$BOOT_DISK_NAME' 已删除"
  else
    echo "[destroy] boot disk '$BOOT_DISK_NAME' 不存在，跳过"
  fi
else
  echo ""
  echo "[destroy] 提示: 持久 boot disk '$BOOT_DISK_NAME' 未删除（如需删除，使用 --purge-boot）"
fi

echo "[destroy] done"
