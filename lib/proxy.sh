# ═══════════════════════════════════════════════════════════
# mihomo 代理快捷命令
# ═══════════════════════════════════════════════════════════

# ── 配置路径 ──
_PROXY_CONFIG=/etc/mihomo/config.yaml
_PROXY_SUB_FILE=~/.mihomo_sub_url
_PROXY_BACKUP_DIR=~/.mihomo_config_backup
_PROXY_NEW_CONFIG=/tmp/mihomo_new_config.yaml

# ── 地区关键词映射 ──
_proxy_region_keywords() {
    local region="${1:-新加坡}"
    case "$region" in
        新加坡|SG)  echo '新加坡|🇸🇬|SG' ;;
        香港|HK)    echo '香港|🇭🇰|HK' ;;
        日本|JP)    echo '日本|🇯🇵|JP' ;;
        台湾|TW)    echo '台湾|🇨🇳|TW' ;;
        美国|US)    echo '美国|🇺🇸|US' ;;
        韩国|KR)    echo '韩国|🇰🇷|KR' ;;
        *)          echo "$region" ;;
    esac
}

# ── 判断是否为地区关键词 ──
_proxy_is_region() {
    case "$1" in
        新加坡|SG|香港|HK|日本|JP|台湾|TW|美国|US|韩国|KR) return 0 ;;
        *) return 1 ;;
    esac
}

# ── 启动 mihomo（若未运行） ──
_proxy_ensure_running() {
    if mc version &>/dev/null; then
        return 0
    fi
    echo "⏳ mihomo 未运行，正在启动..."
    # 清理 stale 状态
    sudo rm -f /tmp/mihomo.pid
    sudo touch /tmp/mihomo.log
    sudo chmod 666 /tmp/mihomo.log
    sudo pkill mihomo 2>/dev/null; sleep 1
    mihomo-bg start
    sleep 2
    if ! mc version &>/dev/null; then
        echo "❌ mihomo 启动失败！查看日志：mihomo-bg log"
        return 1
    fi
    echo "✅ mihomo 已启动"
}

# ── 获取主代理组名 ──
_proxy_main_group() {
    # 从配置读取第一个 Selector 类型代理组名
    python3 - <<'PY'
import yaml
try:
    with open('/etc/mihomo/config.yaml') as f:
        data = yaml.safe_load(f)
    for g in data.get('proxy-groups', []):
        if g.get('type') == 'select':
            print(g['name'])
            break
    else:
        print('红杏云')
except Exception:
    print('红杏云')
PY
}

# ── 测试地区节点并切换 ──
_proxy_switch_region() {
    local region="${1:-新加坡}"
    local keywords
    keywords=$(_proxy_region_keywords "$region")

    local main_group
    main_group=$(_proxy_main_group)

    # 获取目标地区节点（排除信息节点）
    local target_nodes
    target_nodes=$(mc nodes "$main_group" | \
        grep -E "$keywords" | \
        grep -vE '剩余|套餐|到期|重置|流量|\[')

    if [ -z "$target_nodes" ]; then
        echo "❌ 未找到 ${region} 节点！"
        return 1
    fi

    echo "🔍 测试 ${region} 节点延迟..."
    echo ""

    local fastest_node=""
    local fastest_delay=999999
    local test_log=""
    local count=0

    while IFS= read -r node; do
        [ -z "$node" ] && continue
        count=$((count + 1))
        local result
        result=$(mc delay "$node" 5000 2>/dev/null)

        if echo "$result" | grep -q '"delay"'; then
            local delay
            delay=$(echo "$result" | grep -oE '"delay":[0-9]+' | grep -oE '[0-9]+')
            if [ "$delay" -lt "$fastest_delay" ]; then
                fastest_delay=$delay
                fastest_node="$node"
            fi
            test_log+="  ✅ $node: ${delay}ms"
            if [ "$node" = "$fastest_node" ] && [ "$delay" -eq "$fastest_delay" ]; then
                test_log+=" ← 最快"
            fi
            test_log+=$'\n'
        else
            test_log+="  ❌ $node: 不可用"$'\n'
        fi
    done <<< "$target_nodes"

    echo "$test_log"

    if [ -z "$fastest_node" ]; then
        echo ""
        echo "❌ ${region} 所有节点不可用，拒绝使用其他地区节点！"
        echo "建议：稍后重试或联系服务商"
        return 1
    fi

    # 切换所有代理组到最快节点
    echo ""
    echo "🚀 切换到最快节点: $fastest_node (${fastest_delay}ms)"

    # 切换代理组到最快节点（排除 GLOBAL/DIRECT 等无节点组）
    local groups
    groups=$(mc groups | grep -vE 'GLOBAL|DIRECT' | grep -oE '^[^ ]+')

    for g in $groups; do
        mc switch "$g" "$fastest_node" 2>/dev/null || true
    done

    # 验证代理出口
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ 代理已更新！"
    echo "  节点: $fastest_node"
    echo "  延迟: ${fastest_delay}ms"

    local ip_info
    ip_info=$(mc test 2>/dev/null)
    if [ -n "$ip_info" ]; then
        local country=$(echo "$ip_info" | grep -oE '"country":"[^"]+"' | head -1 | cut -d'"' -f4)
        local ip=$(echo "$ip_info" | grep -oE '"ip":"[^"]+"' | head -1 | cut -d'"' -f4)
        [ -n "$ip" ]     && echo "  出口 IP: $ip"
        [ -n "$country" ] && echo "  出口地区: $country"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━"
}

# ═══════════════════════════════════════════════════════════
# 订阅管理：_proxy_sub_update / proxy-sub
# ═══════════════════════════════════════════════════════════

# ── 订阅配置下载与写入（内部函数） ──
_proxy_sub_update() {
    local sub_url="${1:-}"

    # 如果没有传入 URL，从文件读取
    if [ -z "$sub_url" ] && [ -f "$_PROXY_SUB_FILE" ]; then
        sub_url=$(head -1 "$_PROXY_SUB_FILE")
    fi

    if [ -z "$sub_url" ]; then
        echo "⚠️ 未设置订阅链接，跳过订阅更新"
        return 0
    fi

    echo "📋 更新订阅配置..."
    echo "   链接: $sub_url"

    # 1) 备份当前配置
    mkdir -p "$_PROXY_BACKUP_DIR"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${_PROXY_BACKUP_DIR}/config_${timestamp}.yaml"
    sudo cat "$_PROXY_CONFIG" > "$backup_file"
    echo "   备份: $backup_file"

    # 保留最近 5 个备份
    local backup_count=$(ls -1t "${_PROXY_BACKUP_DIR}"/config_*.yaml 2>/dev/null | wc -l)
    if [ "$backup_count" -gt 5 ]; then
        ls -1t "${_PROXY_BACKUP_DIR}"/config_*.yaml | tail -n +6 | xargs rm -f
    fi

    # 2) 从旧配置提取需要保留的字段
    local old_secret old_mixed_port old_ext_ctrl
    old_secret=$(grep -E '^\s*secret:' "$_PROXY_CONFIG" | head -1 | sed -E 's/^\s*secret:\s*//; s/["\x27]//g; s/\s+$//')
    old_mixed_port=$(grep -E '^\s*mixed-port:' "$_PROXY_CONFIG" | head -1 | sed -E 's/^\s*mixed-port:\s*//')
    old_ext_ctrl=$(grep -E '^\s*external-controller:' "$_PROXY_CONFIG" | head -1 | sed -E "s/^\s*external-controller:\s*//; s/[\"']//g; s/\s+$//")

    # 3) 下载订阅配置（先尝试直连，再尝试走代理）
    local http_code
    http_code=$(curl -skL --max-time 30 --noproxy '*' -o "$_PROXY_NEW_CONFIG" -w "%{http_code}" "$sub_url" 2>/dev/null)

    if [ "$http_code" -ne 200 ]; then
        echo "   直连下载失败 (HTTP $http_code)，尝试走代理..."
        http_code=$(curl -skL --max-time 30 --proxy http://127.0.0.1:7890 -o "$_PROXY_NEW_CONFIG" -w "%{http_code}" "$sub_url" 2>/dev/null)
    fi

    if [ "$http_code" -ne 200 ]; then
        echo "❌ 订阅下载失败 (HTTP $http_code)"
        rm -f "$_PROXY_NEW_CONFIG"
        return 1
    fi

    if [ ! -s "$_PROXY_NEW_CONFIG" ]; then
        echo "❌ 下载的配置文件为空"
        rm -f "$_PROXY_NEW_CONFIG"
        return 1
    fi

    # 4) 判断订阅格式：YAML 配置 vs base64 分享链接
    #    如果不是 YAML，则解码 base64 并将 vmess/vless/ss/hysteria2 链接转为 mihomo proxies
    local is_yaml=false
    if head -3 "$_PROXY_NEW_CONFIG" | grep -qE '^(proxies:|port:|mixed-port:|proxy-groups:)'; then
        is_yaml=true
        echo "   格式: mihomo YAML 配置"
    else
        echo "   格式: base64 分享链接，正在转换为 mihomo 配置..."
        python3 - <<'PY_CONVERT'
import base64, json, yaml, sys, re, urllib.parse

def decode_vmess(link):
    """解码 vmess:// 链接"""
    payload = link.replace('vmess://', '')
    # 某些 vmess 链接可能缺少 padding
    missing = len(payload) % 4
    if missing:
        payload += '=' * (4 - missing)
    try:
        obj = json.loads(base64.b64decode(payload).decode('utf-8'))
    except Exception:
        return None
    proxy = {
        'name': obj.get('ps', 'vmess-node'),
        'type': 'vmess',
        'server': obj.get('add', ''),
        'port': int(obj.get('port', 0)),
        'uuid': obj.get('id', ''),
        'alterId': int(obj.get('aid', 0)),
        'cipher': obj.get('scy', 'auto'),
        'udp': True,
    }
    net = obj.get('net', 'tcp')
    if net == 'ws':
        proxy['network'] = 'ws'
        opts = obj.get('path', '/')
        host = obj.get('host', '')
        proxy['ws-opts'] = {'path': opts}
        if host:
            proxy['ws-opts']['headers'] = {'Host': host}
    elif net == 'grpc':
        proxy['network'] = 'grpc'
        proxy['grpc-opts'] = {'grpc-service-name': obj.get('path', '')}
    elif net == 'h2':
        proxy['network'] = 'h2'
        proxy['h2-opts'] = {'path': [obj.get('path', '/')], 'host': [obj.get('host', '')]}
    tls = obj.get('tls', '')
    if tls == 'tls':
        proxy['tls'] = True
        sni = obj.get('sni', obj.get('host', ''))
        if sni:
            proxy['servername'] = sni
    return proxy

def decode_vless(link):
    """解码 vless:// 链接"""
    # vless://uuid@host:port?params#name
    body = link.replace('vless://', '')
    # 分离 name
    if '#' in body:
        body, name = body.rsplit('#', 1)
        name = urllib.parse.unquote(name)
    else:
        name = 'vless-node'
    # 分离 params
    if '?' in body:
        addr_part, params_str = body.split('?', 1)
    else:
        addr_part, params_str = body, ''
    # 分离 uuid@host:port
    if '@' in addr_part:
        uuid, addr = addr_part.split('@', 1)
    else:
        return None
    if ':' in addr:
        host, port = addr.rsplit(':', 1)
        port = int(port)
    else:
        return None
    params = dict(urllib.parse.parse_qsl(params_str))
    proxy = {
        'name': name,
        'type': 'vless',
        'server': host,
        'port': port,
        'uuid': uuid,
        'udp': True,
        'tls': params.get('security', '') == 'tls' or params.get('security', '') == 'reality',
        'network': params.get('type', 'tcp'),
        'flow': params.get('flow', ''),
    }
    if params.get('type') == 'ws':
        proxy['ws-opts'] = {
            'path': params.get('path', '/'),
            'headers': {'Host': params.get('host', '')} if params.get('host') else {}
        }
    if params.get('type') == 'grpc':
        proxy['grpc-opts'] = {'grpc-service-name': params.get('serviceName', '')}
    if params.get('security') == 'reality':
        proxy['reality-opts'] = {
            'public-key': params.get('pbk', ''),
            'short-id': params.get('sid', ''),
        }
        proxy['servername'] = params.get('sni', params.get('fp', ''))
    elif params.get('security') == 'tls':
        proxy['servername'] = params.get('sni', '')
    if params.get('client-fingerprint'):
        proxy['client-fingerprint'] = params.get('client-fingerprint')
    # 过滤空值
    proxy = {k: v for k, v in proxy.items() if v != '' and v is not True or k in ('tls', 'udp')}
    return proxy

def decode_ss(link):
    """解码 ss:// 链接"""
    body = link.replace('ss://', '')
    if '#' in body:
        body, name = body.rsplit('#', 1)
        name = urllib.parse.unquote(name)
    else:
        name = 'ss-node'
    # sip002 format: method:password@host:port
    if '@' in body:
        cred, addr = body.split('@', 1)
        try:
            decoded_cred = base64.b64decode(cred + '==').decode('utf-8')
            method, password = decoded_cred.split(':', 1)
        except Exception:
            method, password = cred.split(':', 1)
        host, port = addr.rsplit(':', 1)
        return {
            'name': name,
            'type': 'ss',
            'server': host,
            'port': int(port),
            'cipher': method,
            'password': password,
            'udp': True,
        }
    return None

def decode_hysteria2(link):
    """解码 hysteria2:// 链接"""
    body = link.replace('hysteria2://', '').replace('hy2://', '')
    if '#' in body:
        body, name = body.rsplit('#', 1)
        name = urllib.parse.unquote(name)
    else:
        name = 'hy2-node'
    if '?' in body:
        addr_part, params_str = body.split('?', 1)
    else:
        addr_part, params_str = body, ''
    if '@' in addr_part:
        password, addr = addr_part.split('@', 1)
    else:
        return None
    if ':' in addr:
        host, port = addr.rsplit(':', 1)
        port = int(port)
    else:
        return None
    params = dict(urllib.parse.parse_qsl(params_str))
    proxy = {
        'name': name,
        'type': 'hysteria2',
        'server': host,
        'port': port,
        'password': urllib.parse.unquote(password),
        'udp': True,
        'sni': params.get('sni', host),
        'skip-cert-verify': params.get('insecure', '0') == '1',
    }
    if params.get('obfs'):
        proxy['obfs'] = params['obfs']
        proxy['obfs-password'] = params.get('obfs-password', '')
    return proxy

# 读取下载的文件
with open('/tmp/mihomo_new_config.yaml') as f:
    raw = f.read()

# 尝试 base64 解码
try:
    # 清理空白行
    lines = [l.strip() for l in raw.strip().split('\n') if l.strip()]
    decoded = base64.b64decode('\n'.join(lines)).decode('utf-8')
    share_links = [l.strip() for l in decoded.split('\n') if l.strip()]
except Exception:
    share_links = [l.strip() for l in raw.strip().split('\n') if l.strip()]

proxies = []
for link in share_links:
    if link.startswith('vmess://'):
        p = decode_vmess(link)
        if p:
            proxies.append(p)
    elif link.startswith('vless://'):
        p = decode_vless(link)
        if p:
            proxies.append(p)
    elif link.startswith('ss://'):
        p = decode_ss(link)
        if p:
            proxies.append(p)
    elif link.startswith('hysteria2://') or link.startswith('hy2://'):
        p = decode_hysteria2(link)
        if p:
            proxies.append(p)

# 过滤信息节点
INFO_KEYWORDS = ['剩余', '套餐', '到期', '重置', '流量', '官网', '订阅', '更新', '群', '频道']
proxies = [p for p in proxies if not any(k in p['name'] for k in INFO_KEYWORDS)]

if len(proxies) == 0:
    print("❌ 转换后没有可用节点", file=sys.stderr)
    sys.exit(1)

# 读取旧配置，保留基础设置部分，替换 proxies 和 proxy-groups
with open('/etc/mihomo/config.yaml') as f:
    old_data = yaml.safe_load(f)

# 更新 proxies
old_data['proxies'] = proxies

# 构建 proxy-groups
node_names = [p['name'] for p in proxies]

# 查找已有的代理组，更新节点列表
updated_groups = []
for g in old_data.get('proxy-groups', []):
    gtype = g.get('type', '')
    if gtype in ('select', 'Selector'):
        # 保留子引用（如"自动选择"、"故障转移"），更新节点
        new_proxies = []
        for p in g.get('proxies', []):
            # 保留对其他组的引用
            if p in [gg.get('name') for gg in old_data.get('proxy-groups', [])]:
                new_proxies.append(p)
        # 添加新节点
        new_proxies.extend(node_names)
        g['proxies'] = new_proxies
        updated_groups.append(g)
    elif gtype in ('url-test', 'URLTest', 'fallback', 'Fallback', 'load-balance', 'LoadBalance'):
        g['proxies'] = node_names
        updated_groups.append(g)
    else:
        # 保留其他组
        updated_groups.append(g)

old_data['proxy-groups'] = updated_groups

# 写入新配置（用 yaml.dump，但保留 flow style）
with open('/tmp/mihomo_new_config.yaml', 'w') as f:
    yaml.dump(old_data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

print(f"   转换完成: {len(proxies)} 个节点")
PY_CONVERT
        if [ $? -ne 0 ]; then
            echo "❌ 分享链接转换失败，保留旧配置"
            rm -f "$_PROXY_NEW_CONFIG"
            return 1
        fi
    fi

    # 5) 验证最终 YAML 格式
    python3 - <<'PY_VALIDATE'
import yaml, sys
try:
    with open('/tmp/mihomo_new_config.yaml') as f:
        data = yaml.safe_load(f)
    if data is None:
        print("❌ 配置解析结果为空", file=sys.stderr)
        sys.exit(1)
    for k in ['proxies', 'proxy-groups']:
        if k not in data:
            print(f"❌ 缺少必要字段: {k}", file=sys.stderr)
            sys.exit(1)
    if not isinstance(data['proxies'], list) or len(data['proxies']) == 0:
        print("❌ proxies 必须是非空列表", file=sys.stderr)
        sys.exit(1)
    print(f"   验证通过: {len(data['proxies'])} 个节点, {len(data['proxy-groups'])} 个代理组")
except yaml.YAMLError as e:
    print(f"❌ YAML 解析失败: {e}", file=sys.stderr)
    sys.exit(1)
PY_VALIDATE
    if [ $? -ne 0 ]; then
        echo "❌ 新配置验证失败，保留旧配置"
        rm -f "$_PROXY_NEW_CONFIG"
        return 1
    fi

    # 5) 保留 secret / mixed-port / external-controller
    export _PS_OLD_SECRET="$old_secret"
    export _PS_OLD_MIXED_PORT="$old_mixed_port"
    export _PS_OLD_EXT_CTRL="$old_ext_ctrl"
    python3 - <<'PY_PATCH'
import re, os

old_secret    = os.environ.get('_PS_OLD_SECRET', '')
old_mixed_port = os.environ.get('_PS_OLD_MIXED_PORT', '')
old_ext_ctrl   = os.environ.get('_PS_OLD_EXT_CTRL', '')

with open('/tmp/mihomo_new_config.yaml') as f:
    content = f.read()

# 保留 secret
if old_secret:
    if re.search(r'^secret:', content, re.MULTILINE):
        content = re.sub(r'^secret:\s*.+$', f'secret: {old_secret}', content, count=1, flags=re.MULTILINE)
    else:
        # 在文件开头插入
        content = f'secret: {old_secret}\n' + content

# 保留 mixed-port
if old_mixed_port and re.search(r'^mixed-port:', content, re.MULTILINE):
    content = re.sub(r'^mixed-port:\s*.+$', f'mixed-port: {old_mixed_port}', content, count=1, flags=re.MULTILINE)

# 保留 external-controller
if old_ext_ctrl and re.search(r'^external-controller:', content, re.MULTILINE):
    content = re.sub(r'^external-controller:\s*.+$', f"external-controller: '{old_ext_ctrl}'", content, count=1, flags=re.MULTILINE)

with open('/tmp/mihomo_new_config.yaml', 'w') as f:
    f.write(content)
PY_PATCH
    unset _PS_OLD_SECRET _PS_OLD_MIXED_PORT _PS_OLD_EXT_CTRL

    # 6) 写入新配置
    sudo cp "$_PROXY_NEW_CONFIG" "$_PROXY_CONFIG"
    rm -f "$_PROXY_NEW_CONFIG"
    echo "   配置已写入: $_PROXY_CONFIG"

    # 7) 重启 mihomo
    mihomo-bg stop 2>/dev/null; sleep 1
    _proxy_ensure_running
    if [ $? -ne 0 ]; then
        echo "❌ 新配置导致启动失败，正在恢复备份..."
        sudo cp "$backup_file" "$_PROXY_CONFIG"
        mihomo-bg stop 2>/dev/null; sleep 1
        _proxy_ensure_running
        if [ $? -ne 0 ]; then
            echo "❌ 严重错误：备份配置也无法启动，请手动检查 $_PROXY_CONFIG"
            return 1
        fi
        echo "✅ 已恢复备份配置"
        return 1
    fi

    echo "✅ 订阅配置更新完成"
    return 0
}

# ── 订阅链接管理 ──
proxy-sub() {
    local cmd="${1:-}"
    local url="${2:-}"

    case "$cmd" in
        set)
            if [ -z "$url" ]; then
                echo "用法: proxy-sub set <订阅链接>"
                return 1
            fi
            echo "$url" > "$_PROXY_SUB_FILE"
            echo "✅ 订阅链接已保存到 $_PROXY_SUB_FILE"
            ;;
        show)
            if [ -f "$_PROXY_SUB_FILE" ]; then
                echo "订阅链接: $(cat $_PROXY_SUB_FILE)"
            else
                echo "⚠️ 未设置订阅链接"
            fi
            ;;
        del)
            rm -f "$_PROXY_SUB_FILE"
            echo "✅ 订阅链接已删除"
            ;;
        update)
            _proxy_sub_update "$url"
            ;;
        *)
            echo "用法: proxy-sub [set <链接>|show|del|update]"
            echo ""
            echo "  set <链接>  保存订阅链接"
            echo "  show        显示已保存的链接"
            echo "  del         删除已保存的链接"
            echo "  update      下载并更新订阅配置"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════
# 代理快捷命令：proxy-on / proxy-off / proxy-status
# ═══════════════════════════════════════════════════════════

# ── 开启代理：启动服务 + 设置环境变量，可选订阅更新和切节点 ──
proxy-on() {
    local sub_url=""
    local region="新加坡"

    # 解析参数：第1参数可能是 URL 或地区，第2参数可能是地区
    local arg1="${1:-}"
    local arg2="${2:-}"

    if [[ "$arg1" =~ ^https?:// ]]; then
        sub_url="$arg1"
        if [ -n "$arg2" ]; then
            region="$arg2"
        fi
    elif _proxy_is_region "$arg1"; then
        region="$arg1"
    fi

    # 1) 启动 mihomo
    _proxy_ensure_running || return 1

    # 2) 如果有订阅 URL，保存并更新配置
    if [ -n "$sub_url" ]; then
        echo "$sub_url" > "$_PROXY_SUB_FILE"
        _proxy_sub_update "$sub_url" || echo "⚠️ 订阅更新失败，继续使用现有配置"
    fi

    # 3) 设置环境变量
    export HTTP_PROXY=http://127.0.0.1:7890
    export HTTPS_PROXY=http://127.0.0.1:7890
    export ALL_PROXY=socks5://127.0.0.1:7890
    echo "✅ 代理环境变量已设置"

    # 4) 切换到目标地区节点
    _proxy_switch_region "$region"
}

# ── 关闭代理（清除环境变量） ──
proxy-off() {
    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY
    echo "✅ 代理已关闭"
}

# ── 查看代理状态 ──
proxy-status() {
    echo "HTTP_PROXY  = ${HTTP_PROXY:-未设置}"
    echo "HTTPS_PROXY = ${HTTPS_PROXY:-未设置}"
    echo "ALL_PROXY   = ${ALL_PROXY:-未设置}"
    echo ""
    if mc version &>/dev/null; then
        echo "mihomo: ✅ 运行中"
        mc current 2>/dev/null | head -5
    else
        echo "mihomo: ❌ 未运行"
    fi
}

# ── 测试延迟：默认测新加坡，可指定地区 ──
proxy-test() {
    _proxy_ensure_running || return 1
    local region="${1:-新加坡}"
    local keywords
    keywords=$(_proxy_region_keywords "$region")

    local main_group
    main_group=$(_proxy_main_group)

    local target_nodes
    target_nodes=$(mc nodes "$main_group" | \
        grep -E "$keywords" | \
        grep -vE '剩余|套餐|到期|重置|流量|\[')

    if [ -z "$target_nodes" ]; then
        echo "❌ 未找到 ${region} 节点！"
        return 1
    fi

    echo "🔍 测试 ${region} 节点延迟..."
    echo ""

    local fastest_node=""
    local fastest_delay=999999
    local test_log=""
    local count=0

    while IFS= read -r node; do
        [ -z "$node" ] && continue
        count=$((count + 1))
        local result
        result=$(mc delay "$node" 5000 2>/dev/null)

        if echo "$result" | grep -q '"delay"'; then
            local delay
            delay=$(echo "$result" | grep -oE '"delay":[0-9]+' | grep -oE '[0-9]+')
            if [ "$delay" -lt "$fastest_delay" ]; then
                fastest_delay=$delay
                fastest_node="$node"
            fi
            test_log+="  ✅ $node: ${delay}ms"
            if [ "$node" = "$fastest_node" ] && [ "$delay" -eq "$fastest_delay" ]; then
                test_log+=" ← 最快"
            fi
            test_log+=$'\n'
        else
            test_log+="  ❌ $node: 不可用"$'\n'
        fi
    done <<< "$target_nodes"

    echo "$test_log"

    if [ -z "$fastest_node" ]; then
        echo "❌ ${region} 所有节点不可用！"
        return 1
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━"
    echo "🏆 最快节点: $fastest_node (${fastest_delay}ms)"
    echo "   共测试 ${count} 个节点"
    echo "━━━━━━━━━━━━━━━━━━━━━━"
}

# ── 更新代理：默认仅切节点，--url 时执行订阅更新+切节点 ──
proxy-update() {
    local do_sub=false
    local sub_url=""

    # 解析参数
    case "${1:-}" in
        --url)
            do_sub=true
            if [ -n "${2:-}" ]; then
                sub_url="$2"
                echo "$sub_url" > "$_PROXY_SUB_FILE"
            fi
            ;;
        --no-url)
            do_sub=false
            ;;
        "")
            # 默认：仅切节点，不做订阅更新
            ;;
        *)
            echo "用法: proxy-update [--url [订阅链接]|--no-url]"
            echo ""
            echo "  (无参数)     仅切换到最快节点"
            echo "  --url        使用已保存的订阅链接更新配置，再切节点"
            echo "  --url <链接>  保存链接并更新配置，再切节点"
            echo "  --no-url     仅切节点（同无参数）"
            return 1
            ;;
    esac

    # 1) 启动 mihomo
    _proxy_ensure_running || return 1

    # 2) 订阅更新（仅 --url 时）
    if [ "$do_sub" = true ]; then
        _proxy_sub_update "$sub_url" || echo "⚠️ 订阅更新失败，继续使用现有配置"
    fi

    # 3) 切换到新加坡最快节点
    _proxy_switch_region "新加坡"
}
