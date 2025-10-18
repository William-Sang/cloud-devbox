#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
用法: $(basename "$0") <create-builder|create-image|delete-builder>

  create-builder  创建临时构建机并自动执行配置脚本
                  配置脚本: scripts/builder-setup.sh
                  自动安装: Docker, Node.js, Python 等
                  
  create-image    从构建机系统盘创建镜像并加入镜像族
  
  delete-builder  删除构建机实例

提示:
  • 编辑 scripts/builder-setup.sh 自定义安装内容
  • 配置完成后需关机: sudo poweroff (在 builder 实例中)
  • 然后创建镜像: bash scripts/build-image.sh create-image
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
    
    # 检查是否存在自定义的 builder 配置脚本
    BUILDER_SETUP_SCRIPT="$ROOT_DIR/scripts/builder-setup.sh"
    if [[ -f "$BUILDER_SETUP_SCRIPT" ]]; then
      echo "[image] 使用自动化配置脚本: builder-setup.sh"
      gcloud "${PROJECT_FLAGS[@]}" compute instances create "$BUILDER_INSTANCE_NAME" \
        --zone "$GCP_ZONE" \
        --machine-type "$BUILDER_MACHINE_TYPE" \
        --image-family "$BASE_IMAGE_FAMILY" --image-project "$BASE_IMAGE_PROJECT" \
        --metadata-from-file startup-script="$BUILDER_SETUP_SCRIPT"
      echo "[image] ✓ Builder 已创建，正在自动执行配置脚本..."
      echo "[image] 配置过程需要 3-5 分钟，可以使用以下命令查看进度："
      echo "[image]   gcloud compute instances get-serial-port-output $BUILDER_INSTANCE_NAME --zone $GCP_ZONE"
      echo "[image] 或 SSH 进入查看: gcloud compute ssh $BUILDER_INSTANCE_NAME --zone $GCP_ZONE"
    else
      echo "[image] 未找到 builder-setup.sh，使用默认配置"
      gcloud "${PROJECT_FLAGS[@]}" compute instances create "$BUILDER_INSTANCE_NAME" \
        --zone "$GCP_ZONE" \
        --machine-type "$BUILDER_MACHINE_TYPE" \
        --image-family "$BASE_IMAGE_FAMILY" --image-project "$BASE_IMAGE_PROJECT"
      echo "[image] builder created. SSH 进入后手动安装 Node/Python/Docker 等，完成后关机。"
    fi
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

