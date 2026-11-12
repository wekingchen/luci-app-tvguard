# TVGuard Agent + N1 Bridge · 双端联动 0.2.8（通用上下文 + Home-only 计时提示）

## 为何不把旧的 TVGuard 全量 IPK 重打包？

当前 N1 真机主包基线为 `v0.1.13-r21-settings-dual-bark`，bridge 为 `0.2.8-r4`。主包与 bridge 分开升级；bridge 不覆盖核心控制器、LuCI 或防火墙文件。

当前 companion 为 **`tvguard-agent-bridge_0.2.8-4_all.ipk`**。它安装独立 CGI、融合/观察脚本、Home-only billing hint 和一次生成的配对密钥；不覆盖 `tvguardctl`、`tvguardd`、LuCI、iptables、防火墙、代理、配额和奖励。billing hint 本身只返回状态，不写额度；r17 之后的 Home-only 核心会消费其中 `system_home/app_home` 两种免计结果；当前真机基线为 r21。

## 链路与安全

Agent → N1 的 OpenWrt uhttpd `/cgi-bin/tvguard-agent`（POST，固定最小协议）
- 仅接受来自 UCI `tvguard.main.ip` 的请求；单次请求最多 512 字节；需要 32 字节十六进制配对码。
- 只保存最新一份包名、Activity、Android 音频活动提示、亮屏提示及服务器接收时间到 `/var/run/tvguard-agent-bridge/latest`（RAM），**无历史日志、无闪存持续写入**。
- 单次 HTTP 200 OK 为收到；3xx/4xx/5xx 不计成功。旧数据超过 35 秒直接作为失效。
- 配对码在 `/etc/tvguard/agent-bridge.key` 中生成一次，600 权限。电视首次配置服务器 URL 与配对码需要在私有首选项落盘一次；不会保存流量历史。
- **明文 LAN HTTP 的 token 不抵抗主动局域网攻击。** r17 仅在“家庭 LAN 可信”的当前威胁模型下，让它承担 `system_home/app_home` 两种窄免计提示；它不获得封禁、防火墙或奖励权限。若需要抵抗 LAN 内主动攻击，后续应增加消息认证与重放保护。
- v0.2.7 新增 `combined_state=playing|paused|app_home|system_home|unknown` 与详细 `combined_candidate`。其中只有已在真机验证 Activity 语义的场景才允许进入四状态；`PlayerActivity`、`AudioManager.isMusicActive()` 或单个 PPS 窗口单独都**不能证明视频真的播放或暂停**；不修改使用额度。
- 如果电视后台被清理、断网、失权限，发送停止，N1 35 秒后自动标记 stale。

## N1 操作（无需修改原 IPK）

1. 单独安装 companion IPK：`opkg install /tmp/tvguard-agent-bridge_0.2.8-4_all.ipk`。配套正式 Home-only 计时要求 r17 或更新核心；当前真机使用 r21。
2. 确保 N1 当前 uhttpd 在 LAN 监听，且已启用 CGI prefix `/cgi-bin`。
3. 查看一次性 token：`/usr/libexec/tvguard-agent-bridge-report pairing`。
4. 记下 N1 的 LAN IP。电视 Agent UI 填写 `http://N1_LAN_IP/cgi-bin/tvguard-agent` 与配对码，保存后启动监测。
5. 测试电视视频首页、正常播放、暂停、桌面，N1 执行 `/usr/libexec/tvguard-agent-bridge-report status`；若 HTTP 连通将看到 `agent=online` 和包名/音频提示、Router PPS 及候选。
6. 失联后 `agent=stale` 或 `agent=missing`；Home-only 核心会 fail-closed：有网络活动时照常扣时，不会因为 Agent 失联获得免费时间。

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


## v0.2.8 · 通用媒体上下文学习（取代按 App 写规则）

v0.2.7 中为快速验证真机证据，曾出现 Galaxy / Tencent / Mango 的保守专用分支。
这些分支只作为历史验证阶段保留在文档，不再代表当前架构。**v0.2.8 的 fusion
源码禁止出现任何视频 App 包名或品牌专用 candidate。**

当前统一规则：

1. Agent 只提供当前 package / Activity / audio / screen，不判断“这是不是视频 App”；
2. N1 原 Adaptive Engine 继续提供 PPS、shadow、pause_hint、P50/P90、active_floor；
3. 当任意前台 package/activity 第一次出现明确强播放证据时，fusion 在 RAM 中把它记为
   **learned media context**；
4. 之后同一个上下文出现连续 strong pause evidence，才允许进入 paused；
5. 同一个已学习媒体 package 切到不同 Activity，若持续低流量 + audio off，则归入
   app-side non-playing UI（对外仍映射为 app_home）；
6. learned media context 内出现 stable_low / idle_overlap 永远不能单独判 paused，
   保护 576p/720p 低码率连续播放；
7. 从未出现过强播放证据的 package，即使 pause_hint 很高，也不能获得 paused/app_home
   这种免计候选；
8. Agent 重启只清 hysteresis，不清 N1 RAM 中已经由强播放证据学到的媒体上下文。

因此优酷、咪咕、小米视频或未来新增视频 App 不需要增加 package 分支。首次出现明确播放时，
系统会自动学习它的媒体上下文；人工样本用于验证“共性模型是否成立”，而不是维护 App 白名单。

### 通用性 CI

测试使用匿名包名 `com.example.*`，但喂入已经从真机采到的低码率流量形态：

- 576p UDP-heavy burst 序列；
- 576p TCP-heavy 中低 PPS 序列；
- shared Activity 先强播放、后暂停；
- learned package 不同 Activity 的非播放界面；
- never-learned package 的高 pause_hint。

CI 还明确禁止 fusion 源码出现
`com.gitvdemo.video`、`com.ktcp.video`、`com.hunantv.license`、
`com.youku.tv` 等视频 App 包名。

v0.2.8 仍为 `billing_effect=none`。通用模型真机通过前，不接管 USED_S。


## v0.2.8-r2 · 576p 周期突发保护（P0）

2026-11-11 真机在**芒果 576p 正常连续播放**时，v0.2.8-1 多次错误进入
`paused_confirmed_learned_context`。这不是芒果专有问题，而是低码率流媒体的共同形态：

- 大部分窗口只有约 18–80 PPS；
- 每隔约 30–60 秒出现一次 125–346 PPS 的明确播放突发；
- 旧 pause prototype 会把低谷识别成 `high_ratio_pause` / `bursty_pause`；
- 旧 fusion 连续 3 个 pause hint 就授予 paused，于是形成
  `paused → playing → paused → playing` 的假振荡。

r2 不增加 App 特判，而是在同一 learned media context 内学习**强播放突发节奏**：

1. 首次明确 strong-play 后，先给 45 秒 bootstrap guard；
2. 若随后再次出现 strong-play，且间隔 10–90 秒，则把该间隔学习为 burst cadence；
3. 保存同一上下文内已观察到的最大 burst gap；
4. guard window = `max_gap + 20s`，下限 45 秒，上限 90 秒；
5. guard 内的 `high_ratio_pause` / `bursty_pause` 不累计 pause streak，
   输出 `recent_play_burst_guard`；
6. 真正超过已学习突发周期仍没有新 strong-play 后，暂停证据才重新获得累计资格；
7. Activity/package 一旦变化，burst cadence 立即清零，不跨上下文继承。

该策略明确偏向 P0：宁可短时间保持 unknown/继续正式计时，也不能把真实 576p 播放误判为 paused/free。
当前 bridge 仍为 `billing_effect=none`，所以这只是 Shadow 修复，不直接改变 USED_S。

### 真实回归样本

新增 `test_real_576p_burst_guard.py`，使用用户明确标注为“正常播放”的真实连续序列，
但将 package/activity 匿名化。序列覆盖：

- 18/20/22/25/31 PPS 等低谷；
- 125/174/180/198/220/226/305/346 PPS 周期突发；
- `high_ratio_pause=95`；
- `bursty_pause=75`；
- `active_votes` / `clear_current` / `overlap` 交替。

整段 trace 的硬门禁是：**不得出现任何 `combined_state=paused`。**


## v0.2.8-r3 · Home-only 正式计时提示

暂停识别不再承担正式免计时职责。新增 `tvguard-agent-billing-hint`，其合同只有三类结果：

- `free system_home`
- `free app_home`
- 其他任何情况均为 `charge <state>`

其中 `paused` 即使在 Shadow Fusion 中被确认，也仍返回 `charge paused`。Agent 丢失、超过 20 秒、输入异常或 fusion 不可用均返回 `charge unknown`。该 helper 本身不修改额度或防火墙；只有 r17 核心显式消费上述 Home-only 结果。


## v0.2.8-r4 · 防止 App 首页加载突发污染播放 Activity

真机验证发现：已学习媒体 App 从播放器切回首页后，首页启动阶段的一次强网络突发会被旧逻辑立即当成“新的播放 Activity”，从而覆盖原本正确的播放上下文。之后即使首页持续低流量，也因为 Activity 已被错误标成播放上下文而无法进入 `app_home`。

r4 采用通用保护，不增加任何 App/包名特判：

1. 第一次学习某个媒体 App 的播放 Activity 规则不变；
2. 同一个已学习媒体 App 切到不同 Activity 后，单次 strong-play 只进入 `media_context_switch_play_warming`；
3. 新 Activity 必须连续获得 3 次新的强播放确认，才允许晋升为新的播放 Activity；
4. 如果加载突发后转为持续低流量 + audio off，则清除切换候选，并按原逻辑累计 3 个新报告确认 `app_home`；
5. 该保护只影响 RAM-only Fusion 学习，不改变 firewall、奖励或其他核心策略。

升级到 r4 会因 fusion state schema v3→v4 自动丢弃旧的 RAM 学习状态，避免把已经污染的 Activity 继续带入新模型；重启或升级后需要一次真实播放重新建立媒体上下文。


### r4 真机验收结果（2026-11-12）

r4 已在 N1 + 小米电视完成正式链路验证：

- 正常播放重新学习到 `com.mgtv.tv.vod.activity.VodDynamicActivity`，fusion schema v4 正确持久在 RAM；
- 回 App 首页后 `com.mgtv.tv.launcher.ChannelHomeActivity` 未覆盖 learned playback Activity，并稳定确认 `app_home`；
- 核心输出 `billing_state=idle_verified / idle_reason=app_home`；
- 儿童模式 App 首页 30 秒累计时间不增长；
- 正常播放和暂停均保持 `charge`；
- 系统首页确认 `system_home` 后 30 秒累计时间不增长。

这证明 r4 的 Activity-switch guard 已解决首页首轮加载突发污染 learned media Activity 的真机问题。
