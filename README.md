# proxy-helper

mihomo (Clash Meta) 代理快捷命令集 + CLI 工具包。

适合 Docker / 开发容器 / Linux 服务器环境使用。

## 包含内容

### 代理快捷命令（shell 函数）

| 命令 | 功能 |
|------|------|
| `proxy-on [地区\|URL]` | 开启代理：启动 mihomo + 设置环境变量 + 可选订阅更新/切节点 |
| `proxy-off` | 关闭代理：清除环境变量 |
| `proxy-status` | 查看代理状态：环境变量 + mihomo 运行状态 + 当前节点 |
| `proxy-update [--url]` | 更新代理：默认仅切节点，`--url` 时先更新订阅再切节点 |
| `proxy-test [地区]` | 测试节点延迟：默认新加坡，可指定香港/日本/美国等 |
| `proxy-sub set/show/del/update` | 订阅链接管理 |

### mihomo CLI 工具（独立可执行）

| 命令 | 功能 |
|------|------|
| `mc` | mihomo API 客户端：查看代理组、节点、切换、延迟、出口测试 |
| `mihomo-bg` | mihomo 进程管理：start/stop/restart/status/log |

## 安装

```bash
git clone https://github.com/Sky2Shaw/proxy-helper.git
cd proxy-helper
bash install.sh
source ~/.bashrc
```

## 使用方法

### 开启代理

```bash
# 基本用法：启动 mihomo + 设置环境变量 + 切新加坡节点
proxy-on

# 切到指定地区
proxy-on 香港
proxy-on 日本

# 传入订阅链接（一步到位：保存链接 → 更新订阅 → 启动 → 切节点）
proxy-on https://sub.example.com/link?token=xxx
proxy-on https://sub.example.com/link?token=xxx 香港
```

### 更新代理

```bash
# 默认：仅测试并切换到最快的新加坡节点
proxy-update

# 先更新订阅配置，再切节点
proxy-update --url

# 保存新的订阅链接并更新
proxy-update --url https://sub.example.com/link?token=xxx

# 仅切节点（同无参数）
proxy-update --no-url
```

### 订阅管理

```bash
# 保存订阅链接
proxy-sub set https://sub.example.com/link?token=xxx

# 查看已保存的链接
proxy-sub show

# 删除已保存的链接
proxy-sub del

# 仅更新订阅配置（不切节点）
proxy-sub update
```

### 测试节点

```bash
# 默认测试新加坡
proxy-test

# 指定地区
proxy-test 香港
proxy-test 日本
proxy-test 美国
```

### 关闭 / 状态

```bash
proxy-off      # 清除 HTTP_PROXY/HTTPS_PROXY/ALL_PROXY
proxy-status   # 查看当前代理状态
```

## 支持的地区关键词

| 关键词 | 匹配 |
|--------|------|
| 新加坡 / SG | 🇸🇬 新加坡 |
| 香港 / HK | 🇭🇰 香港 |
| 日本 / JP | 🇯🇵 日本 |
| 台湾 / TW | 🇨🇳 台湾 |
| 美国 / US | 🇺🇸 美国 |
| 韩国 / KR | 🇰🇷 韩国 |
| 其他文本 | 直接模糊匹配 |

## 支持的订阅格式

- **mihomo YAML 配置**：直接下载的 clash/mihomo 格式配置
- **base64 分享链接**：vmess://、vless://、ss://、hysteria2:// 等链接的 base64 编码列表

下载时自动识别格式并转换。信息节点（剩余流量、套餐到期等）会被自动过滤。

## 订阅更新安全机制

- 下载前自动备份当前配置（保留最近 5 份）
- 保留 `secret`、`mixed-port`、`external-controller` 等关键字段
- YAML 格式验证（proxies、proxy-groups 必须存在）
- 新配置导致 mihomo 启动失败时自动恢复备份
- 直连下载失败时自动尝试走代理下载

## 环境变量

proxy.sh 中的函数会自动从 `/etc/mihomo/config.yaml` 读取配置。
也可以手动设置：

```bash
export MIHOMO_CTRL='http://127.0.0.1:9090'
export MIHOMO_SECRET='你的secret'
export MIHOMO_CONFIG_DIR='/etc/mihomo'
```

持久化到 ~/.bashrc：

```bash
cat >> ~/.bashrc << 'ENV'
export MIHOMO_CTRL=http://127.0.0.1:9090
export MIHOMO_SECRET="$(grep '^secret:' /etc/mihomo/config.yaml | awk '{print $2}')"
export MIHOMO_CONFIG_DIR=/etc/mihomo
ENV
```

## 文件结构

```
proxy-helper/
├── install.sh          # 安装脚本
├── lib/
│   └── proxy.sh        # 代理快捷命令（shell 函数库）
├── bin/
│   ├── mc              # mihomo API 客户端
│   └── mihomo-bg       # mihomo 进程管理器
└── README.md           # 本文档
```

安装后的文件位置：

```
~/.local/bin/mc                # CLI 工具
~/.local/bin/mihomo-bg         # 进程管理
~/.local/lib/proxy.sh          # 函数库（~/.bashrc source 加载）
~/.mihomo_sub_url              # 订阅链接保存
~/.mihomo_config_backup/       # 配置备份目录
```

## 前置要求

- mihomo v1.19+ 已安装在 `/usr/local/bin/mihomo`
- 配置文件位于 `/etc/mihomo/config.yaml`
- python3 + PyYAML（用于 YAML 验证和订阅格式转换）
- curl、sudo

## 常见问题

### `mc version` 没反应

mihomo 未运行。启动：

```bash
mihomo-bg start
# 或直接
proxy-on
```

### 401 Unauthorized

secret 不匹配。重新设置：

```bash
export MIHOMO_SECRET="$(grep '^secret:' /etc/mihomo/config.yaml | awk '{print $2}')"
```

### 订阅下载失败

如果订阅 URL 在国内可直连访问，脚本会先直连下载；失败后再走代理下载。
HTTPS 自签证书会自动跳过验证。

### 代理环境变量

让终端程序（curl、wget、git 等）走 mihomo 代理：

```bash
# 当前会话生效（proxy-on 已自动设置）
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5://127.0.0.1:7890
```
