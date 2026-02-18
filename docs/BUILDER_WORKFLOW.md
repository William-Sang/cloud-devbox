# Builder 工作流程说明

## 📋 变更说明

`build-image.sh` 不自动执行配置脚本，而是通过 **metadata** 将脚本传入实例，由用户手动执行。

### 技术实现

- ✅ 使用 `--metadata-from-file` 在创建实例时传入脚本
- ✅ 脚本通过 metadata API 自动保存到 `~/builder-setup.sh`
- ✅ 无需等待 SSH 就绪，无需手动 scp 复制
- ✅ 实例启动后脚本即可用

### 为什么这样设计？

**优点：**
- ✅ **方便调试**：可以实时查看脚本输出
- ✅ **灵活性高**：可以在执行前修改脚本
- ✅ **分步执行**：遇到问题可以逐行排查
- ✅ **更可控**：用户明确知道何时执行脚本
- ✅ **更快速**：无需等待 SSH 和复制文件

---

## 🔧 工作原理

### Metadata 传入机制

创建实例时，`build-image.sh` 做了以下操作：

```bash
# 1. 创建一个临时的初始化脚本
#    该脚本会在实例启动时运行

# 2. 使用 metadata-from-file 同时传入两个文件
gcloud compute instances create dev-builder \
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

```
1. 系统启动
2. startup-script 自动运行
3. 从 metadata 获取 builder-setup.sh 内容
4. 保存到 ~/builder-setup.sh
5. ✅ 脚本就绪，可以登录执行
```

你可以通过串行端口输出查看这个过程：

```bash
gcloud compute instances get-serial-port-output dev-builder | grep "Builder 脚本"
# 输出: ✅ Builder 脚本已准备就绪
```

---

## 🚀 快速开始

### 方式 A：一键执行（推荐）

```bash
# 1. 创建 builder 实例
bash scripts/build-image.sh create-builder

# 2. SSH 登录并执行配置（等待 30 秒让实例启动）
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

# 2. SSH 登录
gcloud compute ssh dev-builder --zone=asia-northeast1-a

# 3. 查看脚本内容（可选）
cat ~/builder-setup.sh

# 4. 执行配置脚本
sudo bash ~/builder-setup.sh
# 实时查看输出：
# [1/5] 创建用户并配置权限...
# [2/5] 运行 bootstrap 安装工具...
# [3/5] 配置 Git/Vim...
# [4/5] 配置 SSH 密钥与工作目录...
# [5/5] 清理缓存...

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

# 6. 完成后关机并创建镜像
exit
gcloud compute instances stop dev-builder --zone=asia-northeast1-a
bash scripts/build-image.sh create-image
```

---

## 📊 执行时间估算

`builder-setup.sh` 内部调用 `bootstrap/init-devbox.sh apply --all` 安装所有模块：

```
[1/5] 创建用户并配置权限        ~10 秒
[2/5] 运行 bootstrap            ~5-10 分钟
      - mirror (镜像源配置)      ~10 秒
      - base (系统工具)          ~30 秒
      - docker (Docker Engine)   ~60 秒
      - node (fnm + Node LTS)   ~30 秒
      - python (uv + Python)    ~30 秒
      - ai-tools (AI 编码工具)  ~60 秒
      - shell-config (Shell)    ~10 秒
[3/5] 配置 Git/Vim              ~30 秒
[4/5] SSH 密钥与工作目录         ~10 秒
[5/5] 清理缓存                  ~30 秒

总计：约 5-10 分钟
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

[1/5] 创建用户并配置权限...
✓ 用户 dev 创建完成

[2/5] 运行 bootstrap 安装工具...
(bootstrap 模块逐个执行，实时显示进度)
...
```

### 验证安装

```bash
# 在 builder 实例中验证
docker --version
fnm --version
node --version
uv --version
python --version
ls -la ~/.ssh/id_ed25519
```

---

## 🛠️ 自定义配置

### 编辑 bootstrap 配置

在创建 builder 前，可以编辑 `bootstrap/config.default.toml` 自定义安装内容，
或创建 `bootstrap/config.toml` 覆盖默认配置。

### 在实例中临时调整

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

# 或使用调试模式
sudo bash -x ~/builder-setup.sh

# 修复后继续执行
```

### 问题 2：fnm/uv 下载超时

**症状：** 下载很慢或超时

**解决：**
```bash
# 如果在中国网络环境，使用 --region cn 运行 bootstrap：
sudo bash -c 'cd /tmp/cloud-devbox && bash bootstrap/init-devbox.sh apply --all --yes --region cn'
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

---

## 📝 最佳实践

### 1. 版本控制

```bash
# 在 builder-setup.sh 中记录版本
cat > /etc/builder-version <<EOF
BUILD_DATE=$(date -Iseconds)
DOCKER_VERSION=$(docker --version)
NODE_VERSION=$(node --version)
PYTHON_VERSION=$(python --version)
EOF
```

### 2. 清理临时文件

```bash
# 在创建镜像前清理（builder-setup.sh 已自动执行）
sudo apt-get clean
sudo rm -rf /tmp/*
history -c
```

### 3. 测试镜像

```bash
# 从新镜像创建测试实例
gcloud compute instances create test-instance \
  --image-family=dev-gold \
  --zone=asia-northeast1-a

# 验证所有工具
gcloud compute ssh test-instance --command='
  docker --version &&
  fnm --version &&
  node --version &&
  uv --version &&
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

最后更新：2026-02-18
