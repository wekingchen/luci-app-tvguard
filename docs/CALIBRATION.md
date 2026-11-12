# TV Guard · 通用网络状态诊断与校准

> **日常使用无需识别或逐个登记视频 App。** 本文的标注只用于开发人员验证通用识别逻辑，不是使用 TV Guard 的前置步骤。

## 目标及重要边界

TV Guard 管理的是 **小米电视这台设备**，而不是腾讯、爱奇艺、芒果 TV 这些固定应用。未来安装其他播放器，不应该要求家长针对它重新训练。

1. 电视 IPv4 流量经过 N1：统计网络活动，不区分应用。
2. 系统首页、视频播放、暂停、App 首页：尝试从通用网络行为中寻找可复现的证据。
3. 如果网络证据无法区分状态：显示 `unknown`，不假装已识别为闲置。
4. **只有网络证据并不能可靠证明电视前台 UI 或已暂停**。v0.1.12 因此保持 *shadow-only*；v0.1.13 只把满足更严格门槛的“系统首页 / 通用闲置”提示接入儿童计时，并增加 30 秒连续确认。未知或播放提示始终计时，防火墙控制本身不读取这些识别结果。

目前的 `raw PREROUTING -s 192.168.101.76` 仅统计电视**发出的、实际经过 N1 的 IPv4 包**；它不等于视频下载带宽或完整双向流量。电视可能绕开 N1。N1 执行 `ip route get 192.168.101.76` 只能说明 N1 如何到电视，**不能证明电视外出必经 N1**。

## 实测与反例（2026-11-08）

已获得腾讯极光一组播放、暂停、应用首页样本，以及小米系统首页 3 组：

| 场景 | 总 PPS 范围 | 说明 |
| --- | ---: | --- |
| 腾讯极光正常播放 | 91～309 | TCP 多次只有 1～4 PPS |
| 腾讯极光暂停 | 65～157 | 出站 UDP 仍大量存在 |
| 腾讯极光应用首页 | 14～71 | 最后仍有 71 PPS 突发 |
| 小米系统首页 | 约 7～10 | 三次平均较稳定 |

**播放和暂停区间在 91～157 PPS 重叠；暂停和首页也会重叠。** 不能使用“低于某个 PPS 就暂停免计时”的规则。

这些值只是这台电视、此网络路径和这些视频内容下的观测，绝不是所有 App 的标准参数。

## 当前通用影子识别引擎（开发分支）

`root/usr/libexec/tvguard-shadow` 已不再按每个 App 分别匹配原型，而是汇总不同播放器的状态特征：

- 运行时**不接受 App 名称参数**；只看设备出站 PPS、TCP PPS、UDP PPS、出站字节速率。
- 样本标签中的 App 名称**只为验证泛化能力**。正常使用无需人工填写。
- 为避免仅从一个播放器过拟合，播放、暂停、应用首页三类每类至少需要 3 个独立校准会话、18 个采样窗口，并包含至少 **2 个明确不同的应用**。`general` 和 `other` 标签不能伪装成两个独立的 App 证据。
- 当前窗口必须接近已观测范围，并且任何可免计时结果都必须与播放范围有明确分离；与播放重叠时输出 `unknown`。
- **系统首页**是电视本身的设备级状态：至少 3 个独立会话、18 个样本；播放只作为“不能误免正在播放”的负参考，因此至少 1 个已标注播放会话、6 个窗口即可用于重叠排除。只有当前首页特征与播放参考明确分离时才输出 `system_home`，不再要求播放也达到 3 会话 / 18 样本。
- **App 首页**增加本机保守兜底：只要已有至少 1 个明确人工标注会话、10 个窗口，当前四维特征落在该 App 首页样本包络内，并与播放参考明确分离，就可输出 `app_home` 并进入 30 秒连续确认。它只复用“这台电视已经验证过的首页特征”，不会把任意低 PPS 当作首页；不匹配的新 App 仍为 `unknown` 并计时。
- 若同一实时窗口同时命中两个已经验证的闲置包络（例如 App 首页流量继续衰减后也落入系统首页范围），分类器输出中性 `idle`，不强行声称具体前台页面。计时状态把 `system_home / app_home / idle / paused` 视为同一个“可信闲置族”，在这些标签之间切换不会重置 30 秒确认，也不会短暂恢复扣时；只有 `unknown / playing` 才立即恢复计时。
- 系统首页不再要求 PPS/TCP/UDP/bytes 四维**全部**同时落入历史矩形范围：真机已观察到电视停在同一首页时会有后台 TCP 或字节突发。新版要求 PPS 本身仍处于系统首页低活跃包络（历史范围加小幅容差），四维至少 3/4 命中，并继续要求与播放参考明确分离。这样允许单一后台突发，但不会把播放级 PPS 当作系统首页。
- **暂停与 App 首页的跨应用通用闲置**仍保持更高门槛：要输出通用 `idle`，播放、暂停、App 首页三类均需至少 2 个不同视频 App 的跨应用证据。由于当前暂停样本与播放范围存在明显重叠，暂停不会因为单一会话而直接免计时。
- **播放标签与免计时采用不同安全级别**：`playing` 只是显示/诊断标签，本身不会改变 `USED_S` 或 gate，因此只需至少 1 个已标注播放会话（≥6 窗口）作为本机参考；但当前样本仍必须明确排除已知 App 首页、系统首页和暂停包络。若处于播放/暂停重叠区则保持 `unknown` 并继续计时；若活跃度明显高于所有闲置/暂停上界，可在已标注播放范围上做**有上界的**合理外推后显示 `playing`，超出该动态上界的异常流量仍返回 `unknown`。
- `sleep` 不作为网络分类器的可靠标签；零流量可能来自电视绕过 N1、路由中断或长时间缓冲，仍由独立静默逻辑处理。
- v0.1.13 中 `system_home` / `idle` 只有连续约 30 秒才会令 `billing_state=idle_verified` 并暂停 `USED_S`；`unknown` / `playing` 立即计时。

**这些条件是保守的实验门槛，而非要求用户每个应用都做三轮采样。** 现有数据中，仅腾讯极光三种状态采集齐全，跨应用泛化尚未得到验证。当前显示 `unknown` 属于预期。

## 如何验证真正的通用性

r8 起已标注样本正式保存在 `/mnt/mmcblk2p4/tvguard/calibration-v3.csv`（`/etc/tvguard` 仅可能是兼容软链接），格式：

```text
timestamp,session_id,scene,app,pps,tcp_pps,udp_pps,outbound_bytes_per_second
```

这份 CSV 仅为网络聚合统计，不记录视频内容、账号或观看画面。

### 可选的方向性 v4 数据

当前开发候选还预留了 `/mnt/mmcblk2p4/tvguard/calibration-v4.csv`。它**不会因为升级自动出现**，只有同时满足以下条件才写入：

- 家长正在进行明确状态的 120 秒手工标注；
- `observe_reply=1` 已由管理员在真实 N1 上单独启用；
- 两个回程观测点都存在，且本轮已经建立有效的计数器差值（不是 warming-up / unavailable）。

v4 每行 12 列：

```text
timestamp,session_id,scene,app,
tx_pps,tx_tcp_pps,tx_udp_pps,tx_bytes_per_second,
reply_prerouting_pps,reply_prerouting_bytes_per_second,
reply_local_pps,reply_local_bytes_per_second
```

如果回程观测关闭或不可用，**不会写全 0 的 v4 假样本**。v4 当前只作为下一阶段判断“双向数据是否真能提高通用识别”的实验数据；现有 `USED_S`、`ACTIVITY`、`tvguard-shadow` 和防火墙都不读取它。

### Agent 联合 v5 数据

v0.1.14-r3 起，四状态人工学习在继续写 `calibration-v3.csv` 的同时，新增 `/mnt/mmcblk2p4/tvguard/calibration-v5.csv`。v5 不需要开启 `observe_reply`，直接复用电视 Agent 已经每约 10 秒送到 N1 的 latest-only 上下文。

每行 14 列：

```text
epoch,session_id,ground_truth,agent_state,agent_age_seconds,
package,activity,audio_active,screen_on,report_seq,
pps,tcp_pps,udp_pps,outbound_bytes_per_second
```

- `ground_truth` 仍由家长在学习中心选择，只有 `system_home / app_home / playing / paused` 四种；
- `agent_state=fresh` 只在 N1 接收时间不超过 20 秒且格式有效时成立；stale/missing/invalid 不会沿用最后一次 package/Activity 伪装成当前上下文；
- package/Activity 用于自动区分不同视频 App 和页面上下文；audio/screen 只作为辅助证据，不能单独证明播放或暂停；
- `calibration-v3.csv` 继续作为现有 Adaptive/Shadow 的兼容网络数据源，历史模型不会因 r3 升级失效；
- `tvguard-learn` 会从 v5 计算 Agent 覆盖率、主 package/Activity 稳定度、音频/屏幕比例和前台切换次数；Agent 覆盖不足时明确降级为 network-only，而不是伪造联合高可信。r6 起这些联合统计还会追加进入 `learning-sessions.csv`（原 18 列保持不变，后追加 11 个 Agent 特征），因此高可信人工会话终于可以被运行时 Fusion 复用。

v5 同样由 `tvguard-data` 管理：持久分区不可用时只写 `/var/run/tvguard-data`，挂载恢复后只合并中断期间的新记录。电视端仍然不保存学习历史。


将 v3 从 N1 拷到电脑后，使用：

```sh
python3 scripts/evaluate-generalization.py calibration-v3.csv
```

此工具会**留出整个播放器的所有样本**，只从其他应用学习，再测试从未进入训练集的播放器（leave-one-app-out）。只有至少 3 个具有完整播放/暂停/首页标注的独立视频 App 时才可能执行这种验证；目前不足时明确输出 `insufficient_cross_app_validation`，不会伪造准确率。

另有 `scripts/evaluate-calibration.py` 用于检查单应用内的状态分离度，仅作辅助分析，不能证明泛化。

即使未来验证了特定 App 组合上的识别表现，**也不代表对所有未知 App 都可靠**。真正的自动免计时需要更强的独立证据，例如经实际验证的双向连接特征和路径完整性；当前暂不启用。

## 操作原则

- 不需要继续逐个采集电视里的所有 App。
- 需要时只选择**少数具有不同网络行为的代表性应用**做留出验证，或者验证某个明确出现误判的新场景。
- 不强迫安装 `tcpdump`、`conntrack`、电视端软件或智能插座。
- 先做只读观测；在确认路由与代理兼容之前，不改 N1 的默认网关、转发、SSR 或防火墙策略。

## v0.1.13-r2：计费状态与场景标签解耦

真机已经证明 App 首页和系统首页的网络特征会重叠、漂移，单靠出站 PPS/TCP/UDP/bytes 不能诚实地长期区分具体前台页面。因此 r2 起：

- **计费层只关心可信闲置 / 明确活跃 / 未知**，不再依赖“系统首页”和“App 首页”这两个具体名字。
- 当系统首页和 App 首页的证据同时存在时，匹配任一可信低活跃包络统一输出中性 `idle`；具体页面名称只保留在人工校准数据中，不再作为日常状态的强断言。
- 已经达到 `idle_verified` 后，若下一帧只是 `low_traffic + unknown`，进入最多 20 秒的 `idle_grace`，保持暂停计时；若在 20 秒内重新获得 idle 证据则无缝继续。
- `playing`、中/高活跃 `unknown`、或低活跃 unknown 超过 20 秒都会立即/最终恢复 charge。这样把首页后台心跳造成的单帧抖动与真正开始观看区分开。
- 这个保持窗口是**有界滞回**，不是“低 PPS 永久免费”。最坏情况下只会在已经确认闲置之后给一次短暂的 20 秒过渡容差。

完整的自适应在线学习（时间窗口统计、近期样本加权、人工纠错、双向流量特征）将作为后续识别引擎重构方向；r2 先停止继续堆具体页面阈值。
## v0.1.13-r3：四状态学习中心

新的人工学习入口只保留四个 ground-truth 标签：

1. `system_home`：电视系统首页
2. `app_home`：视频 App 首页
3. `playing`：视频正常播放
4. `paused`：视频暂停

用户选择标签后只需再选择 60 / 180 / 300 秒采集时间。控制器按 10 秒节奏保存原始窗口，到时自动结束，并调用 `tvguard-learn` 分析该会话。

分析器不会修改计时或防火墙。它将会话汇总为：
- 样本完整度；
- PPS P10 / median / P90；
- TCP、UDP median；
- BPS median / P90；
- PPS 相对跨度与波动等级；
- 会话质量（high / medium / low）。

最近一次人类可读结果写入 `/mnt/mmcblk2p4/tvguard/learning-last.txt`；机器可读会话摘要追加到 `/mnt/mmcblk2p4/tvguard/learning-sessions.csv`。这些会话摘要是 Adaptive Engine 建立滚动窗口画像的输入，不是新的固定阈值表。持久分区临时不可用时只使用 `/var/run/tvguard-data` RAM 兜底，不向 overlay `/etc` 建立第二套数据库。

## Phase 2 方向：暂停画像与双向特征

Phase 1 真机确认 idle/active 稳定后，Phase 2 聚焦最难的 `paused`：

- 继续保留 `paused` 为独立人工 ground-truth 标签；
- 暂停画像不直接合并进 idle；
- 优先增加滚动窗口中的波动特征（burst rate、P50/P90 gap、TCP/UDP 比例、bytes-per-packet）；
- `observe_reply=0` 仍保持默认，双向流量只在显式启用的实验采集里写入 `calibration-v4.csv`；
- 在证明 RX 特征能稳定提高 paused 与 playing 的分离度之前，reply observer 不参与正式计费；
- 只有完成多会话真机验证后，才考虑让高置信 paused 进入免计时集合。



## Phase 2A：暂停不是单一画像

暂停人工标签仍只有一个 `paused` ground truth，但 Adaptive Engine 不再假设所有暂停行为服从一个分布。每个 completed+high paused 学习会话先形成自己的 session profile，再根据相对 idle/playing 的位置归入诊断原型。

当前原型语义：
- `idle_overlap`：P50/P90 均落在学习出的 idle 安全范围。该行为可能是暂停，也可能是首页，因此只描述“重叠”，不强行识别具体页面。
- `bursty_pause`：P50 仍低，但 P90 超出 idle 安全范围，表现为低基线 + 后台突发。
- `high_ratio_pause`：session PPS 中位已离开普通 idle，但 BPS/PPS 中位与 trusted playing 的 B/P P90 有强分离。运行时使用最近约 60 秒的 rolling B/P median 作为辅助证据。

B/P 这里只是同一 N1 计数口径下的统计特征，不解释为真实物理包大小；GSO/GRO、计数位置等都会影响绝对值。因此阈值必须从本机高质量 playing/paused 数据动态学习，不写死通用常数。

Phase 2A 只输出 pause hint、score、rolling B/P P50/P90、active-window count 与 trend；这些字段不参与 `USED_S` 或 gate。若 TX 特征后续无法稳定分离高流量暂停和真实播放，再进入 Phase 2B 双向流量实验。



## Phase 2A 过渡否决：播放证据优先于暂停线索

r5 真机证明：rolling B/P 很高并不等价于 paused。腾讯从暂停恢复播放约 60 秒后，B/P P50/P90 仍可达到 2439/5022，但 Phase 1 已给出 active 100%，当前 PPS 也超过 learned active floor。

因此 high_ratio_pause 必须服从更高优先级的播放证据：
- clear-current active（当前 PPS >= active floor）直接 veto；
- 最近窗口呈强上升趋势时 veto；
- pause hint 永远不能覆盖 Phase 1 active。

这些规则的目的是避免把“播放恢复后的缓存/高吞吐阶段”误标为暂停。它们不是新的免计时条件。



## r6 真机结论：B/P 是上下文特征，不是 paused 绝对判据

r6 进一步证明：正常播放也可能出现极高 rolling B/P（例如 P50/P90 3086/5246 或 4503/5290）。因此 B/P 只能与 learned active floor、rolling trend、active-window count 等共同使用，不能单独定义 paused。

当前 high_ratio_pause 语义应理解为：
- paused-like evidence：高；
- billing authority：无；
- 若出现 clear-active PPS 或明显 rising trend，则 playback evidence 优先并 veto pause hint；
- 若 Phase 1 为 active，则计时继续，不因 pause hint 改变。

这套优先级已通过 N1 的 play → pause → play 真机序列验证。



## 存储约束

校准和学习数据属于长期模型输入，但不能以无限日志形式保存。当前 append-only 持久数据总设计预算为 1 MiB；超限时只保留最近记录。

Adaptive Engine 的实时 rolling window 位于 `/var/run`，不是持久学习库。未来 Shadow Soak 也必须遵循“高频原始窗口放 volatile ring、持久层只留有界摘要”的原则。磁盘容量不能作为提高模型精度的代价。



## r8 持久数据位置

正式学习/状态数据根固定为 `/mnt/mmcblk2p4/tvguard`。升级 r8 时会从旧 `/etc/tvguard` 一次性迁移已知文件；迁移经过目标存在和字节数校验后才清理旧文件。

如果 `/mnt/mmcblk2p4` 暂时未挂载，采集与运行态只写 `/var/run/tvguard-data`。挂载恢复后仅合并中断期间新增的数据，旧库种入 RAM 的前缀不会重复写回，因此不会因为挂载抖动人为放大学习样本权重。

原始长期 Shadow Soak 仍禁止无界持久写入；高频窗口必须优先使用 volatile ring，持久摘要继续受 1 MiB 总设计预算约束。


## Shadow Soak：长期观察阶段

Shadow Soak 不产生新的模型权重，也不改变 paused/playing 分类边界。它只用于回答两个问题：

1. 正常日常播放中，`high_ratio_pause` 会不会无人工干预地出现；
2. 出现时持续多久、Adaptive 是 active 还是 ambiguous，以及恢复播放后是否能及时退出。

高频原始窗口只保留在 `/var/run` 的有界环中。持久层只保存累计计数与当前/最近候选摘要，避免为了识别精度持续写 eMMC。只有当 Soak 长期数据证明假阳性足够低，才讨论下一阶段 `paused_verified`；在此之前 pause hint 始终没有 billing authority。



## r11：高 B/P 必须视为重叠特征

芒果 TV 576p 正常播放已经证明 high_ratio_pause 会在真实播放中长时间、多次触发，因此 Phase 2A 的“高流量暂停候选”语义过强。

从 r11 起：
- `high_ratio_pause` 内部字段暂保留兼容，但产品语义改为“高 B/P 重叠行为”；
- `adaptive_pause_score` 只是规则持续满足的规则分，不解释为暂停概率；
- 不再把 B/P 单独或结合较低 PPS 当作 paused_verified 依据；
- Shadow Soak v2 额外采集 TCP PPS、UDP PPS 和 BPS，继续寻找协议组成、吞吐与时间结构的稳定差异。

当前一个值得验证但尚未成立的假设：已知腾讯高吞吐暂停样本多为 UDP 主导，而芒果 576p 假阳性窗口至少观察到明显 TCP 成分。该假设只作为 Soak v2 的研究方向，未进入 billing classifier。



## v0.1.14-r2：只有“当前明确确认暂停”获得免计时权限

r2 根据当前产品策略，把已有 Fusion 的严格暂停确认态接入正式计时，但**不**开放泛化 idle/pause hint 权限。

允许免计时的暂停必须同时满足：

1. 当前 package/Activity 已经由强播放证据学习为媒体上下文；
2. 当前不处于 recent-play burst guard；
3. 连续 3 个新的 Agent report 满足 Fusion 的强暂停证据；
4. Fusion 当前 candidate 必须精确为 `paused_confirmed_learned_context`。

只有这个 candidate 返回 `free paused`，核心记录为 `billing_state=idle_verified / idle_reason=paused`。

以下全部继续计时并继续作为学习/研究证据：

- `paused_temporal_hold`；
- `high_ratio_pause / bursty_pause / idle_overlap`；
- `stable_low` 或 Adaptive idle；
- 单独的低 PPS、高 B/P、audio off；
- `unknown / ambiguous`；
- Agent stale / missing / invalid。

这不是把“暂停画像”整体升格为正式计费依据，而是只给已有严格确认态一个窄授权。后续暂停研究继续用于扩大可确认覆盖面、减少 unknown，并验证不同 App / 码率下的假阳性；任何新状态都不能自动继承免计时权限。

## v0.1.14-r3：Agent-assisted Adaptive Learning

r3 重新定义“选择电视当前状态 → 学习”的职责：用户只负责提供**人工真值**，设备上下文由 Agent 自动补齐。

当前流程：

1. 在 LuCI 选择系统首页、App 首页、正常播放或视频暂停；
2. 页面同时显示当前 Agent 是否 fresh，以及自动识别到的 package / Activity / audio / screen；
3. 开始学习后，每个有效网络窗口同时写 v3 与 v5；
4. Agent 临时失联不会中断会话，网络样本照常保留，但联合质量自动降级；
5. 会话结束后自动报告 Agent 覆盖率、主 App、主页面、上下文稳定度和网络统计；
6. `scripts/evaluate-generalization.py` 可直接读取 v5，按真实 package 做 leave-one-app-out，避免再依赖手工的腾讯/爱奇艺/芒果标签。

这一阶段**没有**把 package/Activity/audio/screen 变成新的免计时规则。正式计时仍只接受既有 Home-only 与 `paused_confirmed_learned_context` 的窄授权；其他状态继续计时、继续学习。


## v0.1.14-r6：成对人工学习的 Agent 音频画像

r6 针对真机已确认的关键反例补齐最后一段学习链：同一个播放器 Activity 在“正在播放”和“暂停”时可能完全不变，而且暂停后仍会出现数百 PPS 的下载突发。因此网络 active 不能永远覆盖人工学习出来的暂停上下文。

运行时不会使用任何视频 App 白名单。只有同时满足以下条件，exact package+Activity 才获得 learned-audio profile：

1. 至少一个 completed + high 的 playing 人工会话；
2. 至少一个 completed + high 的 paused 人工会话；
3. 两类会话的 Agent joint quality 都为 high，dominant package/Activity 稳定度均 ≥75%，屏幕亮比例 ≥90%；
4. 两类会话必须是同一 exact package+Activity；
5. playing 平均 audio-active 比例 ≥70%，paused ≤30%，两者差值至少 50 个百分点；
6. 若同一 exact context 还出现高可信 app_home 会话，则禁用该音频画像，避免把共享 Activity 误当播放器专属页面。

满足后：
- 当前 exact context + audio=1：直接确认 playing，即使 PPS 暂时很低，也继续计时，优先保护 576p/720p；
- 当前 exact context + audio=0：r7 起连续 2 个新的 Agent report 后确认 paused；第 1 个仍是 unknown/charge。旧的网络 pause-evidence 路径仍保持 3 个 report，不一起放宽；
- paused 已确认后，即使后台预取让 PPS 突然升高，也不能单凭网络 active 覆盖人工学习出的暂停状态；
- audio 恢复为 1 时立即退出 paused 并恢复 playing；
- Agent stale、package-only、unknown Activity、无成对高可信样本、音频分离不足时全部 fail-closed，继续沿用原来的保守 Fusion/计时路径。

2026-11-12 真机观察到芒果 TV 播放与暂停均处于同一 `VodDynamicActivity`，播放 audio=1、暂停 audio=0；暂停后一度出现 PPS≈198，随后降至 51–98，又可再次升到 349。该反例正是 r6 不再允许“网络 active 无条件否决暂停”的原因，但上述包名/Activity 只记录在测试文档中，不进入决策白名单。


## v0.1.14-r7：learned-audio 暂停确认由 3 个心跳收紧到 2 个

r6 真机儿童模式已确认：正常播放 40 秒约 +43 秒，暂停确认后 40 秒 +0，恢复播放 40 秒约 +43 秒；但从按下暂停到正式免计仍多计约 32 秒。随后专门验证“静音但继续播放”：连续 5 个 Agent report 均保持 audio_active=1，Fusion 一直为 playing，未出现静音误判。

因此 r7 只对**已经存在成对高可信 playing/paused Agent 画像的 exact package+Activity**收紧确认：第 1 个 fresh audio=0 report 继续 charge，第 2 个 fresh audio=0 report 才进入 `paused_confirmed_learned_audio_context`。这样保留一个完整抗抖窗口，同时把典型暂停确认延迟从约 30 秒降到约 20 秒。没有 learned-audio profile 的旧网络暂停路径仍要求 3 个 fresh report。


## v0.1.15-r1：共享 exact context 的 generic nonplaying

腾讯极光真机揭示了一类与芒果不同的结构：playing、paused、app_home 三态都可能共享同一个 package+Activity。此时 exact context 本身不能区分状态，audio=0 也不能诚实地被叫做 paused，因为 app_home 同样是 audio=0。

2026-11-12 腾讯三轮 180 秒人工学习：

- playing：17/17 fresh，joint=high，package/Activity 稳定 100%，audio=100%，PPS P10/P50/P90=100/120/168；
- paused：17/17 fresh，joint=high，package/Activity 稳定 100%，audio=5%，PPS=37/49/73；
- app_home：16/16 fresh，joint=high，package/Activity 稳定 100%，audio=0%，PPS=17/24/40；
- 三态 exact context 相同：`com.ktcp.video / com.ktcp.video.activity.onepage.HomeSingleTaskActivity`；
- 静音继续播放的 5 个 fresh report 均保持 audio_active=1。

因此 r1 新增通用 Type-D profile，源码不使用上述真实包名。只有同一 exact context 同时拥有 completed+high+joint-high 的 playing、paused、app_home，且 playing 平均 audio>=70%、paused/app_home 均<=30%，playing 相对两者均至少分离 50 个百分点，才获得该画像。

运行时：
- audio=1 → `playing_confirmed_learned_nonplaying_profile`，即使 PPS 很低也继续计时；
- 第 1 个 fresh audio=0 → `nonplaying_audio_profile_warming`，继续 charge；
- 第 2 个 fresh audio=0 → `nonplaying_confirmed_learned_audio_context`，Fusion 输出诚实的 `nonplaying`，billing 返回 `free nonplaying`；
- 网络 active/high PPS 不能单独否决已经由三态人工学习建立的 nonplaying；
- audio 恢复为 1 立即回 playing/charge；
- stale/package-only/Activity unknown/三态样本不齐/音频分离不足全部 fail-closed。

网络 PPS 的 playing/paused/app_home 分层可以用于后续展示态细分，但当前**不参与 generic nonplaying 的免计授权**，避免把 App 专属网络阈值写死成计费规则。
