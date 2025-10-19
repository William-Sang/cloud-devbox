#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
用法: $(basename "$0") <create-builder|create-image|delete-builder>

  create-builder  创建临时构建机并通过 metadata 传入配置脚本
                  脚本会自动保存到实例主目录: ~/builder-setup.sh
                  需要手动 SSH 登录后执行脚本（方便调试）
                  
  create-image    从构建机系统盘创建镜像并加入镜像族
  
  delete-builder  删除构建机实例

工作流程:
  1. bash scripts/build-image.sh create-builder
  2. gcloud compute ssh <builder-name>
  3. sudo bash ~/builder-setup.sh
  4. sudo poweroff (在 builder 实例中)
  5. bash scripts/build-image.sh create-image

提示:
  • 编辑 scripts/builder-setup.sh 自定义安装内容
  • 手动执行脚本可以实时查看输出和调试
  • 如遇问题，可以分步执行脚本中的命令
EOF
}

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
fi

CMD=${1:-}
GCP_PROJECT_ID=${GCP_PROJECT_ID:-}
GCP_ZONE=${GCP_ZONE:-asia-northeast1-a}

BUILDER_INSTANCE_NAME=${BUILDER_INSTANCE_NAME:-dev-builder}
BUILDER_MACHINE_TYPE=${BUILDER_MACHINE_TYPE:-e2-standard-4}
BASE_IMAGE_FAMILY=${BASE_IMAGE_FAMILY:-debian-12}
BASE_IMAGE_PROJECT=${BASE_IMAGE_PROJECT:-debian-cloud}

IMAGE_FAMILY=${IMAGE_FAMILY:-dev-gold}

PROJECT_FLAGS=()
if [[ -n "$GCP_PROJECT_ID" ]]; then
  PROJECT_FLAGS+=(--project "$GCP_PROJECT_ID")
fi

case "$CMD" in
  create-builder)
    echo "[image] creating builder: $BUILDER_INSTANCE_NAME"
    
    # 检查配置脚本是否存在
    BUILDER_SETUP_SCRIPT="$ROOT_DIR/scripts/builder-setup.sh"
    if [[ ! -f "$BUILDER_SETUP_SCRIPT" ]]; then
      echo "[image] ❌ 未找到 builder-setup.sh"
      echo "[image] 路径: $BUILDER_SETUP_SCRIPT"
      exit 1
    fi
    
    echo "[image] ✓ 找到配置脚本: builder-setup.sh"
    
    # 创建临时的初始化脚本
    # 该脚本会在实例启动时执行，从 metadata 中读取 builder-setup.sh
    TEMP_INIT_SCRIPT=$(mktemp)
    cat > "$TEMP_INIT_SCRIPT" <<'EOF'
#!/bin/bash
# 从 metadata 中提取 builder-setup.sh 并保存到用户主目录

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 准备 Builder 配置脚本"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 获取默认用户
DEFAULT_USER=$(ls /home 2>/dev/null | head -n 1)

# 从 metadata 获取脚本内容并保存到 root 主目录
echo "正在从 metadata 获取配置脚本..."
curl -sf -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/builder-script" \
  -o /root/builder-setup.sh

if [[ $? -eq 0 ]] && [[ -f /root/builder-setup.sh ]]; then
  chmod +x /root/builder-setup.sh
  echo "✓ 脚本已保存: /root/builder-setup.sh"
  
  # 如果有普通用户，也复制一份
  if [[ -n "$DEFAULT_USER" ]]; then
    cp /root/builder-setup.sh /home/$DEFAULT_USER/builder-setup.sh
    chown $DEFAULT_USER:$DEFAULT_USER /home/$DEFAULT_USER/builder-setup.sh
    chmod +x /home/$DEFAULT_USER/builder-setup.sh
    echo "✓ 脚本已复制: /home/$DEFAULT_USER/builder-setup.sh"
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✅ Builder 脚本已准备就绪"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "执行配置脚本: sudo bash ~/builder-setup.sh"
  echo ""
else
  echo "❌ 无法获取配置脚本"
  exit 1
fi
EOF
    
    echo "[image] 正在创建实例并传入脚本..."
    
    # 创建实例，通过 metadata 传入脚本
    gcloud "${PROJECT_FLAGS[@]}" compute instances create "$BUILDER_INSTANCE_NAME" \
      --zone "$GCP_ZONE" \
      --machine-type "$BUILDER_MACHINE_TYPE" \
      --image-family "$BASE_IMAGE_FAMILY" --image-project "$BASE_IMAGE_PROJECT" \
      --metadata-from-file startup-script="$TEMP_INIT_SCRIPT",builder-script="$BUILDER_SETUP_SCRIPT"
    
    # 清理临时文件
    rm -f "$TEMP_INIT_SCRIPT"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Builder 实例已创建"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "实例名称: $BUILDER_INSTANCE_NAME"
    echo "区域:     $GCP_ZONE"
    echo ""
    echo "📝 脚本已通过 metadata 传入实例 (~/builder-setup.sh)"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "下一步："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "手动执行配置："
    echo "  1. SSH 登录:"
    echo "     gcloud compute ssh $BUILDER_INSTANCE_NAME --zone $GCP_ZONE"
    echo ""
    echo "  2. 执行配置:"
    echo "     sudo bash ~/builder-setup.sh"
    echo ""
    echo "  3. 配置完成后关机:"
    echo "     sudo poweroff"
    echo ""
    echo "  4. 创建镜像:"
    echo "     bash scripts/build-image.sh create-image"
    echo ""
    ;;

  create-image)
    echo "[image] creating image from builder: $BUILDER_INSTANCE_NAME"
    # 解析构建机的启动磁盘名称
    BOOT_DISK_URI=$(gcloud "${PROJECT_FLAGS[@]}" compute instances describe "$BUILDER_INSTANCE_NAME" --zone "$GCP_ZONE" --format='get(disks[0].source)')
    if [[ -z "${BOOT_DISK_URI}" ]]; then
      echo "[image] cannot resolve builder boot disk. Ensure builder exists." >&2
      exit 1
    fi
    BOOT_DISK_NAME=${BOOT_DISK_URI##*/}
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    IMAGE_NAME="${IMAGE_FAMILY}-${TIMESTAMP}"

    gcloud "${PROJECT_FLAGS[@]}" compute images create "$IMAGE_NAME" \
      --source-disk="$BOOT_DISK_NAME" \
      --source-disk-zone="$GCP_ZONE" \
      --family="$IMAGE_FAMILY"
    echo "[image] image created: $IMAGE_NAME (family=$IMAGE_FAMILY)"
    ;;

  delete-builder)
    echo "[image] deleting builder: $BUILDER_INSTANCE_NAME"
    gcloud "${PROJECT_FLAGS[@]}" compute instances delete "$BUILDER_INSTANCE_NAME" --zone "$GCP_ZONE" --quiet || true
    ;;

  *)
    usage
    exit 1
    ;;
esac

echo "[image] done"

