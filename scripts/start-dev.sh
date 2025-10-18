#!/usr/bin/env bash
set -euo pipefail

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

PROJECT_FLAGS=()
if [[ -n "$GCP_PROJECT_ID" ]]; then
  PROJECT_FLAGS+=(--project "$GCP_PROJECT_ID")
fi

timestamp=$(date +%Y%m%d-%H%M%S)
INSTANCE_NAME=${SPOT_INSTANCE_NAME:-dev-spot-$timestamp}

mkdir -p "$ROOT_DIR/.state"

echo "[start] zone=$GCP_ZONE instance=$INSTANCE_NAME"

# 0) 确认静态 IP 存在
gcloud "${PROJECT_FLAGS[@]}" compute addresses describe "$ADDRESS_NAME" --region "$GCP_REGION" >/dev/null 2>&1 || {
  echo "[start] static address '$ADDRESS_NAME' not found in $GCP_REGION. Run scripts/setup-network.sh first." >&2
  exit 1
}

# 1) 准备永久磁盘（不存在则创建）
if gcloud "${PROJECT_FLAGS[@]}" compute disks describe "$DISK_NAME" --zone "$GCP_ZONE" >/dev/null 2>&1; then
  echo "[start] disk '$DISK_NAME' exists"
else
  gcloud "${PROJECT_FLAGS[@]}" compute disks create "$DISK_NAME" \
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
  if gcloud "${PROJECT_FLAGS[@]}" compute images describe-from-family "$IMAGE_FAMILY" \
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
cat > "$STARTUP_SCRIPT_FILE" <<'EOF'
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
if ! grep -qs '${MOUNT_POINT}' /proc/mounts; then
  mount -o discard,defaults ${MOUNT_DEVICE} ${MOUNT_POINT}
fi

# 添加到 fstab（如果还没有）
if ! grep -qs '${MOUNT_POINT}' /etc/fstab; then
  echo '${MOUNT_DEVICE} ${MOUNT_POINT} ext4 discard,defaults,nofail 0 2' >> /etc/fstab
fi

# 设置欢迎信息
echo '💻 开发机已准备好，工作目录 ${MOUNT_POINT}' > /etc/motd
EOF

# 替换脚本中的变量
sed -i "s|\${MOUNT_POINT}|${MOUNT_POINT}|g" "$STARTUP_SCRIPT_FILE"
sed -i "s|\${MOUNT_DEVICE}|${MOUNT_DEVICE}|g" "$STARTUP_SCRIPT_FILE"

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

# 5) 创建 Spot 实例
gcloud "${PROJECT_FLAGS[@]}" compute instances create "$INSTANCE_NAME" \
  --zone "$GCP_ZONE" \
  --machine-type "$SPOT_MACHINE_TYPE" \
  "${IMAGE_FLAGS[@]}" \
  --address "$ADDRESS_NAME" \
  --disk name="$DISK_NAME",mode=rw,boot=no,auto-delete=no \
  --provisioning-model=SPOT \
  --instance-termination-action="$TERMINATION_ACTION" \
  --max-run-duration="$MAX_RUN_DURATION" \
  "${TAGS_ARG[@]}" \
  "${SA_ARG[@]}" \
  "${LABELS_ARG[@]}" \
  --metadata-from-file startup-script="$STARTUP_SCRIPT_FILE"

# 6) 获取外网 IP 并输出连接指引
EXTERNAL_IP=$(gcloud "${PROJECT_FLAGS[@]}" compute instances describe "$INSTANCE_NAME" --zone "$GCP_ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "$INSTANCE_NAME" > "$ROOT_DIR/.state/last_instance_name"

cat <<MSG
[start] done
外网 IP: $EXTERNAL_IP

建议在 ~/.ssh/config 添加：
Host gcp-dev
  HostName $EXTERNAL_IP
  User <你的用户名>
  IdentityFile ~/.ssh/gcp_dev
  ServerAliveInterval 60

然后使用： ssh gcp-dev
工作目录： ${MOUNT_POINT}
自动删除： ${MAX_RUN_DURATION} 后，动作为 ${TERMINATION_ACTION}
MSG

