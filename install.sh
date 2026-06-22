#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
LIB_DIR="$HOME/.local/lib"
MIHOMO_BIN="/usr/local/bin/mihomo"
MIHOMO_CONFIG_DIR="/etc/mihomo"

# ── 1) 安装 mihomo 二进制（如未安装） ──
install_mihomo() {
    if [ -x "$MIHOMO_BIN" ]; then
        echo "✅ mihomo 已安装: $MIHOMO_BIN"
        return 0
    fi

    echo "⏳ 正在下载 mihomo ..."

    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64)   ASSET_PATTERN="mihomo-linux-amd64-v1.*\.gz" ;;
        aarch64|arm64) ASSET_PATTERN="mihomo-linux-arm64.*\.gz" ;;
        *)        echo "❌ 不支持的架构: $ARCH"; return 1 ;;
    esac

    DOWNLOAD_URL="$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
        | grep browser_download_url \
        | grep -E "$ASSET_PATTERN" \
        | head -n 1 \
        | cut -d '"' -f 4)"

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "❌ 无法获取 mihomo 下载链接"
        return 1
    fi

    echo "   下载: $DOWNLOAD_URL"
    curl -L "$DOWNLOAD_URL" -o /tmp/mihomo.gz
    gzip -d /tmp/mihomo.gz
    chmod +x /tmp/mihomo
    sudo mv /tmp/mihomo "$MIHOMO_BIN"

    echo "✅ mihomo 已安装: $MIHOMO_BIN"
}

# ── 2) 创建配置目录（如不存在） ──
setup_config_dir() {
    if [ -d "$MIHOMO_CONFIG_DIR" ]; then
        echo "✅ 配置目录已存在: $MIHOMO_CONFIG_DIR"
        return 0
    fi

    echo "⏳ 创建配置目录: $MIHOMO_CONFIG_DIR"
    sudo mkdir -p "$MIHOMO_CONFIG_DIR"

    # 写入最小可用配置
    sudo tee "$MIHOMO_CONFIG_DIR/config.yaml" > /dev/null <<'MINCFG'
mixed-port: 7890
allow-lan: true
bind-address: '*'
mode: rule
log-level: info
external-controller: 127.0.0.1:9090
secret: 'change-me-please'
proxy-groups:
    - name: 默认
      type: select
      proxies:
          - DIRECT
rules:
    - MATCH,默认
MINCFG

    echo "✅ 最小配置已写入: $MIHOMO_CONFIG_DIR/config.yaml"
    echo "⚠️ 请用 proxy-sub set <URL> 或 proxy-update --url <URL> 更新完整配置"
}

# ── 3) 安装 proxy-helper 工具 ──
install_tools() {
    mkdir -p "$INSTALL_DIR" "$LIB_DIR"

    # 安装 mihomo CLI 工具
    cp ./bin/mc "$INSTALL_DIR/mc"
    cp ./bin/mihomo-bg "$INSTALL_DIR/mihomo-bg"
    chmod +x "$INSTALL_DIR/mc" "$INSTALL_DIR/mihomo-bg"

    # 安装代理快捷命令库
    cp ./lib/proxy.sh "$LIB_DIR/proxy.sh"

    echo "✅ 工具已安装到 $INSTALL_DIR 和 $LIB_DIR"
}

# ── 4) 配置 bashrc ──
setup_bashrc() {
    # 添加 source 到 ~/.bashrc（如果还没有）
    if ! grep -q 'source.*proxy.sh' "$HOME/.bashrc" 2>/dev/null; then
        echo '' >> "$HOME/.bashrc"
        echo '# 代理快捷命令：proxy-on / proxy-off / proxy-update / proxy-sub' >> "$HOME/.bashrc"
        echo "source $LIB_DIR/proxy.sh" >> "$HOME/.bashrc"
    fi

    # 确保 ~/.local/bin 在 PATH
    if ! grep -q 'export PATH.*\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
}

# ── 主流程 ──
echo "╔══════════════════════════════════╗"
echo "║     proxy-helper 安装程序        ║"
echo "╚══════════════════════════════════╝"
echo ""

install_mihomo
setup_config_dir
install_tools
setup_bashrc

echo ""
cat <<MSG
╔══════════════════════════════════╗
║        安装完成！                 ║
╚══════════════════════════════════╝

请执行：

  source ~/.bashrc

然后使用：

  proxy-on [地区|URL]     开启代理
  proxy-off               关闭代理
  proxy-update [--url]    更新节点 / 更新订阅
  proxy-sub set <URL>     设置订阅链接
  proxy-test [地区]       测试节点延迟
  proxy-status            查看代理状态

首次使用建议：

  # 传入订阅链接，一步到位
  proxy-on https://你的订阅链接

  # 或先设置链接再更新
  proxy-sub set https://你的订阅链接
  proxy-update --url

MSG
