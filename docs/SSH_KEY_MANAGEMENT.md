# SSH 密钥管理方案

## 📋 目录

- [问题背景](#问题背景)
- [当前方案及问题](#当前方案及问题)
- [解决方案对比](#解决方案对比)
- [推荐方案详解](#推荐方案详解)
- [实施指南](#实施指南)
- [安全最佳实践](#安全最佳实践)

---

## 问题背景

### 开发环境的需求

在 GCE Builder 开发环境中，SSH 密钥主要用于：

1. **Git 操作**：克隆私有仓库、推送代码到 GitHub/GitLab
2. **服务器访问**：SSH 连接到其他服务器
3. **Docker 构建**：在 Dockerfile 中访问私有依赖
4. **自动化脚本**：CI/CD 流程中的自动化操作

### 核心矛盾

**便利性需求：**
- ✅ 每次创建新实例，密钥自动配置好
- ✅ 不需要每次都去 GitHub 添加新公钥
- ✅ 多个实例可以共享同一个密钥

**安全性需求：**
- ❌ 私钥不应该存储在镜像中（镜像可能被分享）
- ❌ 所有实例不应该使用完全相同的密钥（降低攻击面）
- ❌ 密钥泄露时应该能够快速撤销

---

## 当前方案及问题

### 当前实现（builder-setup.sh）

```bash
# 在镜像构建时生成 SSH 密钥
ssh-keygen -t ed25519 -C "gcp-dev-machine" -f ~/.ssh/id_ed25519 -N ""
```

### 问题分析

#### ⚠️ 问题 1：密钥被打包进镜像

```bash
# 流程
1. 创建 builder 实例 → 运行 builder-setup.sh → 生成 SSH 密钥
2. 关机 → 从磁盘创建镜像 → 密钥被打包进去
3. 从镜像创建实例 A → 包含密钥
4. 从镜像创建实例 B → 包含相同的密钥

# 结果
所有实例 A、B、C... 都有相同的私钥！
```

**安全风险：**
- 🔴 任何一个实例被攻破，攻击者可以访问所有实例
- 🔴 镜像分享给他人时，私钥也被分享了
- 🔴 无法追踪是哪个实例在使用密钥

#### ⚠️ 问题 2：密钥管理困难

- 如果需要更换密钥，所有实例都需要重新创建
- 无法针对不同用途使用不同密钥
- 难以实现密钥轮换策略

#### ✅ 当前方案的优点

- 极其便利：创建实例即可使用
- 无需额外配置
- 适合快速原型开发

---

## 解决方案对比

### 方案概览

| 方案 | 安全性 | 便利性 | 成本 | 复杂度 | 适用场景 |
|------|--------|--------|------|--------|----------|
| **方案 1：SSH Agent 转发** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | 免费 | 低 | 个人开发、临时调试 |
| **方案 2：Secret Manager** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | 低 | 中 | **团队开发（推荐）** |
| **方案 3：GitHub Token** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | 免费 | 低 | 现代化团队 |
| **方案 4：Deploy Key** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | 免费 | 中 | 多仓库场景 |
| **方案 5：首次启动生成** | ⭐⭐⭐⭐ | ⭐⭐ | 免费 | 低 | 高安全性要求 |
| **方案 6：共享密钥+保护** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | 免费 | 低 | 快速原型、学习 |

---

## 推荐方案详解

### 🏆 方案 1：SSH Agent 转发（个人开发首选）

#### 原理

使用本地电脑的 SSH 密钥，通过 SSH Agent 转发到远程实例，远程实例不存储任何私钥。

#### 优点

- ✅ **最安全**：私钥永远不离开本地电脑
- ✅ 所有实例共享本地密钥
- ✅ 实例销毁时无需清理
- ✅ 零成本

#### 缺点

- ❌ 需要保持 SSH 连接
- ❌ 不适合自动化脚本（需要人工介入）
- ❌ 在不可信环境中有风险

#### 实施步骤

**1. 本地配置 SSH Agent**

```bash
# 确保 ssh-agent 运行
eval "$(ssh-agent -s)"

# 添加密钥到 agent
ssh-add ~/.ssh/id_ed25519
```

**2. 配置 SSH 转发**

编辑本地 `~/.ssh/config`：

```bash
# 方式 1：直接配置
Host gce-builder
  HostName <instance-external-ip>
  User your_username
  ForwardAgent yes
  IdentityFile ~/.ssh/id_ed25519

# 方式 2：通配符配置所有 GCE 实例
Host *.compute.internal
  ForwardAgent yes
```

**3. 使用 gcloud 启用转发**

```bash
# 临时使用
gcloud compute ssh dev-builder --ssh-flag="-A"

# 或设置环境变量
export GCE_SSH_FLAGS="-A"
gcloud compute ssh dev-builder
```

**4. 验证转发是否工作**

```bash
# 在远程实例中
$ ssh-add -l
# 应该能看到本地的密钥

$ git clone git@github.com:your/private-repo.git
# 成功！使用的是本地密钥
```

#### 注意事项

⚠️ **安全警告**：
- 仅在可信环境中使用 Agent 转发
- 不要在共享服务器上使用
- 有权访问该服务器的其他用户可能劫持你的 agent socket

---

### 🏆 方案 2：GCP Secret Manager（团队开发首选）

#### 原理

将 SSH 密钥存储在 GCP Secret Manager 中，实例启动时动态获取并配置。

#### 优点

- ✅ 密钥不在镜像中
- ✅ 集中管理，方便轮换
- ✅ 所有实例使用同一密钥（便利）
- ✅ 支持版本控制和审计
- ✅ 可设置访问权限

#### 缺点

- 💰 有少量费用（每月约 $0.06 per secret）
- 🔧 需要配置 IAM 权限

#### 实施步骤

**1. 上传密钥到 Secret Manager**

```bash
# 上传私钥
gcloud secrets create dev-ssh-private-key \
  --data-file=~/.ssh/id_ed25519 \
  --replication-policy=automatic

# 上传公钥
gcloud secrets create dev-ssh-public-key \
  --data-file=~/.ssh/id_ed25519.pub \
  --replication-policy=automatic

# 验证
gcloud secrets list
```

**2. 配置 IAM 权限**

```bash
# 方式 1：使用默认服务账号
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud secrets add-iam-policy-binding dev-ssh-private-key \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding dev-ssh-public-key \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 方式 2：创建专用服务账号（更安全）
gcloud iam service-accounts create dev-instance-sa \
  --display-name="Dev Instance Service Account"

gcloud secrets add-iam-policy-binding dev-ssh-private-key \
  --member="serviceAccount:dev-instance-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**3. 修改 builder-setup.sh**

替换 SSH 密钥生成部分（SSH 密钥生成部分）：

```bash
# 生成 SSH 密钥 → 改为：从 Secret Manager 获取密钥
echo "从 Secret Manager 配置 SSH 密钥..."

# 检查是否可以访问 Secret Manager
if gcloud secrets versions access latest --secret=dev-ssh-private-key &>/dev/null; then
  
  # 为 root 配置
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  gcloud secrets versions access latest --secret=dev-ssh-private-key > /root/.ssh/id_ed25519
  gcloud secrets versions access latest --secret=dev-ssh-public-key > /root/.ssh/id_ed25519.pub
  chmod 600 /root/.ssh/id_ed25519
  chmod 644 /root/.ssh/id_ed25519.pub
  echo "✓ SSH 密钥配置完成 (root)"
  
  # 为默认用户配置
  DEFAULT_USER=$(ls /home | head -n 1)
  if [[ -n "$DEFAULT_USER" ]]; then
    sudo -u "$DEFAULT_USER" bash -c '
      mkdir -p ~/.ssh
      chmod 700 ~/.ssh
      gcloud secrets versions access latest --secret=dev-ssh-private-key > ~/.ssh/id_ed25519
      gcloud secrets versions access latest --secret=dev-ssh-public-key > ~/.ssh/id_ed25519.pub
      chmod 600 ~/.ssh/id_ed25519
      chmod 644 ~/.ssh/id_ed25519.pub
    '
    echo "✓ SSH 密钥配置完成 ($DEFAULT_USER)"
  fi
  
else
  echo "⚠️  警告：无法访问 Secret Manager，跳过 SSH 密钥配置"
  echo "   请确保实例有访问 Secret Manager 的权限"
  echo "   或使用 SSH Agent 转发"
fi
```

**4. 创建实例时指定正确的作用域/服务账号**

```bash
# 方式 1：使用默认服务账号 + cloud-platform 作用域
gcloud compute instances create my-dev-instance \
  --image-family=dev-gold \
  --scopes=cloud-platform

# 方式 2：使用专用服务账号（推荐）
gcloud compute instances create my-dev-instance \
  --image-family=dev-gold \
  --service-account=dev-instance-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --scopes=cloud-platform
```

**5. 在 GitHub 添加公钥**

```bash
# 查看公钥
gcloud secrets versions access latest --secret=dev-ssh-public-key

# 复制输出，添加到：
# GitHub → Settings → SSH and GPG keys → New SSH key
# 标题：GCE Dev Environments (Shared)
```

#### 密钥轮换

```bash
# 生成新密钥
ssh-keygen -t ed25519 -C "sang.williams@gmail.com" -f ~/.ssh/id_ed25519_new -N ""

# 更新 Secret Manager
gcloud secrets versions add dev-ssh-private-key --data-file=~/.ssh/id_ed25519_new
gcloud secrets versions add dev-ssh-public-key --data-file=~/.ssh/id_ed25519_new.pub

# 在 GitHub 添加新公钥

# 所有新创建的实例自动使用新密钥
# 旧实例重启后也会更新（如果配置了启动脚本）
```

---

### 🏆 方案 3：GitHub Token / Personal Access Token

#### 原理

不使用 SSH，改用 HTTPS + Token 认证。

#### 优点

- ✅ Token 可以设置精细权限
- ✅ 可以随时撤销
- ✅ 支持多个服务（GitHub, GitLab, Bitbucket）
- ✅ 更现代的认证方式

#### 实施步骤

**1. 创建 GitHub Fine-grained Token**

```
访问：https://github.com/settings/tokens?type=beta

1. 点击 "Generate new token" → "Fine-grained token"
2. Token name: GCE Dev Environments
3. Expiration: 90 days（建议定期轮换）
4. Repository access:
   - 选择需要访问的仓库
5. Permissions:
   - Contents: Read and write
   - Metadata: Read-only
6. 生成并复制 token（形如 github_pat_xxx）
```

**2. 存储到 Secret Manager**

```bash
echo -n "github_pat_xxx..." | gcloud secrets create github-token \
  --data-file=- \
  --replication-policy=automatic
```

**3. 在 builder-setup.sh 中配置**

```bash
# 配置 Git 使用 HTTPS + Token
echo "配置 GitHub Token 认证..."

if gcloud secrets versions access latest --secret=github-token &>/dev/null; then
  GITHUB_TOKEN=$(gcloud secrets versions access latest --secret=github-token)
  
  # 方式 1：使用 Git credential helper
  git config --global credential.helper store
  echo "https://sang.williams:${GITHUB_TOKEN}@github.com" > /root/.git-credentials
  chmod 600 /root/.git-credentials
  
  # 为默认用户配置
  if [[ -n "$DEFAULT_USER" ]]; then
    echo "https://sang.williams:${GITHUB_TOKEN}@github.com" > /home/$DEFAULT_USER/.git-credentials
    chown $DEFAULT_USER:$DEFAULT_USER /home/$DEFAULT_USER/.git-credentials
    chmod 600 /home/$DEFAULT_USER/.git-credentials
    sudo -u "$DEFAULT_USER" git config --global credential.helper store
  fi
  
  echo "✓ GitHub Token 配置完成"
else
  echo "⚠️  未找到 GitHub Token"
fi
```

**4. 使用方式**

```bash
# 使用 HTTPS URL 克隆
git clone https://github.com/your/private-repo.git

# 无需输入密码，自动使用 token！
```

---

### 🏆 方案 4：Deploy Key（多仓库场景）

#### 适用场景

- 需要访问特定的私有仓库
- 想要为不同仓库设置不同权限
- 只需要只读访问（拉取代码）

#### 实施步骤

**1. 生成 Deploy Key**

```bash
ssh-keygen -t ed25519 -C "dev-environments-readonly" -f ~/.ssh/deploy_key_repo1 -N ""
```

**2. 在 GitHub 仓库中添加**

```
仓库 → Settings → Deploy keys → Add deploy key

Title: GCE Dev Environments
Key: [粘贴 deploy_key_repo1.pub 内容]
☐ Allow write access（根据需要勾选）
```

**3. 上传到 Secret Manager**

```bash
gcloud secrets create deploy-key-repo1 --data-file=~/.ssh/deploy_key_repo1
```

**4. 配置 SSH config**

在 builder-setup.sh 中：

```bash
# 配置 SSH 使用特定密钥
cat >> /root/.ssh/config <<EOF
Host github.com-repo1
  HostName github.com
  User git
  IdentityFile ~/.ssh/deploy_key_repo1
  IdentitiesOnly yes
EOF

# 克隆时使用特殊 host
git clone git@github.com-repo1:user/repo1.git
```

---

### 方案 5：首次启动时生成密钥

#### 适用场景

- 高安全性要求
- 每个实例必须有唯一密钥
- 可以接受每次手动添加公钥到 GitHub

#### 实施步骤

**1. 在 builder-setup.sh 中移除密钥生成**

注释掉SSH 密钥生成部分的密钥生成代码。

**2. 创建首次启动服务**

```bash
# 在 builder-setup.sh 中添加
cat > /usr/local/bin/generate-ssh-keys.sh <<'SCRIPT'
#!/usr/bin/env bash
# 首次启动时生成唯一的 SSH 密钥

MARKER_FILE="/var/lib/ssh-keys-generated"

if [[ -f "$MARKER_FILE" ]]; then
  echo "SSH 密钥已存在，跳过生成"
  exit 0
fi

echo "生成 SSH 密钥..."

# 为 root 生成
if [[ ! -f /root/.ssh/id_ed25519 ]]; then
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  ssh-keygen -t ed25519 -C "sang.williams@gmail.com-$(hostname)" -f /root/.ssh/id_ed25519 -N ""
  echo "✓ Root SSH 密钥已生成"
  echo "公钥："
  cat /root/.ssh/id_ed25519.pub
fi

# 为普通用户生成
for user_home in /home/*; do
  if [[ -d "$user_home" ]]; then
    username=$(basename "$user_home")
    sudo -u "$username" bash -c "
      if [[ ! -f ~/.ssh/id_ed25519 ]]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keygen -t ed25519 -C '$username@$(hostname)' -f ~/.ssh/id_ed25519 -N ''
        echo '✓ $username SSH 密钥已生成'
        echo '公钥：'
        cat ~/.ssh/id_ed25519.pub
      fi
    "
  fi
done

touch "$MARKER_FILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "请将上述公钥添加到 GitHub/GitLab"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SCRIPT

chmod +x /usr/local/bin/generate-ssh-keys.sh

# 创建 systemd 服务
cat > /etc/systemd/system/generate-ssh-keys.service <<'SERVICE'
[Unit]
Description=Generate SSH keys on first boot
After=network.target
ConditionPathExists=!/var/lib/ssh-keys-generated

[Service]
Type=oneshot
ExecStart=/usr/local/bin/generate-ssh-keys.sh
RemainAfterExit=yes
StandardOutput=journal

[Install]
WantedBy=multi-user.target
SERVICE

systemctl enable generate-ssh-keys.service
```

**3. 使用方式**

```bash
# 创建实例
gcloud compute instances create my-dev --image-family=dev-gold

# SSH 登录
gcloud compute ssh my-dev

# 查看生成的公钥
cat ~/.ssh/id_ed25519.pub

# 复制并添加到 GitHub
```

---

### 方案 6：接受风险 + 加强防护（当前方案改进）

#### 适用场景

- 快速原型开发
- 个人学习环境
- 可接受一定安全风险

#### 改进措施

**1. 添加警告和标识**

```bash
# 在 builder-setup.sh 中
cat > /etc/image-security-notice <<EOF
⚠️  安全提示 ⚠️

此镜像包含预配置的 SSH 密钥，仅供开发环境使用。

风险：
- 所有从此镜像创建的实例共享相同的 SSH 密钥
- 不适用于生产环境
- 不应分享给不可信的人员

建议：
- 定期轮换密钥（每季度）
- 使用防火墙限制访问
- 仅在私有网络中使用
- 对于生产环境，请使用 Secret Manager 方案

密钥标识：
  公钥位置: ~/.ssh/id_ed25519.pub
  用途: 开发环境共享密钥
  GitHub 标题: "GCE Dev Environments (Shared)"
EOF

cat /etc/image-security-notice
```

**2. 网络防护**

```bash
# 创建防火墙规则限制访问
gcloud compute firewall-rules create dev-ssh-restricted \
  --allow=tcp:22 \
  --source-ranges=YOUR_IP/32 \
  --target-tags=dev-instance \
  --description="Restrict SSH to dev instances"

# 创建实例时打标签
gcloud compute instances create my-dev \
  --image-family=dev-gold \
  --tags=dev-instance \
  --labels=environment=dev,security-level=shared-key
```

**3. 定期审计**

```bash
# 列出所有使用共享密钥的实例
gcloud compute instances list \
  --filter="labels.security-level=shared-key" \
  --format="table(name,zone,status,creationTimestamp)"
```

---

## 实施指南

### 推荐实施路径

#### 阶段 1：立即实施（保持当前方案）

**目的**：快速开始开发，暂时接受风险

```bash
1. 保持 builder-setup.sh 当前的密钥生成代码
2. 添加安全警告和标识（方案 6）
3. 配置网络防火墙限制访问
4. 在 GitHub 中明确标注密钥用途
```

#### 阶段 2：过渡方案（1-2 周内）

**目的**：学习使用 SSH Agent 转发

```bash
1. 在本地配置 SSH Agent 转发
2. 日常开发使用 Agent 转发
3. 熟悉工作流程
```

#### 阶段 3：长期方案（1 个月内）

**目的**：实施 Secret Manager 方案

```bash
1. 设置 GCP Secret Manager
2. 上传开发密钥
3. 修改 builder-setup.sh
4. 测试新镜像
5. 迁移所有实例
```

### 具体步骤

#### 步骤 1：设置 Secret Manager（约 10 分钟）

```bash
# 1. 上传密钥
gcloud secrets create dev-ssh-private-key --data-file=~/.ssh/id_ed25519
gcloud secrets create dev-ssh-public-key --data-file=~/.ssh/id_ed25519.pub

# 2. 配置权限
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud secrets add-iam-policy-binding dev-ssh-private-key \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding dev-ssh-public-key \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 3. 验证
gcloud secrets list
```

#### 步骤 2：修改 builder-setup.sh（约 5 分钟）

参考方案 2 的代码，替换SSH 密钥生成部分。

#### 步骤 3：重建镜像（约 5-10 分钟）

```bash
# 1. 删除旧 builder
bash scripts/build-image.sh delete-builder

# 2. 创建新 builder
bash scripts/build-image.sh create-builder

# 3. 等待配置完成，然后关机
gcloud compute ssh dev-builder --command="sudo poweroff"

# 4. 创建新镜像
bash scripts/build-image.sh create-image
```

#### 步骤 4：测试（约 5 分钟）

```bash
# 1. 创建测试实例
gcloud compute instances create test-dev \
  --image-family=dev-gold \
  --scopes=cloud-platform

# 2. 验证密钥配置
gcloud compute ssh test-dev --command="ls -la ~/.ssh/id_ed25519"

# 3. 测试 Git 操作
gcloud compute ssh test-dev --command="git clone git@github.com:your/test-repo.git"

# 4. 清理
gcloud compute instances delete test-dev --quiet
```

---

## 安全最佳实践

### 1. 密钥管理原则

#### 最小权限原则
```bash
# ✅ 好：为不同用途创建不同密钥
~/.ssh/id_ed25519_readonly   # 只读部署密钥
~/.ssh/id_ed25519_dev        # 开发密钥
~/.ssh/id_ed25519_prod       # 生产密钥（永远不放在开发环境）

# ❌ 差：一个密钥用于所有场景
~/.ssh/id_ed25519            # 万能密钥
```

#### 定期轮换
```bash
# 建议周期
- 开发环境共享密钥：每季度
- 生产环境密钥：每月
- 疑似泄露：立即
```

#### 密钥保护
```bash
# 正确的权限
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519      # 私钥：仅所有者可读写
chmod 644 ~/.ssh/id_ed25519.pub  # 公钥：所有人可读

# 使用密码保护私钥（生产环境）
ssh-keygen -t ed25519 -C "prod-key" -f ~/.ssh/id_prod -N "strong-passphrase"
```

### 2. GitHub/GitLab 配置

#### 密钥命名规范
```
格式：<环境>-<用户>-<设备/用途>-<日期>

示例：
- dev-willliam-gce-shared-2024-10
- prod-deploy-bot-2024-10
- personal-macbook-pro-2024-10
```

#### 定期审计
```bash
# 定期检查 GitHub 的 SSH 密钥
# Settings → SSH and GPG keys

# 删除：
- 长期未使用的密钥（Last used: > 3 months ago）
- 不再使用的设备的密钥
- 已销毁实例的密钥
```

### 3. 监控和审计

#### 启用 GCP 审计日志
```bash
# 查看 Secret Manager 访问日志
gcloud logging read "resource.type=secretmanager.googleapis.com" \
  --limit 50 \
  --format json

# 查看实例创建日志
gcloud logging read "resource.type=gce_instance" \
  --limit 50
```

#### 设置告警
```bash
# 当有人访问 Secret 时发送通知
# GCP Console → Monitoring → Alerting → Create Policy
# 条件：Secret Manager Secret Version Access
```

### 4. 事故响应

#### 密钥泄露处理流程

```bash
# 1. 立即撤销（5 分钟内）
# GitHub → Settings → SSH keys → Delete

# 2. 轮换密钥（10 分钟内）
ssh-keygen -t ed25519 -C "new-key" -f ~/.ssh/id_new -N ""
gcloud secrets versions add dev-ssh-private-key --data-file=~/.ssh/id_new
gcloud secrets versions add dev-ssh-public-key --data-file=~/.ssh/id_new.pub

# 3. 更新 GitHub
# 添加新公钥

# 4. 重启所有实例（强制更新密钥）
gcloud compute instances list --format="value(name)" | xargs -I {} \
  gcloud compute instances reset {}

# 5. 审计影响范围
# 检查泄露期间的访问日志

# 6. 记录事故
# 更新安全文档
```

### 5. 合规性考虑

#### 企业环境检查清单

- [ ] 私钥永远不存储在代码仓库中
- [ ] 私钥永远不出现在日志中
- [ ] 使用密钥管理服务（如 Secret Manager）
- [ ] 启用审计日志
- [ ] 定期轮换密钥
- [ ] 有密钥泄露应急预案
- [ ] 实施最小权限原则
- [ ] 定期安全审计

---

## 附录

### A. 常用命令速查

#### Secret Manager
```bash
# 创建 secret
gcloud secrets create SECRET_NAME --data-file=FILE

# 更新 secret
gcloud secrets versions add SECRET_NAME --data-file=FILE

# 读取 secret
gcloud secrets versions access latest --secret=SECRET_NAME

# 列出所有 secrets
gcloud secrets list

# 删除 secret
gcloud secrets delete SECRET_NAME
```

#### SSH Agent
```bash
# 启动 agent
eval "$(ssh-agent -s)"

# 添加密钥
ssh-add ~/.ssh/id_ed25519

# 列出已加载的密钥
ssh-add -l

# 删除所有密钥
ssh-add -D

# 测试 agent 转发
ssh -A user@host "ssh-add -l"
```

#### Git 凭证
```bash
# 配置 credential helper
git config --global credential.helper store

# 查看存储的凭证
cat ~/.git-credentials

# 清除凭证
git credential-cache exit
rm ~/.git-credentials
```

### B. 故障排查

#### 问题：无法访问 Secret Manager

**症状：**
```
ERROR: (gcloud.secrets.versions.access) Permission denied
```

**解决：**
```bash
# 1. 检查实例的服务账号
gcloud compute instances describe INSTANCE_NAME \
  --format="value(serviceAccounts[0].email)"

# 2. 检查服务账号权限
gcloud secrets get-iam-policy SECRET_NAME

# 3. 添加权限
gcloud secrets add-iam-policy-binding SECRET_NAME \
  --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
  --role="roles/secretmanager.secretAccessor"

# 4. 确保实例有正确的作用域
# 重新创建实例时添加 --scopes=cloud-platform
```

#### 问题：SSH Agent 转发不工作

**症状：**
```bash
$ ssh-add -l
Could not open a connection to your authentication agent.
```

**解决：**
```bash
# 1. 确保本地 agent 运行
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 2. 确保启用了转发
ssh -A user@host

# 3. 检查 SSH 配置
cat ~/.ssh/config | grep ForwardAgent

# 4. 在远程检查
echo $SSH_AUTH_SOCK  # 应该有值
```

#### 问题：Git 克隆失败

**症状：**
```
git@github.com: Permission denied (publickey).
```

**解决：**
```bash
# 1. 检查密钥是否存在
ls -la ~/.ssh/id_ed25519

# 2. 检查密钥权限
chmod 600 ~/.ssh/id_ed25519

# 3. 测试 SSH 连接
ssh -T git@github.com

# 4. 查看详细调试信息
GIT_SSH_COMMAND="ssh -v" git clone git@github.com:user/repo.git

# 5. 验证公钥是否添加到 GitHub
curl https://github.com/USERNAME.keys
```

### C. 成本估算

#### Secret Manager 费用
```
定价（2024）：
- Active secret versions: $0.06 per secret per month
- Access operations: $0.03 per 10,000 operations

示例（2 个 secrets）：
- 存储费用: 2 × $0.06 = $0.12/月
- 访问费用: 100 instances × 1 access/day × 30 days = 3,000 次 = $0.009/月
- 总计: 约 $0.13/月

结论：成本极低，几乎可忽略
```

### D. 参考资源

- [GitHub: Connecting to GitHub with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
- [GCP: Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [SSH Agent Forwarding](https://www.ssh.com/academy/ssh/agent)
- [Git Credential Storage](https://git-scm.com/book/en/v2/Git-Tools-Credential-Storage)

---

## 更新日志

- **2024-10-18**: 初始版本，包含 6 种方案对比和详细实施指南

---

## 反馈和改进

如有问题或建议，请联系：sang.williams@gmail.com

或提交 Issue 到项目仓库。

