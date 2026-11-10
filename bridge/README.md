# TVGuard Agent + N1 Bridge · 双端联动 0.2.0（实验影子版）

## 为何不把旧的 TVGuard 全量 IPK 重打包？

用户 N1 真机已经使用 `v0.1.13-r15-temporal-state-migration`。当前仓库 main 为更早 v0.1.12，公开 `feat/v0.1.13-smart-billing` 也没有 r15 的所有固化内容。**不可用旧源码生成的 luci-app-tvguard 覆盖真机。**

本方案交付 **独立、仅影子观察的 `tvguard-agent-bridge_0.2.0-1_all.ipk`**。它仅安装独立 CGI、只读融合状态脚本和一次生成的配对密钥；不覆盖 `tvguardctl`、`tvguardd`、LuCI、iptables、防火墙、代理、配额和奖励，也不重启相关服务。

## 链路与安全

Agent → N1 的 OpenWrt uhttpd `/cgi-bin/tvguard-agent`（POST，固定最小协议）
- 仅接受来自 UCI `tvguard.main.ip` 的请求；单次请求最多 512 字节；需要 32 字节十六进制配对码。
- 只保存最新一份包名、Activity、Android 音频活动提示、亮屏提示及服务器接收时间到 `/var/run/tvguard-agent-bridge/latest`（RAM），**无历史日志、无闪存持续写入**。
- 单次 HTTP 200 OK 为收到；3xx/4xx/5xx 不计成功。旧数据超过 35 秒直接作为失效。
- 配对码在 `/etc/tvguard/agent-bridge.key` 中生成一次，600 权限。电视首次配置服务器 URL 与配对码需要在私有首选项落盘一次；不会保存流量历史。
- **明文 LAN HTTP 的密钥在局域网不防嗅探，本版本仅供影子联调，不能作为真实防火墙/计费授权。** 正式控制需额外认证、重放防护和部署审计。
- 影子分析输出 `system_home`、`app_home_candidate`、`playing_candidate`、`player_open_audio_inactive`、`sleep_candidate`、`unknown`。`PlayerActivity`、`AudioManager.isMusicActive()` 或出站 PPS 单独都**不能证明视频真的播放或暂停**；不修改使用额度。
- 如果电视后台被清理、断网、失权限，发送停止，N1 35 秒后自动标记 stale。

## N1 操作（无需修改原 IPK）

1. 单独安装 companion IPK：`opkg install /tmp/tvguard-agent-bridge_0.2.0-1_all.ipk`。不要使用旧版主仓生成的 `luci-app-tvguard` 替换 r15。
2. 确保 N1 当前 uhttpd 在 LAN 监听，且已启用 CGI prefix `/cgi-bin`。
3. 查看一次性 token：`/usr/libexec/tvguard-agent-bridge-report pairing`。
4. 记下 N1 的 LAN IP。电视 Agent UI 填写 `http://N1_LAN_IP/cgi-bin/tvguard-agent` 与配对码，保存后启动监测。
5. 测试电视视频首页、正常播放、暂停、桌面，N1 执行 `/usr/libexec/tvguard-agent-bridge-report status`；若 HTTP 连通将看到 `agent=online` 和包名/音频提示、Router PPS 及候选。
6. 失联后 `agent=stale` 或 `agent=missing`；不会影响原有 N1 控制系统。

## 对成功的定义

0.2.0 只交付**真实两端数据互通的旁路观察闭环**，不是正式智能计时成品。必须收集人工标注下的 576p/720p、4K、暂停、App 首页、系统桌面/待机多种样本，验证联合证据何时可区别，之后才决定是否安全接入 `USED_S`。若暂停和低码率播放证据仍重合，不能宣称实现精确计时。
