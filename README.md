<div align="center">

# cloud-devbox

用 Google Cloud 一键启动/销毁的云端开发机模板。支持固定 IP、Spot 节省成本、自定义镜像、永久磁盘挂载到 `/workspace`，适配 Cursor / VSCode Remote。

</div>

---

## ✨ 功能特性

- 固定公网 IP，远程连接稳定
- Spot 抢占式实例，低成本（典型 ~$0.05/小时）
- 自定义镜像，环境一致，30s 级启动
- 永久数据盘，代码与配置保留在 `/workspace`
- 脚本化一键启动、自动定时删除，避免遗留账单

## TODO
1. 输出脚本运行时长
2. 解决默认 /workspace 没有权限的问题

---

## 📦 目录结构

```
.
├── scripts/
│   ├── setup-network.sh      # 申请静态 IP、创建防火墙
│   ├── start-dev.sh          # 启动 Spot 开发机并挂载数据盘
│   ├── destroy-dev.sh        # 销毁临时实例
│   └── build-image.sh        # 构建/更新自定义镜像（可选）
├── ssh/
│   └── config.example        # SSH 配置模板
├── .env.example              # 环境变量模板
└── README.md
```

---

## ✅ 前置条件

- 已开启 GCP 计费并创建项目
- 已安装并初始化 `gcloud`（登录并选择项目）
- 账号具备 `Compute Admin` 权限或等价权限

---

## 📥 安装依赖

### 安装 Google Cloud SDK (gcloud)

**Linux / WSL:**

```bash
# 下载并安装
curl https://sdk.cloud.google.com | bash

# 重启 shell 或执行
exec -l $SHELL

# 初始化并登录
gcloud auth login

```

**macOS:**

```bash
# 使用 Homebrew
brew install --cask google-cloud-sdk

# 初始化并登录
gcloud init
```

---

## ⚡ 快速开始

1. 克隆并配置环境变量

```bash
git clone https://github.com/yourname/cloud-devbox.git
cd cloud-devbox
cp env.example .env
# 编辑 .env，至少填写：GCP_PROJECT_ID、GCP_REGION、GCP_ZONE
```

2. 一次性初始化网络（静态 IP 与 SSH 防火墙）

```bash
bash scripts/setup-network.sh
```

3.（可选）制作自定义镜像（更快启动，更一致环境）

```bash
# 第一步：创建临时构建机（SSH 进去手动安装 Node/Python/Docker 等，完成后关机）
bash scripts/build-image.sh create-builder

# 第二步：从构建机磁盘产出镜像并加入镜像族
bash scripts/build-image.sh create-image
```

4. 启动临时开发机（Spot）

```bash
bash scripts/start-dev.sh
```

5. 配置并连接 Cursor / VSCode Remote SSH（参考 `ssh/config.example`）

```bash
# ~/.ssh/config 追加：
Host gcp-dev
  HostName <上一步输出的外网 IP>
  User <你的用户名>
  IdentityFile ~/.ssh/gcp_dev
  ServerAliveInterval 60

# 连接
ssh gcp-dev
```

6. 用完销毁（避免账单）

```bash
bash scripts/destroy-dev.sh
```

---

## 🔧 配置项（.env）

关键变量（均已在 `.env.example` 中提供默认值或示例）：

- `GCP_PROJECT_ID`：GCP 项目 ID
- `GCP_REGION` / `GCP_ZONE`：区域与可用区
- `ADDRESS_NAME`：静态 IP 名称
- `DISK_NAME` / `DISK_SIZE_GB` / `DISK_TYPE`：永久盘配置
- **镜像配置（智能选择）**：
  - `IMAGE_FAMILY` / `IMAGE_PROJECT`：自定义镜像（可选）
  - `DEFAULT_IMAGE_FAMILY` / `DEFAULT_IMAGE_PROJECT`：默认镜像（回退）
  - 脚本会自动检测自定义镜像是否存在，不存在则使用默认镜像
- `SPOT_MACHINE_TYPE` / `MAX_RUN_DURATION` / `TERMINATION_ACTION`：Spot 实例与自动删除策略
- `MOUNT_POINT` / `MOUNT_DEVICE`：数据盘挂载点与设备名
- `NETWORK_TAGS` / `SOURCE_RANGES_SSH`：网络标签与 SSH 来源网段
- `LABEL_KEY`/`LABEL_VALUE`：用于标记并批量销毁临时实例

---

## 🧪 脚本说明

- `scripts/setup-network.sh`：创建静态 IP 与 `allow-ssh` 防火墙（幂等）
- `scripts/start-dev.sh`：
  - 确保永久盘存在（不存在则创建）
  - **智能镜像选择**：自动检测自定义镜像，不存在则回退到默认镜像
  - 启动 Spot 实例，自动格式化并挂载数据盘到 `${MOUNT_POINT}`，设置自动删除
  - 首次使用会自动格式化新磁盘为 ext4 文件系统
  - 输出外网 IP 与 SSH 配置指引
- `scripts/destroy-dev.sh`：删除带有指定标签的运行中实例（默认 `devbox=yes`）
- `scripts/build-image.sh`（可选）：
  - `create-builder`：创建构建机供你安装依赖
  - `create-image`：从构建机磁盘创建镜像（并加入镜像族），随后可删除构建机

---

## 🔐 安全建议

- 将 `SOURCE_RANGES_SSH` 设置为你当前公网 IP 段，避免 0.0.0.0/0 暴露
- 推荐使用 IAP 隧道或 VPN 进一步收敛暴露面
- 定期 rotate SSH key，限制 `Network Tags` 的使用范围

---

## ❓ 常见问题

### 环境依赖问题

- **`gcloud: command not found`**：
  - 需要先安装 Google Cloud SDK，请参考上面的"📥 安装依赖"章节
  - 安装后记得执行 `gcloud init` 和 `gcloud auth login`

### 实例启动问题

- **镜像选择机制**：
  - ✅ 脚本支持智能镜像选择，无需手动修改配置
  - 如果配置了自定义镜像，脚本会先检测是否存在
  - 如果自定义镜像不存在或未配置，自动使用默认镜像（Debian 12）
  - 可以通过 `DEFAULT_IMAGE_FAMILY` 和 `DEFAULT_IMAGE_PROJECT` 自定义默认镜像

- **启动失败且提示镜像不存在**：
  - 这个问题现在会自动解决，脚本会回退到默认镜像
  - 如果仍然失败，检查 `DEFAULT_IMAGE_FAMILY` 和 `DEFAULT_IMAGE_PROJECT` 配置

- **metadata 参数错误**：
  - 已修复：现在使用 `--metadata-from-file` 代替直接传递启动脚本，避免特殊字符解析问题

### 磁盘问题

- **磁盘未挂载**：
  - 检查 `.env` 中 `MOUNT_DEVICE` 是否与实际一致（GCE 通常为 `/dev/sdb`）
  - 新磁盘会自动格式化为 ext4，无需手动操作

### 网络问题

- **防火墙未生效**：
  - 确认实例 `--tags` 与规则 `--target-tags` 一致
  - 检查是否先运行了 `setup-network.sh`

---

## 许可证

MIT
