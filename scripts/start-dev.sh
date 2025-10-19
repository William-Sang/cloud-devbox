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
GCP_REGION=${GCP_REGION:-asia-northeast1}
GCP_ZONE=${GCP_ZONE:-asia-northeast1-a}

ADDRESS_NAME=${ADDRESS_NAME:-dev-ip}
DISK_NAME=${DISK_NAME:-dev-data}
DISK_SIZE_GB=${DISK_SIZE_GB:-100}
DISK_TYPE=${DISK_TYPE:-pd-balanced}

IMAGE_FAMILY=${IMAGE_FAMILY:-}
IMAGE_PROJECT=${IMAGE_PROJECT:-}

# 默认镜像配置（当自定义镜像不存在时使用）
DEFAULT_IMAGE_FAMILY=${DEFAULT_IMAGE_FAMILY:-debian-12}
DEFAULT_IMAGE_PROJECT=${DEFAULT_IMAGE_PROJECT:-debian-cloud}

SPOT_INSTANCE_NAME=${SPOT_INSTANCE_NAME:-}
SPOT_MACHINE_TYPE=${SPOT_MACHINE_TYPE:-e2-standard-4}
MAX_RUN_DURATION=${MAX_RUN_DURATION:-4h}
TERMINATION_ACTION=${TERMINATION_ACTION:-DELETE}

NETWORK_TAGS=${NETWORK_TAGS:-ssh}
MOUNT_POINT=${MOUNT_POINT:-/workspace}
MOUNT_DEVICE=${MOUNT_DEVICE:-/dev/sdb}

LABEL_KEY=${LABEL_KEY:-devbox}
LABEL_VALUE=${LABEL_VALUE:-yes}

SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_EMAIL:-}

# SSH 配置
SSH_USERNAME=${SSH_USERNAME:-dev}
SSH_PUBLIC_KEY_FILE=${SSH_PUBLIC_KEY_FILE:-}

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

timestamp=$(date +%Y%m%d-%H%M%S)
INSTANCE_NAME=${SPOT_INSTANCE_NAME:-dev-spot-$timestamp}

mkdir -p "$ROOT_DIR/.state"

echo "[start] zone=$GCP_ZONE instance=$INSTANCE_NAME"

# 0) 确认静态 IP 存在
run_gcloud compute addresses describe "$ADDRESS_NAME" --region "$GCP_REGION" >/dev/null 2>&1 || {
  echo "[start] static address '$ADDRESS_NAME' not found in $GCP_REGION. Run scripts/setup-network.sh first." >&2
  exit 1
}

# 1) 准备永久磁盘（不存在则创建）
if run_gcloud compute disks describe "$DISK_NAME" --zone "$GCP_ZONE" >/dev/null 2>&1; then
  echo "[start] disk '$DISK_NAME' exists"
else
  run_gcloud compute disks create "$DISK_NAME" \
    --size="${DISK_SIZE_GB}GB" \
    --type="$DISK_TYPE" \
    --zone "$GCP_ZONE"
  echo "[start] disk '$DISK_NAME' created"
fi

# 2) 组装镜像参数 - 智能检测自定义镜像
IMAGE_FLAGS=()
FINAL_IMAGE_FAMILY=""
FINAL_IMAGE_PROJECT=""

if [[ -n "$IMAGE_FAMILY" && -n "$IMAGE_PROJECT" ]]; then
  # 检测自定义镜像是否存在
  echo "[start] 检测自定义镜像: $IMAGE_FAMILY (项目: $IMAGE_PROJECT)"
  if run_gcloud compute images describe-from-family "$IMAGE_FAMILY" \
       --project "$IMAGE_PROJECT" >/dev/null 2>&1; then
    echo "[start] ✓ 找到自定义镜像，使用: $IMAGE_FAMILY"
    FINAL_IMAGE_FAMILY="$IMAGE_FAMILY"
    FINAL_IMAGE_PROJECT="$IMAGE_PROJECT"
  else
    echo "[start] ✗ 自定义镜像不存在，回退到默认镜像: $DEFAULT_IMAGE_FAMILY"
    FINAL_IMAGE_FAMILY="$DEFAULT_IMAGE_FAMILY"
    FINAL_IMAGE_PROJECT="$DEFAULT_IMAGE_PROJECT"
  fi
else
  # 未配置自定义镜像，直接使用默认镜像
  echo "[start] 未配置自定义镜像，使用默认镜像: $DEFAULT_IMAGE_FAMILY"
  FINAL_IMAGE_FAMILY="$DEFAULT_IMAGE_FAMILY"
  FINAL_IMAGE_PROJECT="$DEFAULT_IMAGE_PROJECT"
fi

IMAGE_FLAGS+=(--image-family "$FINAL_IMAGE_FAMILY" --image-project "$FINAL_IMAGE_PROJECT")

# 3) 启动脚本（在实例内部执行）
STARTUP_SCRIPT_FILE="$ROOT_DIR/.state/startup-script.sh"
cat > "$STARTUP_SCRIPT_FILE" <<EOF
#!/bin/bash
set -e

# 检查磁盘是否已格式化，如果没有则格式化
if ! blkid ${MOUNT_DEVICE} > /dev/null 2>&1; then
  echo "正在格式化 ${MOUNT_DEVICE} 为 ext4..."
  mkfs.ext4 -F ${MOUNT_DEVICE}
fi

# 创建挂载点
mkdir -p ${MOUNT_POINT}

# 如果未挂载则挂载
if ! grep -qs "${MOUNT_POINT}" /proc/mounts; then
  mount -o discard,defaults ${MOUNT_DEVICE} ${MOUNT_POINT}
fi

# 添加到 fstab（如果还没有）
if ! grep -qs "${MOUNT_POINT}" /etc/fstab; then
  echo "${MOUNT_DEVICE} ${MOUNT_POINT} ext4 discard,defaults,nofail 0 2" >> /etc/fstab
fi

# 设置工作目录权限（确保属于配置的用户）
if id "${SSH_USERNAME}" &>/dev/null; then
  chown -R ${SSH_USERNAME}:${SSH_USERNAME} ${MOUNT_POINT}
  chmod 755 ${MOUNT_POINT}
  echo "✓ ${MOUNT_POINT} 所有者已设置为 ${SSH_USERNAME}"
fi

# 设置欢迎信息
cat > /etc/motd <<MOTD
╔══════════════════════════════════════════════════════════════╗
║            💻  GCP 开发机                                    ║
╚══════════════════════════════════════════════════════════════╝

工作目录: ${MOUNT_POINT} (属于 ${SSH_USERNAME})
登录用户: ${SSH_USERNAME}

已安装工具：
  • Docker、Git、Vim (amix/vimrc)
  • mise (Node.js LTS, Python 3.12)

使用提示：
  • 所有工具已为 ${SSH_USERNAME} 用户配置完成
  • Docker 可直接使用，无需 sudo
  • mise 已自动激活

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MOTD
EOF

# 4) 组装通用参数
TAGS_ARG=()
if [[ -n "$NETWORK_TAGS" ]]; then
  TAGS_ARG+=(--tags="$NETWORK_TAGS")
fi

SA_ARG=()
if [[ -n "$SERVICE_ACCOUNT_EMAIL" ]]; then
  SA_ARG+=(--service-account "$SERVICE_ACCOUNT_EMAIL" --scopes cloud-platform)
fi

LABELS_ARG=(--labels "${LABEL_KEY}=${LABEL_VALUE}")

# 5) 准备 SSH 公钥
SSH_KEYS_METADATA=()
SSH_IDENTITY_FILE_PATH=""
if [[ -n "${SSH_PUBLIC_KEY_FILE:-}" ]]; then
  SSH_KEY_PATH="$SSH_PUBLIC_KEY_FILE"

  case "$SSH_KEY_PATH" in
    ~*)
      SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
      ;;
    /*)
      ;;
    ./*)
      SSH_KEY_PATH="$ROOT_DIR/${SSH_KEY_PATH#./}"
      ;;
    *)
      SSH_KEY_PATH="$ROOT_DIR/$SSH_KEY_PATH"
      ;;
  esac

  if [[ -f "$SSH_KEY_PATH" ]]; then
    SSH_KEY_CONTENT=$(cat "$SSH_KEY_PATH")
    # 使用 --metadata 直接传递（转义特殊字符）
    SSH_KEYS_METADATA+=(--metadata "ssh-keys=${SSH_USERNAME}:${SSH_KEY_CONTENT}")
    if [[ "$SSH_KEY_PATH" == *.pub ]]; then
      SSH_IDENTITY_FILE_PATH="${SSH_KEY_PATH%.pub}"
    else
      SSH_IDENTITY_FILE_PATH="$SSH_KEY_PATH"
    fi
    echo "[start] 添加 SSH 公钥: $SSH_PUBLIC_KEY_FILE (用户: $SSH_USERNAME)"
  else
    echo "[start] 未找到 SSH 公钥文件 ($SSH_PUBLIC_KEY_FILE)，将跳过公钥注入"
  fi
fi

# 5) 创建 Spot 实例
GCLOUD_INSTANCE_CREATE_ARGS=(
  --zone "$GCP_ZONE"
  --machine-type "$SPOT_MACHINE_TYPE"
  --address "$ADDRESS_NAME"
  --disk name="$DISK_NAME",mode=rw,boot=no,auto-delete=no
  --provisioning-model=SPOT
  --instance-termination-action="$TERMINATION_ACTION"
  --max-run-duration="$MAX_RUN_DURATION"
)

if [[ ${#IMAGE_FLAGS[@]} -gt 0 ]]; then
  GCLOUD_INSTANCE_CREATE_ARGS+=("${IMAGE_FLAGS[@]}")
fi

if [[ ${#TAGS_ARG[@]} -gt 0 ]]; then
  GCLOUD_INSTANCE_CREATE_ARGS+=("${TAGS_ARG[@]}")
fi

if [[ ${#SA_ARG[@]} -gt 0 ]]; then
  GCLOUD_INSTANCE_CREATE_ARGS+=("${SA_ARG[@]}")
fi

if [[ ${#LABELS_ARG[@]} -gt 0 ]]; then
  GCLOUD_INSTANCE_CREATE_ARGS+=("${LABELS_ARG[@]}")
fi

if [[ ${#SSH_KEYS_METADATA[@]} -gt 0 ]]; then
  GCLOUD_INSTANCE_CREATE_ARGS+=("${SSH_KEYS_METADATA[@]}")
fi

GCLOUD_INSTANCE_CREATE_ARGS+=(--metadata-from-file "startup-script=$STARTUP_SCRIPT_FILE")

run_gcloud compute instances create "$INSTANCE_NAME" "${GCLOUD_INSTANCE_CREATE_ARGS[@]}"

# 6) 获取外网 IP 并输出连接指引
EXTERNAL_IP=$(run_gcloud compute instances describe "$INSTANCE_NAME" --zone "$GCP_ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "$INSTANCE_NAME" > "$ROOT_DIR/.state/last_instance_name"

IDENTITY_FILE_CONFIG=""
if [[ -n "$SSH_IDENTITY_FILE_PATH" ]]; then
  IDENTITY_FILE_CONFIG="  IdentityFile $SSH_IDENTITY_FILE_PATH"
fi

cat <<MSG
[start] done
外网 IP: $EXTERNAL_IP

建议在 ~/.ssh/config 添加：
Host gcp-dev
  HostName $EXTERNAL_IP
  User ${SSH_USERNAME}
${IDENTITY_FILE_CONFIG}
  ServerAliveInterval 60

然后使用： ssh gcp-dev
工作目录： ${MOUNT_POINT}
自动删除： ${MAX_RUN_DURATION} 后，动作为 ${TERMINATION_ACTION}
MSG
