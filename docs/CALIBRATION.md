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

已标注样本保存在 `/etc/tvguard/calibration-v3.csv`，格式：

```text
timestamp,session_id,scene,app,pps,tcp_pps,udp_pps,outbound_bytes_per_second
```

这份 CSV 仅为网络聚合统计，不记录视频内容、账号或观看画面。

### 可选的方向性 v4 数据

当前开发候选还预留了 `/etc/tvguard/calibration-v4.csv`。它**不会因为升级自动出现**，只有同时满足以下条件才写入：

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

最近一次人类可读结果写入 `/etc/tvguard/learning-last.txt`；机器可读会话摘要追加到 `/etc/tvguard/learning-sessions.csv`。这些会话摘要是后续 Adaptive Engine Phase 1 建立滚动窗口画像的输入，不是新的固定阈值表。

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

