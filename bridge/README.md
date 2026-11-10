# TVGuard Agent + N1 Bridge · 双端联动 0.2.1（实验影子版）

## 为何不把旧的 TVGuard 全量 IPK 重打包？

用户 N1 真机已经使用 `v0.1.13-r15-temporal-state-migration`。当前仓库 main 为更早 v0.1.12，公开 `feat/v0.1.13-smart-billing` 也没有 r15 的所有固化内容。**不可用旧源码生成的 luci-app-tvguard 覆盖真机。**

本方案交付 **独立、仅影子观察的 `tvguard-agent-bridge_0.2.1-1_all.ipk`**。它仅安装独立 CGI、只读融合状态脚本和一次生成的配对密钥；不覆盖 `tvguardctl`、`tvguardd`、LuCI、iptables、防火墙、代理、配额和奖励，也不重启相关服务。

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

1. 单独安装 companion IPK：`opkg install /tmp/tvguard-agent-bridge_0.2.1-1_all.ipk`。不要使用旧版主仓生成的 `luci-app-tvguard` 替换 r15。
2. 确保 N1 当前 uhttpd 在 LAN 监听，且已启用 CGI prefix `/cgi-bin`。
3. 查看一次性 token：`/usr/libexec/tvguard-agent-bridge-report pairing`。
4. 记下 N1 的 LAN IP。电视 Agent UI 填写 `http://N1_LAN_IP/cgi-bin/tvguard-agent` 与配对码，保存后启动监测。
5. 测试电视视频首页、正常播放、暂停、桌面，N1 执行 `/usr/libexec/tvguard-agent-bridge-report status`；若 HTTP 连通将看到 `agent=online` 和包名/音频提示、Router PPS 及候选。
6. 失联后 `agent=stale` 或 `agent=missing`；不会影响原有 N1 控制系统。

## 对成功的定义

0.2.1 只交付**真实两端数据互通的旁路观察闭环**，不是正式智能计时成品。必须收集人工标注下的 576p/720p、4K、暂停、App 首页、系统桌面/待机多种样本，验证联合证据何时可区别，之后才决定是否安全接入 `USED_S`。若暂停和低码率播放证据仍重合，不能宣称实现精确计时。

## v0.2.1 · 修复 LEDE/N1 BusyBox 安装失败（2026-11-10）

v0.2.0 在真实 N1 安装时报告 `od: not found`，随后出现 `file_sha256sum_alloc: Failed to open file /etc/tvguard/agent-bridge.key`。

- 生成配对码不再调用 `od`。用 `dd` 从内核 `/dev/urandom` 读取 32 字节随机种子、`sha256sum` 运算，再取前 32 位十六进制字符串。任何依赖缺失或随机读取失败均拒绝生成。
- 必须严格校验密钥内容，而非只看文件是否非空。旧失败安装留下的空文件、仅换行文件、无效内容会原子修复；已存在的合法配对密钥保持不变。
- `control/conffiles` 不再声明一个不存在于 `data.tar.gz` 的运行时生成密钥，避免 opkg 校验无效路径；安装配置仅执行一次写入，密钥默认权限 600。
- 新增在 **没有 `od`** 的最小 BusyBox 模拟命令环境下执行 `postinst` 的回归测试，并检验幂等性、权限、缺陷修复和包元数据。

如旧包仍处于已安装但配置失败状态，可只卸载 `tvguard-agent-bridge` 后安装修复版 0.2.1-1；**不得删除或降级 `luci-app-tvguard` 主包**。

## v0.2.2 · 小米 Android 6 电视遥控器零键盘配对

固定地址：N1 192.168.101.99，电视 192.168.101.76。电视 APK 首次自动预填 `http://192.168.101.99/cgi-bin/tvguard-agent`；更改地址通过电视遥控器可操作的数字键盘（不依赖 TV 输入法）。

**一键配对步骤：** N1 SSH 执行 `/usr/libexec/tvguard-agent-bridge-pair open`，开启最长 120 秒的一次性配对窗口；电视打开 Agent v0.2.2，按方向键选「自动配对 N1（无需输入密钥）」并按确认键。只有源地址等于 UCI tvguard.main.ip 的电视可以 POST `PAIR1`，一次成功即关闭窗口，电视从 HTTP 响应中取得现有 32 位 token 并保存一次 SharedPreferences。窗口关闭后不再透露密钥。可执行 `/usr/libexec/tvguard-agent-bridge-pair status` 或 `close`。

明文局域网 HTTP 上的 token 仍有局域网嗅探风险，因此 **仅用于影子观察，不参与正式限额、封禁、家庭成员权限判断**。不将固定密钥写入公开 APK；电视无持久日志/缓存/队列，配对 token 仅首次成功时写入小型配置文件。

N1 独立 Bridge v0.2.2-1 可从 v0.2.1-1 单独升级，配置脚本保留已生成的合法 token，不需重装核心 luci-app-tvguard，不需重启 N1。
