#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
LIB_DIR="$HOME/.local/lib"

mkdir -p "$INSTALL_DIR" "$LIB_DIR"

# 安装 mihomo 工具包
cp ./bin/mc "$INSTALL_DIR/mc"
cp ./bin/mihomo-bg "$INSTALL_DIR/mihomo-bg"
chmod +x "$INSTALL_DIR/mc" "$INSTALL_DIR/mihomo-bg"

# 安装代理快捷命令库
cp ./lib/proxy.sh "$LIB_DIR/proxy.sh"

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

cat <<MSG
安装完成！

请执行：

  source ~/.bashrc

然后使用：

  proxy-on [地区|URL]     开启代理
  proxy-off               关闭代理
  proxy-update [--url]    更新节点 / 更新订阅
  proxy-sub set <URL>     设置订阅链接
  proxy-test [地区]       测试节点延迟
  proxy-status            查看代理状态
  mc groups               查看代理组
  mc switch <组> <节点>   切换节点
  mihomo-bg start/stop    管理 mihomo 进程

MSG
