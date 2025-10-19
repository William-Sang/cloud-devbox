# Builder 工作流程说明

## 📋 变更说明

从当前版本开始，`build-image.sh` 不再自动执行配置脚本，而是通过 **metadata** 将脚本传入实例，由用户手动执行。

### 技术实现

- ✅ 使用 `--metadata-from-file` 在创建实例时传入脚本
- ✅ 脚本通过 metadata API 自动保存到 `~/builder-setup.sh`
- ✅ 无需等待 SSH 就绪，无需手动 scp 复制
- ✅ 实例启动后脚本即可用

### 为什么这样改？

**优点：**
- ✅ **方便调试**：可以实时查看脚本输出
- ✅ **灵活性高**：可以在执行前修改脚本
- ✅ **分步执行**：遇到问题可以逐行排查
- ✅ **更可控**：用户明确知道何时执行脚本
- ✅ **更快速**：无需等待 SSH 和复制文件

**之前的问题：**
- ❌ 脚本在后台自动执行，无法实时查看进度
- ❌ 出错时不知道哪一步失败
- ❌ 需要查看串行端口输出才能调试

---

## 🔧 工作原理

### Metadata 传入机制

创建实例时，`build-image.sh` 做了以下操作：

```bash
# 1. 创建一个临时的初始化脚本
#    该脚本会在实例启动时运行

# 2. 使用 metadata-from-file 同时传入两个文件
gcloud compute instances create builder-instance \
  --metadata-from-file \
    startup-script=/tmp/init-script.sh,\        # 初始化脚本
    builder-script=scripts/builder-setup.sh     # 配置脚本内容

# 3. 初始化脚本在实例启动时执行，做以下事情：
#    - 从 metadata API 读取 builder-script
#    - 保存到 /root/builder-setup.sh
#    - 复制到普通用户的主目录
#    - 设置可执行权限
```

### 脚本准备过程

实例启动后的前 10-20 秒内，会自动执行以下步骤：

```bash
1. 系统启动
2. startup-script 自动运行
3. 从 metadata 获取 builder-setup.sh 内容
4. 保存到 ~/builder-setup.sh
5. ✅ 脚本就绪，可以登录执行
```

你可以通过串行端口输出查看这个过程：

```bash
gcloud compute instances get-serial-port-output builder-instance | grep "Builder 脚本"
# 输出: ✅ Builder 脚本已准备就绪
```

---

## 🚀 快速开始

### 方式 A：一键执行（推荐）

```bash
# 1. 创建 builder 实例
bash scripts/build-image.sh create-builder

# 2. SSH 登录并执行配置
gcloud compute ssh dev-builder --zone=asia-northeast1-a --command="sudo bash ~/builder-setup.sh"

# 3. 配置完成后关机
gcloud compute instances stop dev-builder --zone=asia-northeast1-a

# 4. 创建镜像
bash scripts/build-image.sh create-image
```

### 方式 B：手动执行（完全控制）

```bash
# 1. 创建 builder 实例
bash scripts/build-image.sh create-builder
# 输出类似：
# ✓ 脚本已复制到实例: ~/builder-setup.sh
# 
# 下一步：
#   1. SSH 登录到实例：
#      gcloud compute ssh dev-builder --zone asia-northeast1-a
#   2. 执行配置脚本（需要 root 权限）：
#      sudo bash ~/builder-setup.sh

# 2. SSH 登录
gcloud compute ssh dev-builder --zone=asia-northeast1-a

# 3. 查看脚本内容（可选）
cat ~/builder-setup.sh

# 4. 执行配置脚本
sudo bash ~/builder-setup.sh
# 实时查看输出：
# [1/6] 更新系统包...
# [2/6] 安装基础工具...
# [3/6] 安装 Docker...
# ...

# 5. 配置完成后，退出并关机
exit
gcloud compute instances stop dev-builder --zone=asia-northeast1-a

# 6. 创建镜像
bash scripts/build-image.sh create-image
```

### 方式 C：调试模式（分步执行）

```bash
# 1. 创建实例
bash scripts/build-image.sh create-builder

# 2. SSH 登录
gcloud compute ssh dev-builder

# 3. 查看脚本内容
less ~/builder-setup.sh

# 4. 可以修改脚本（如果需要）
vim ~/builder-setup.sh

# 5. 分步执行（方便调试）
sudo bash -x ~/builder-setup.sh  # -x 显示每条命令

# 或者逐部分执行
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli
# ...

# 6. 完成后关机并创建镜像
exit
gcloud compute instances stop dev-builder --zone=asia-northeast1-a
bash scripts/build-image.sh create-image
```

---

## 📊 执行时间估算

```
[1/6] 更新系统包...                ~30 秒
[2/6] 安装基础工具...               ~30 秒
[3/6] 安装 Docker...               ~60 秒
[4/6] 安装 mise...                 ~20 秒
[5/6] 安装 Node.js/Python...      ~120 秒（下载和编译）
[6/6] 配置环境...                  ~60 秒
      - Vim (amix/vimrc)
      - Git 配置
      - SSH 密钥生成

总计：约 5-8 分钟
首次可能需要 10-15 分钟（取决于网络）
```

---

## 🔍 检查配置状态

### 实时查看输出

执行 `sudo bash ~/builder-setup.sh` 后，你会看到：

```bash
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 开始配置 Builder 实例
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1/6] 更新系统包...
✓ 系统更新完成

[2/6] 安装基础工具...
✓ 基础工具安装完成
...
```

### 配置完成标志

看到以下输出说明配置成功：

```bash
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Builder 配置完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

已安装：
  • mise:    2024.x.x
  • Docker:  Docker version 24.x.x
  • Node.js: v20.x.x
  • npm:     10.x.x
  • Python:  Python 3.12.x
  • Git:     git version 2.x.x
  • Vim:     amix/vimrc (已配置)

Git 配置：
  • 用户名: willliam.sang
  • 邮箱:   sang.williams@gmail.com

SSH 密钥已生成：
  Root 用户公钥:
  ssh-ed25519 AAAA... gcp-dev-machine
```

### 验证安装

```bash
# 在 builder 实例中验证
docker --version
mise --version
node --version
python --version
ls -la ~/.ssh/id_ed25519
```

---

## 🛠️ 自定义配置

### 编辑配置脚本

在创建 builder 前，编辑 `scripts/builder-setup.sh`：

```bash
# 找到自定义安装内容部分（第 217 行后）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 📝 自定义安装内容
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 示例：安装 Go
echo "安装 Go..."
mise use -g go@1.21

# 示例：安装 Rust
echo "安装 Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# 示例：安装 Python 包
echo "安装 Python 包..."
pip install requests pandas numpy flask django

# 示例：克隆常用仓库
echo "克隆仓库..."
cd /workspace
git clone https://github.com/your/project.git
```

### 实例中临时调整

如果需要在实例中调整：

```bash
# SSH 登录
gcloud compute ssh dev-builder

# 编辑脚本
sudo vim ~/builder-setup.sh

# 执行修改后的脚本
sudo bash ~/builder-setup.sh
```

---

## 🐛 故障排查

### 问题 1：脚本执行失败

**症状：** 某个步骤出错，脚本中断

**解决：**
```bash
# 查看错误信息
sudo bash ~/builder-setup.sh 2>&1 | tee setup.log

# 逐步执行失败的部分
# 例如，如果 Docker 安装失败：
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli

# 修复后继续执行剩余部分
```

### 问题 2：mise 安装 Node.js/Python 超时

**症状：** mise 下载很慢或超时

**解决：**
```bash
# 使用国内镜像（如果在中国）
export MISE_NODE_MIRROR_URL=https://npmmirror.com/mirrors/node
export MISE_PYTHON_BUILD_MIRROR_URL=https://registry.npmmirror.com/binary.html?path=python/

# 重新执行 mise 安装
mise use -g node@lts
mise use -g python@3.12
```

### 问题 3：SSH 连接超时

**症状：** `gcloud compute ssh` 连接不上

**解决：**
```bash
# 1. 检查实例状态
gcloud compute instances describe dev-builder \
  --zone=asia-northeast1-a \
  --format="get(status)"

# 2. 等待实例完全启动（创建后需要 30-60 秒）
sleep 30

# 3. 重试连接
gcloud compute ssh dev-builder --zone=asia-northeast1-a
```

### 问题 4：权限错误

**症状：** `Permission denied` 错误

**解决：**
```bash
# 确保使用 sudo 执行脚本
sudo bash ~/builder-setup.sh

# 检查脚本权限
ls -la ~/builder-setup.sh
chmod +x ~/builder-setup.sh
```

---

## 📝 最佳实践

### 1. 版本控制

```bash
# 在 builder-setup.sh 中记录版本
cat > /etc/builder-version <<EOF
BUILD_DATE=$(date -Iseconds)
SCRIPT_VERSION=1.0
DOCKER_VERSION=$(docker --version)
NODE_VERSION=$(node --version)
PYTHON_VERSION=$(python --version)
EOF
```

### 2. 添加完成标记

```bash
# 在脚本末尾添加
touch /var/lib/builder-setup-complete
echo "$(date -Iseconds)" > /var/lib/builder-setup-timestamp
```

### 3. 清理临时文件

```bash
# 在创建镜像前清理
sudo apt-get clean
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
history -c
```

### 4. 测试镜像

```bash
# 从新镜像创建测试实例
gcloud compute instances create test-instance \
  --image-family=dev-gold \
  --zone=asia-northeast1-a

# 验证所有工具
gcloud compute ssh test-instance --command='
  docker --version &&
  mise --version &&
  node --version &&
  python --version &&
  echo "✅ 镜像测试通过"
'

# 清理测试实例
gcloud compute instances delete test-instance --zone=asia-northeast1-a --quiet
```

---

## 🔗 相关文档

- [BUILDER_GUIDE.md](BUILDER_GUIDE.md) - Builder 详细指南
- [SSH_KEY_MANAGEMENT.md](SSH_KEY_MANAGEMENT.md) - SSH 密钥管理方案
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - 快速参考手册

---

## 📊 对比：旧版 vs 新版

| 特性 | 旧版（自动执行） | 新版（手动执行） |
|------|-----------------|-----------------|
| **执行方式** | 启动脚本自动执行 | 用户手动执行 |
| **输出可见性** | 需查看串行端口 | 实时显示 ✅ |
| **调试难度** | 较难 | 容易 ✅ |
| **灵活性** | 低 | 高 ✅ |
| **便利性** | 高 ✅ | 中等 |
| **出错处理** | 需要重新创建实例 | 可以立即修复 ✅ |
| **学习曲线** | 低 | 中等 |

**推荐：** 对于生产环境，新版更适合；如需更好的调试体验，可以使用方式 B 手动执行配置。

---

最后更新：2024-10-18


