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
DISK_SIZE_GB=${DISK_SIZE_GB:-20}
DISK_TYPE=${DISK_TYPE:-pd-balanced}

# 持久 boot disk 配置（开启后系统盘也会持久化，apt 安装的软件不会丢失）
PERSIST_BOOT_DISK=${PERSIST_BOOT_DISK:-true}
BOOT_DISK_NAME=${BOOT_DISK_NAME:-dev-boot}
BOOT_DISK_SIZE_GB=${BOOT_DISK_SIZE_GB:-20}
BOOT_DISK_TYPE=${BOOT_DISK_TYPE:-pd-balanced}

IMAGE_FAMILY=${IMAGE_FAMILY:-}
IMAGE_PROJECT=${IMAGE_PROJECT:-}

# 默认镜像配置（当自定义镜像不存在时使用）
DEFAULT_IMAGE_FAMILY=${DEFAULT_IMAGE_FAMILY:-ubuntu-2404-lts-amd64}
DEFAULT_IMAGE_PROJECT=${DEFAULT_IMAGE_PROJECT:-ubuntu-os-cloud}

SPOT_INSTANCE_NAME=${SPOT_INSTANCE_NAME:-}
SPOT_MACHINE_TYPE=${SPOT_MACHINE_TYPE:-e2-standard-4}
MAX_RUN_DURATION=${MAX_RUN_DURATION:-4h}
TERMINATION_ACTION=${TERMINATION_ACTION:-DELETE}

NETWORK_TAGS=${NETWORK_TAGS:-ssh}
MOUNT_POINT=${MOUNT_POINT:-/workspace}
# 默认使用 /dev/disk/by-id/ 稳定路径（基于磁盘名），不受设备顺序影响
MOUNT_DEVICE=${MOUNT_DEVICE:-/dev/disk/by-id/google-${DISK_NAME}}

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

# 0) 确认 gcloud 可用
if ! command -v gcloud >/dev/null 2>&1; then
  echo "[start] gcloud CLI 未安装或未在 PATH 中，无法继续。" >&2
  echo "[start] 请先安装 gcloud (google-cloud-cli)，或确保它已在 PATH 中。" >&2
  exit 1
fi

# 0.5) 检查同名实例是否已存在
if run_gcloud compute instances describe "$INSTANCE_NAME" --zone "$GCP_ZONE" >/dev/null 2>&1; then
  echo "[start] ❌ 实例 '$INSTANCE_NAME' 已存在。" >&2
  echo "[start] 请先运行 bash scripts/destroy-dev.sh 或使用不同的 SPOT_INSTANCE_NAME。" >&2
  exit 1
fi

# 1) 确认静态 IP 存在
ADDR_DESCRIBE_ERR=""
if ! ADDR_DESCRIBE_ERR="$(run_gcloud compute addresses describe "$ADDRESS_NAME" --region "$GCP_REGION" 2>&1 1>/dev/null)"; then
  # gcloud 失败不一定是“资源不存在”，也可能是网络/权限/API 未启用等原因
  if [[ "$ADDR_DESCRIBE_ERR" == *"was not found"* || "$ADDR_DESCRIBE_ERR" == *"NOT_FOUND"* || "$ADDR_DESCRIBE_ERR" == *"not found"* ]]; then
    echo "[start] static address '$ADDRESS_NAME' not found in $GCP_REGION. Run scripts/setup-network.sh first." >&2
  else
    echo "[start] failed to query static address '$ADDRESS_NAME' in $GCP_REGION." >&2
    echo "[start] gcloud error:" >&2
    echo "$ADDR_DESCRIBE_ERR" >&2
    echo "[start] hint: check network/DNS/proxy/SSL connectivity to compute.googleapis.com, and ensure Compute Engine API is enabled + permissions are sufficient." >&2
  fi
  exit 1
fi

# 2) 准备永久磁盘（不存在则创建）
if run_gcloud compute disks describe "$DISK_NAME" --zone "$GCP_ZONE" >/dev/null 2>&1; then
  echo "[start] disk '$DISK_NAME' exists"
else
  run_gcloud compute disks create "$DISK_NAME" \
    --size="${DISK_SIZE_GB}GB" \
    --type="$DISK_TYPE" \
    --zone "$GCP_ZONE"
  echo "[start] disk '$DISK_NAME' created"
fi

# 3) 组装镜像参数 - 智能检测自定义镜像
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

# 2.5) 准备持久 boot disk（如果启用）
BOOT_DISK_EXISTS=false
if [[ "$PERSIST_BOOT_DISK" == "true" ]]; then
  echo "[start] 持久 boot disk 已启用: $BOOT_DISK_NAME"
  
  if run_gcloud compute disks describe "$BOOT_DISK_NAME" --zone "$GCP_ZONE" >/dev/null 2>&1; then
    echo "[start] ✓ boot disk '$BOOT_DISK_NAME' 已存在，将复用"
    BOOT_DISK_EXISTS=true
  else
    echo "[start] boot disk '$BOOT_DISK_NAME' 不存在，正在从镜像创建..."
    run_gcloud compute disks create "$BOOT_DISK_NAME" \
      --size="${BOOT_DISK_SIZE_GB}GB" \
      --type="$BOOT_DISK_TYPE" \
      --zone "$GCP_ZONE" \
      --image-family "$FINAL_IMAGE_FAMILY" \
      --image-project "$FINAL_IMAGE_PROJECT"
    echo "[start] ✓ boot disk '$BOOT_DISK_NAME' 已创建"
    BOOT_DISK_EXISTS=true
  fi
fi

# 3) 启动脚本（在实例内部执行）
STARTUP_SCRIPT_FILE="$ROOT_DIR/.state/startup-script.sh"
cat > "$STARTUP_SCRIPT_FILE" <<EOF
#!/bin/bash
set -euo pipefail

DEVICE="${MOUNT_DEVICE}"

# 等待设备就绪（GCE 磁盘挂载可能有短暂延迟）
echo "等待数据盘设备 \${DEVICE} 就绪..."
for i in \$(seq 1 30); do
  if [[ -e "\${DEVICE}" ]]; then
    break
  fi
  sleep 1
done

if [[ ! -e "\${DEVICE}" ]]; then
  echo "❌ 数据盘设备 \${DEVICE} 不存在，跳过挂载" >&2
  echo "请检查 .env 中 MOUNT_DEVICE 和 DISK_NAME 配置是否正确" >&2
  exit 1
fi

# 解析实际设备路径（符号链接 -> 块设备）
REAL_DEVICE=\$(readlink -f "\${DEVICE}")
echo "数据盘设备: \${DEVICE} -> \${REAL_DEVICE}"

# 安全检查：拒绝操作 boot 分区所在的磁盘
BOOT_DISK=\$(readlink -f /dev/disk/by-id/google-"${BOOT_DISK_NAME}" 2>/dev/null || echo "")
if [[ -n "\${BOOT_DISK}" && "\${REAL_DEVICE}" == "\${BOOT_DISK}"* ]]; then
  echo "❌ 安全检查失败: \${DEVICE} 解析为 \${REAL_DEVICE}，与 boot disk 冲突" >&2
  exit 1
fi

# 检查磁盘是否已格式化，如果没有则格式化
if ! blkid "\${DEVICE}" > /dev/null 2>&1; then
  echo "正在格式化 \${DEVICE} 为 ext4..."
  mkfs.ext4 -F "\${DEVICE}"
fi

# 创建挂载点
mkdir -p "${MOUNT_POINT}"

# 如果未挂载则挂载
if ! grep -qs "${MOUNT_POINT}" /proc/mounts; then
  mount -o discard,defaults "\${DEVICE}" "${MOUNT_POINT}"
fi

# 添加到 fstab（使用稳定设备路径，如果还没有）
if ! grep -qs "${MOUNT_POINT}" /etc/fstab; then
  echo "\${DEVICE} ${MOUNT_POINT} ext4 discard,defaults,nofail 0 2" >> /etc/fstab
fi

# 设置工作目录权限（确保属于配置的用户）
if id "${SSH_USERNAME}" &>/dev/null; then
  chown -R "${SSH_USERNAME}:${SSH_USERNAME}" "${MOUNT_POINT}"
  chmod 755 "${MOUNT_POINT}"
  echo "✓ ${MOUNT_POINT} 所有者已设置为 ${SSH_USERNAME}"

  # 首次启动时生成 SSH 密钥（避免镜像中共享密钥）
  SSH_KEY_FILE="/home/${SSH_USERNAME}/.ssh/id_ed25519"
  if [[ ! -f "\${SSH_KEY_FILE}" ]]; then
    sudo -u "${SSH_USERNAME}" bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && ssh-keygen -t ed25519 -C 'gcp-dev-machine' -f ~/.ssh/id_ed25519 -N ''"
    echo "✓ SSH 密钥已为 ${SSH_USERNAME} 自动生成"
  fi
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
  • fnm (Node.js LTS), uv (Python 3.12/3.13)

使用提示：
  • 所有工具已为 ${SSH_USERNAME} 用户配置完成
  • Docker 可直接使用，无需 sudo

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

# 6) 创建 Spot 实例
GCLOUD_INSTANCE_CREATE_ARGS=(
  --zone "$GCP_ZONE"
  --machine-type "$SPOT_MACHINE_TYPE"
  --address "$ADDRESS_NAME"
  --disk name="$DISK_NAME",mode=rw,boot=no,auto-delete=no
  --provisioning-model=SPOT
  --instance-termination-action="$TERMINATION_ACTION"
  --max-run-duration="$MAX_RUN_DURATION"
)

# 根据是否使用持久 boot disk 决定启动盘来源
if [[ "$PERSIST_BOOT_DISK" == "true" && "$BOOT_DISK_EXISTS" == "true" ]]; then
  # 使用持久 boot disk 启动（不再传 --image-family/--image-project）
  GCLOUD_INSTANCE_CREATE_ARGS+=(--disk "name=$BOOT_DISK_NAME,boot=yes,auto-delete=no,mode=rw")
  echo "[start] 使用持久 boot disk 启动: $BOOT_DISK_NAME"
elif [[ ${#IMAGE_FLAGS[@]} -gt 0 ]]; then
  # 回退到从镜像启动（boot disk 会随实例删除）
  GCLOUD_INSTANCE_CREATE_ARGS+=("${IMAGE_FLAGS[@]}")
  echo "[start] 使用镜像启动: $FINAL_IMAGE_FAMILY (boot disk 不持久化)"
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

BOOT_DISK_INFO=""
if [[ "$PERSIST_BOOT_DISK" == "true" ]]; then
  BOOT_DISK_INFO="系统盘： ${BOOT_DISK_NAME} (持久化，apt 安装的软件会保留)"
else
  BOOT_DISK_INFO="系统盘： 临时 (实例删除后会丢失)"
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
  ServerAliveCountMax 3
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/known_hosts.cloud-devbox
  # 注意: accept-new 会自动接受新主机密钥但拒绝变更的密钥
  # Spot 实例重建后主机密钥会变化，如遇连接拒绝可运行:
  # ssh-keygen -R $EXTERNAL_IP -f ~/.ssh/known_hosts.cloud-devbox

然后使用： ssh gcp-dev
工作目录： ${MOUNT_POINT}
${BOOT_DISK_INFO}
自动删除： ${MAX_RUN_DURATION} 后，动作为 ${TERMINATION_ACTION}
查看启动日志： gcloud compute instances get-serial-port-output ${INSTANCE_NAME} --zone ${GCP_ZONE}
MSG
