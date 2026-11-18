#!/bin/sh
# N1 家长遥控只读预检。不更改配额、模式、授权、Docker 或防火墙。
set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
fail=0
pass() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
bad() { printf '[FAIL] %s\n' "$1"; fail=$((fail + 1)); }

if [ -x /usr/libexec/tvguard-isolation-audit ]; then
    audit="$(/usr/libexec/tvguard-isolation-audit 2>/dev/null || :)"
    [ "$audit" = ok ] && pass 'TVGuard 隔离审计正常' || bad "TVGuard 隔离审计异常：$audit"
fi
if [ -x /usr/libexec/tvguard-status ]; then
    data="$(/usr/libexec/tvguard-status status 2>/dev/null || :)"
    if printf '%s\n' "$data" | grep -q '"watch_seconds":' &&
       printf '%s\n' "$data" | grep -q '"mode":'; then
        pass '观看统计和模式状态可读取'
    else
        bad '观看统计或模式状态无法读取'
    fi
    unset data
else
    bad 'tvguard-status 不存在'
fi
if [ -x /usr/libexec/tvguard-random-hex ]; then
    p="$(/usr/libexec/tvguard-random-hex 16 2>/dev/null || :)"
    s="$(/usr/libexec/tvguard-random-hex 32 2>/dev/null || :)"
    lp="$(printf '%s' "$p" | wc -c | tr -d ' ')"
    ls="$(printf '%s' "$s" | wc -c | tr -d ' ')"
    if [ "$lp" = 32 ] && [ "$ls" = 64 ] &&
       printf '%s%s\n' "$p" "$s" | grep -Eq '^[a-f0-9]+$'; then
        pass 'BusyBox 随机码功能正常（不会输出密钥）'
    else
        bad 'BusyBox 随机码生成失败'
    fi
    unset p s
else
    bad '随机码辅助程序缺失'
fi

if [ -f /etc/tvguard/remote-enabled ] &&
   [ "$(cat /etc/tvguard/remote-enabled)" = 1 ]; then
    [ -x /usr/sbin/uhttpd ] && pass 'uhttpd 已安装' || bad 'uhttpd 不存在'
    home_code="$(curl --noproxy '*' --max-time 3 -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18765/ 2>/dev/null || :)"
    [ "$home_code" = 200 ] && pass '本机首页 HTTP 200' || bad "本机首页 HTTP $home_code"
    unauth="$(curl --noproxy '*' --max-time 3 -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:18765/cgi-bin/tvg?action=status' 2>/dev/null || :)"
    [ "$unauth" = 401 ] && pass '未授权 API 返回 401' || bad "未授权 API 返回 $unauth"
    if [ -f /etc/tvguard/remote-lan-enabled ] &&
       [ "$(cat /etc/tvguard/remote-lan-enabled)" = 1 ]; then
        ipaddr="$(/usr/libexec/tvguard-remote-lan-ip 2>/dev/null || :)"
        if [ -n "$ipaddr" ]; then
            lan_code="$(curl --noproxy '*' --max-time 3 -s -o /dev/null -w '%{http_code}' "http://$ipaddr:18765/" 2>/dev/null || :)"
            [ "$lan_code" = 200 ] && pass "LAN HTTP：$ipaddr:18765" || bad "LAN HTTP $lan_code"
        else
            bad '找不到 br-lan 私有地址'
        fi
    else
        warn 'LAN HTTP 未启用'
    fi
else
    warn '家长遥控服务未启用，跳过 HTTP 检查'
fi
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker container inspect tvguard-cloudflared >/dev/null 2>&1; then
        label="$(docker inspect -f '{{index .Config.Labels "org.tvguard.owner"}}' tvguard-cloudflared 2>/dev/null || :)"
        running="$(docker inspect -f '{{.State.Running}}' tvguard-cloudflared 2>/dev/null || :)"
        cmd="$(docker inspect -f '{{json .Config.Cmd}}' tvguard-cloudflared 2>/dev/null || :)"
        [ "$label" = luci-app-tvguard ] && pass 'Tunnel 所有权标签正确' || bad 'Tunnel 所有权标签不正确'
        [ "$running" = true ] && pass 'Tunnel 容器运行中' || bad 'Tunnel 容器不在运行'
        printf '%s\n' "$cmd" | grep -Fq '127.0.0.1:20241' &&
            pass 'Tunnel Metrics 绑定 localhost' || bad 'Tunnel Metrics 绑定地址异常'
        unset cmd
    else
        warn 'Tunnel 专用容器尚未创建'
    fi
else
    warn 'Docker 不可用，跳过容器检查'
fi

printf '\n'
if [ "$fail" -gt 0 ]; then
    printf '预检失败：%s 项。请先排查，不要发布公网入口。\n' "$fail"
    exit 1
fi
echo '预检已执行：通过的仅是本地检查；仍需 iPhone 和 Cloudflare Access 实测。'
