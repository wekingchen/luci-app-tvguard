# TVGuard Agent + N1 Bridge · 双端联动 0.2.7（实验影子版）

## 为何不把旧的 TVGuard 全量 IPK 重打包？

用户 N1 真机已经使用 `v0.1.13-r15-temporal-state-migration`。当前仓库 main 为更早 v0.1.12，公开 `feat/v0.1.13-smart-billing` 也没有 r15 的所有固化内容。**不可用旧源码生成的 luci-app-tvguard 覆盖真机。**

本方案交付 **独立、仅影子观察的 `tvguard-agent-bridge_0.2.7-1_all.ipk`**。它仅安装独立 CGI、只读融合状态脚本和一次生成的配对密钥；不覆盖 `tvguardctl`、`tvguardd`、LuCI、iptables、防火墙、代理、配额和奖励，也不重启相关服务。

## 链路与安全

Agent → N1 的 OpenWrt uhttpd `/cgi-bin/tvguard-agent`（POST，固定最小协议）
- 仅接受来自 UCI `tvguard.main.ip` 的请求；单次请求最多 512 字节；需要 32 字节十六进制配对码。
- 只保存最新一份包名、Activity、Android 音频活动提示、亮屏提示及服务器接收时间到 `/var/run/tvguard-agent-bridge/latest`（RAM），**无历史日志、无闪存持续写入**。
- 单次 HTTP 200 OK 为收到；3xx/4xx/5xx 不计成功。旧数据超过 35 秒直接作为失效。
- 配对码在 `/etc/tvguard/agent-bridge.key` 中生成一次，600 权限。电视首次配置服务器 URL 与配对码需要在私有首选项落盘一次；不会保存流量历史。
- **明文 LAN HTTP 的密钥在局域网不防嗅探，本版本仅供影子联调，不能作为真实防火墙/计费授权。** 正式控制需额外认证、重放防护和部署审计。
- v0.2.7 新增 `combined_state=playing|paused|app_home|system_home|unknown` 与详细 `combined_candidate`。其中只有已在真机验证 Activity 语义的场景才允许进入四状态；`PlayerActivity`、`AudioManager.isMusicActive()` 或单个 PPS 窗口单独都**不能证明视频真的播放或暂停**；不修改使用额度。
- 如果电视后台被清理、断网、失权限，发送停止，N1 35 秒后自动标记 stale。

## N1 操作（无需修改原 IPK）

1. 单独安装 companion IPK：`opkg install /tmp/tvguard-agent-bridge_0.2.7-1_all.ipk`。不要使用旧版主仓生成的 `luci-app-tvguard` 替换 r15。
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

## v0.2.3 · 首次播放失联及音频活动假阴性处理（2026-11-10）

真机日志显示银河奇异果播放器 PPS 476/494/482/227，Android 音频提示却为 0；随后 N1 69 秒未收到新的报告。旧版 soak 每 10 秒重复读取同一份 Agent 上报，最后几行 age=4/14/25/35 是**同一条旧报告**，不能当作四次独立确认。

修复：
- Agent 上报独立于 UsageStats 采样（采样每 5 秒，心跳每 10 秒），即使厂商 UsageStats 查询卡顿，也能继续传递心跳。超过 20 秒没有新鲜有效快照时发送 `unknown`，禁止重复宣称旧的 PlayerActivity。
- N1 输出最近接收时间、报告序号和客户端上报时间；失联时保留最后收到的序号及服务端时间作为诊断，不把历史前台当成当前活动。
- `audio_active=0` 对视频播放不构成暂停证据，重命名为 `player_state_unresolved_audio_hint_off`；继续严格影子运行，不影响正式计时。
- N1 Shadow Soak 切换到 `/var/run/tvguard-agent-bridge/soak-v2.csv`，最多 180 行，增加报告序号、接收时间与 is_new_report；同一报告重复采样标记为 `repeated_report_not_new_evidence`，超过 35 秒失联标记 `agent_stale`。旧 v1 数据保留在原 RAM 文件，重启后自然清空。
- 如果电视整个进程被系统回收，独立上报线程也会停止，**不能因此宣称解决了厂商后台清理**。后续据真机 seq 和失联情况进一步诊断。

## v0.2.4 · Agent 进程重启证据

Shadow Soak v2 在 N1 RAM 中保留上一次报告序号。若新的有效报告序号从较大值回落（例如 6 → 1），该行标记 `agent_process_restart_suspected`。这与 Android Agent 的进程内 sequence 重置相对应，用来判断 watchdog 是否实际拉起了新进程。它仅是诊断证据，不参与正式计时。

Soak 自身重启时会从 RAM 历史最后一行恢复 last_seq / last_received 签名，避免把同一条旧上报重新算成新证据。


## v0.2.7 · PlayerActivity + N1 pause_hint 时序融合（2026-11-11）

本阶段只解决 **Shadow 层的 paused 识别**，不接入正式计时。Android Agent 继续使用已真机验证的
`0.2.6-r2`；因为现有上报已经包含 package / Activity / audio / screen，暂停融合所需的新证据全部在 N1，
所以本轮无需为了版本号修改 APK。

### 已纳入的真机事实

- 银河奇异果 `com.gitvdemo.video`：
  - 首页与播放器 Activity 可区分；
  - 正常播放为 `PlayerActivity`；
  - 暂停时 Activity 仍为 `PlayerActivity`；
  - `audio_active=1` 在暂停时仍可能持续，因此不能作为暂停否决条件。
- 腾讯极光 `com.ktcp.video`：
  - `HomeSingleTaskActivity` 在真实播放和暂停中都会出现；
  - 因此 v0.2.7 明确禁止把该 Activity 直接当成 `app_home` 或 `paused`。
- 免费低码率播放存在很低 PPS 窗口；`idle_overlap` 只代表网络重叠区域，**永远不能单独触发 paused**。

### v0.2.7 规则

银河 `PlayerActivity` 下：

1. `bursty_pause >= 75` 或 `high_ratio_pause >= 90` 才算正向暂停证据；
2. 必须连续 **3 个新的 Agent report** 才进入 `combined_state=paused`；
3. 重复读取同一 report 不增加 streak；
4. 一旦出现明确当前播放证据（network shadow=playing，或 Adaptive clear_current / 当前 PPS 超 active_floor），
   立即退出暂停并进入 `playing`，不等待对称的 3 窗；
5. 暂停确认后允许 1 个缺失 hint 窗口的 temporal hold，第二个缺失窗口回到 unknown；
6. Agent 进程重启后首个 report 清空 pause streak，不跨进程继承播放器时序置信度；
7. `idle_overlap` 即使持续低 PPS，也始终保持 `unknown`，这是 576p/720p P0 防漏计门禁。

### 数据与隔离

- temporal fusion 状态只写 `/var/run/tvguard-agent-bridge/fusion.state`；
- Shadow Soak 升级为 RAM-only `soak-v3.csv`，记录 Adaptive pause hint、P50/P90、active floor、
  combined_state、candidate、fusion streak、report sequence 与新鲜度；
- 文件仍有固定行数上限，重启即清空；
- 不读取或修改 `USED_S`、`billing_state`、奖励、`TVG_GATE` 或防火墙；
- bridge 仍通过 CI 隔离门禁，禁止覆盖现有 smart-billing core。

### 真机验收

v0.2.7 安装后先只观察银河奇异果：

- 正常低码率播放：不得进入 `paused`；
- 暂停：预期先出现 `pause_candidate_warming`，连续证据后变为
  `combined_state=paused / paused_confirmed_temporal`；
- 恢复播放：明确播放证据出现后应快速切回 `playing`；
- App 首页与系统首页分别显示 `app_home` / `system_home`；
- 整个过程 `billing_effect=none`。

银河通过后，再单独为腾讯共享 Activity 建立可靠 discriminator；在此之前腾讯保持 conservative unknown，
不为了“凑齐四状态”制造假确定性。


## v0.2.7-2 · 无打扰观察与回归矩阵

0.2.7-2 不改变 0.2.7 的状态判定阈值，也不接入正式计费。它只增强可验证性：

- 新增 `/usr/libexec/tvguard-agent-bridge-report summary`，直接汇总 RAM-only `soak-v3.csv`；
- summary 只统计已有 RAM 观察，不主动唤醒电视、不要求 ADB、不写闪存；
- 输出 fresh/repeated/stale 数量，以及 playing/paused/app_home/system_home/unknown 分布；
- 单独统计 pause warming / confirmed / hold、idle_overlap unresolved、Tencent shared Activity unresolved、Agent restart reset；
- 固化两组已观察到的芒果 576p 低码率 PPS 序列，保证它们在未验证 Activity 语义下永远不能被误判成 paused；
- 固化银河低码率 PlayerActivity + idle_overlap 不累计 pause streak；
- 固化腾讯 HomeSingleTaskActivity 即使出现 high_ratio_pause 也保持 unknown。

因此孩子正常看电视期间不需要做任何人工标注。等方便时可以先看：

```sh
/usr/libexec/tvguard-agent-bridge-report summary
```

它只能作为“自然运行观察摘要”，不能替代有明确 App / 清晰度 / 暂停时点的人工真机验收。


### 0.2.7-2 保守收紧：银河首页只认已验证 Activity

真机目前只验证了 `com.gala.video.app.epg.HomeActivity` 是银河奇异果首页。
因此 0.2.7-2 不再把 `com.gitvdemo.video` 包内所有“非 PlayerActivity”一概标成 `app_home`：

- 精确 `HomeActivity` → `app_home`
- `PlayerActivity` → 进入播放/暂停融合
- 其他详情、搜索、分类等未验证 Activity → `unknown / galaxy_nonplayer_activity_unresolved`

这是单向保守化：宁可暂时 unknown，也不把未验证页面错误当成首页。
