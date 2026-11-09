## v0.1.13-r10 Shadow Soak · 长期旁路观察

在 r6 已完成 play → pause → play 真机闭环后，r10 开始 Shadow Soak。目标不是立即让 paused 自动免计时，而是先证明高流量暂停候选在日常真实观看中的假阳性率足够低。

数据策略：
- 每个有效 tick 将 already-computed Adaptive telemetry 复制给 `tvguard-soak`；
- 原始 10 秒窗口只写 `/var/run/tvguard-soak-window.csv`，约保留最近 6 小时，超过约 2200 行自动回落到 2160 行；
- `/var/run/tvguard-soak.state` 保存当前累计/候选会话状态，RAM-only；
- `/mnt/mmcblk2p4/tvguard/soak-summary` 为 overwrite-only 小摘要，只在 high_ratio_pause 进入/退出或最多每小时 checkpoint 时写一次；
- 进入/退出事件复用已有、受 256 KiB 上限保护的 `events.log`，不新增 append-only 持久日志；
- Soak summary 不计入原有 1 MiB append-only 预算，因为它是原子覆盖写的小文件。

安全隔离：
- `tvguard-soak` 只接收 telemetry 副本；
- 返回值没有 billing/gate 动作字段；
- controller 只读取 transition/duration 并可记录事件；
- 自动回归明确验证 soak enter/exit 时 `USED_S`、`billing_state`、`blocked/gate` 仍由原有逻辑决定。

只读查看：
`/usr/libexec/tvguard-status soak`

CI #42609884752：static + package success。
Package：`luci-app-tvguard_0.1.13-10_all.ipk`
IPK SHA256：`b47d304168d38990b4b6d4885e8cdd48f148059a7ec9c236b7577186d01f6bb0`
Artifact：`tvguard-v0.1.13-r10-shadow-soak-ipk`
Artifact digest：`sha256:4a55bf52071c4382a4b3bb5cb638eacc6d03098fbf11b4b4daf58a15205197dc`

## v0.1.13-r9 Config Persistence · UCI 跨固件恢复

r8 已将运行状态/学习数据迁到 `/mnt/mmcblk2p4/tvguard`。r9 继续把 `/etc/config/tvguard` 纳入跨固件保护，但保持 UCI 正式工作路径不变。

正式备份：
`/mnt/mmcblk2p4/tvguard/config/tvguard`

关键语义：
- `/etc/config/tvguard` 仍是 OpenWrt/UCI 的 live config，LuCI 与 `uci` 命令继续正常使用；
- package 正常升级前，`preinst` 尝试先把当前 live config 备份到 mmc；
- 新固件 overlay 中若安装前不存在 TV Guard 配置，`preinst` 写入一次性 restore marker，`postinst` 在文件解包后优先恢复 mmc 备份；
- 若包被直接预置进新固件、没有经历普通 preinst 路径，启动阶段仍能识别“新 overlay + 包内默认配置 + mmc 已有自定义备份”，并恢复自定义备份；
- 同一 overlay 上管理员主动把配置改回默认值时不会被旧备份反向覆盖，因为会有 `/etc/.tvguard-config-v1` overlay marker；
- sysupgrade 若保留了一个非默认、更新的 `/etc/config/tvguard`，即使 overlay marker 未保留，也优先把这份 live custom config 视为新版本并刷新 mmc 备份；
- mmc 未挂载时不会在别处创建第二份持久配置备份；继续使用当前 live UCI，待 mmc 恢复后再同步；
- daemon 每轮只做 compare-first `config-sync`，内容未变化时不会重写 mmc 文件；service reload 后也会立即刷新备份。

同时修正 `tvguard-status brief` 计时文案：
- parent → `已暂停（家长模式不计儿童额度）`
- locked → `已暂停（锁定模式）`
- child → 才根据 Adaptive/静默/计时状态解释原因。

CI #42607014521：static + package success，覆盖：
- 正常 package upgrade vs fresh-overlay preinst 区分；
- fresh firmware default config 自动恢复 durable custom config；
- preserved newer custom config 不被旧 backup 覆盖；
- 同 overlay 主动修改/回默认的语义；
- mmc 临时缺失不产生第二持久配置源；
- service start/reload/daemon config-sync；
- 原有 controller/Adaptive/firewall/proxy isolation/storage/migration 回归。

Package：`luci-app-tvguard_0.1.13-9_all.ipk`
IPK SHA256：`f003c9d5877cf01bf40c662d31876452ef3234ace4328231099e8b014e41c1cb`
Artifact：`tvguard-v0.1.13-r9-config-persistence-ipk`
Artifact digest：`sha256:e8369bcdfce46f4278d71d98269af9bea21283802221a098435e47db7cb61df4`

## v0.1.13-r8 Durable MMC Data · 持久数据迁移

N1 的固件 overlay 在升级/重刷时可能被替换，因此 `/etc/tvguard` 不再作为正式持久数据根。r8 将 TV Guard 的运行状态、学习资料和历史摘要统一迁到：

`/mnt/mmcblk2p4/tvguard`

迁移/故障语义：
- `/mnt/mmcblk2p4` 精确挂载且可写时，正式数据根为 `/mnt/mmcblk2p4/tvguard`；
- 首次 r7→r8 升级会原子复制并校验旧 `/etc/tvguard` 中已知文件，成功后才删除旧副本；
- 已知数据全部迁完且旧目录为空时，可创建 `/etc/tvguard -> /mnt/mmcblk2p4/tvguard` 兼容软链接；
- 未知/管理员自行放入 `/etc/tvguard` 的文件不会自动删除；
- 若持久分区尚未挂载，新的写入只进入 `/var/run/tvguard-data`，不会重新把 overlay `/etc` 变成第二套持久数据库；
- 持久盘恢复后，只合并挂载中断期间新增的 append-only 后缀；从旧库种入 RAM 供读取的前缀不会重复追加，避免学习样本被重复加权；
- `/var/run/tvguard.state` 继续作为当前启动周期的运行态权威，磁盘状态是持久快照；
- 若系统启动早于 mmc 挂载，RAM runtime 会记录当前数据根模式；当数据根从 `volatile` 切回 `persistent` 时，旧 RAM runtime 会被丢弃并立即重新加载 mmc 的持久状态，避免临时 child/default 状态压住真实模式与额度。
- 原 r7 的 1 MiB append-only 总预算继续生效，迁移到 mmc 后仍会自动裁剪。

当前正式持久文件：
- `/mnt/mmcblk2p4/tvguard/state`
- `/mnt/mmcblk2p4/tvguard/events.log`
- `/mnt/mmcblk2p4/tvguard/calibration-v3.csv`
- `/mnt/mmcblk2p4/tvguard/calibration-v4.csv`
- `/mnt/mmcblk2p4/tvguard/learning-sessions.csv`
- `/mnt/mmcblk2p4/tvguard/learning-last.txt`

`tvguard-status storage` 会显示当前是 `persistent` 还是 `volatile`、实际数据目录、正式持久目录、挂载状态和剩余空间。

CI #42599800578：static + package success；其中覆盖旧库迁移、挂载缺失 RAM fallback、恢复后只合并新增数据、学习数据不重复、volatile→persistent 运行态切换后立即恢复 mmc 状态、存储上限、原有 controller/enforcement/firewall/proxy/Adaptive 回归。
Package：`luci-app-tvguard_0.1.13-8_all.ipk`
IPK SHA256：`d258470f95a0a545d309f2f3ea11229aa0642b4c9038d477b42a4eb5aeecf4b7`
Artifact：`tvguard-v0.1.13-r8-durable-mmc-data-ipk`
Artifact digest（CI #42599800578）：`sha256:cd6600b51327f887a9ece30301fd67dbc9dd5afcb1ef606514f896d7b7774abc`

> 固件升级前必须先确认 `tvguard-status storage` 显示 `数据模式: persistent` 且当前目录为 `/mnt/mmcblk2p4/tvguard`。否则当前 r7 数据仍可能只在 overlay 中，不能宣称已具备跨固件升级持久性。

## v0.1.13-r7 Storage Guard · 持久存储硬上限

为避免 N1 长期运行后 TV Guard 自身数据无限增长，r7 新增统一存储护栏。

当前所有追加型持久数据的设计预算合计固定为 **1 MiB**：
- `/etc/tvguard/events.log`：最多 256 KiB，超限保留最近 1500 行；
- `/etc/tvguard/calibration-v3.csv`：最多 256 KiB，超限保留最近 1500 行；
- `/etc/tvguard/calibration-v4.csv`：最多 384 KiB，超限保留最近 1800 行；
- `/etc/tvguard/learning-sessions.csv`：最多 128 KiB，超限保留最近 512 个会话摘要。

其中前 3 项原本已有局部裁剪；r7 补齐此前无上限的 `learning-sessions.csv`，并新增 `tvguard-retention` 统一兜底。daemon 启动时执行一次裁剪，完成学习会话后再次裁剪。

不会持续增长的文件：
- `state`：覆盖写；
- `learning-last.txt`：覆盖写；
- `/var/run/tvguard-adaptive-window.csv`：临时滚动窗口，最多约 12 行，重启即消失，不写入持久存储。

后续 Shadow Soak 的设计约束：原始高频 soak 数据必须优先进入 `/var/run` 或 `/tmp` 的有界环形缓冲，禁止建立无限追加的 `/etc/tvguard` 原始日志；若保存持久摘要，也必须纳入 retention 上限。

新增只读检查：
`/usr/libexec/tvguard-status storage`

CI #42595915294 已验证：人为制造超大 append-only 文件后，四类文件均自动裁剪回规定上限，且保留最新记录；static + package 均成功。

Package：`luci-app-tvguard_0.1.13-7_all.ipk`
IPK SHA256：`e4670c58476f21f086baa2dd812fe9e72880345f405ebc89c768c532098d1546`
Artifact：`tvguard-v0.1.13-r7-storage-guard-ipk`
Artifact digest：`sha256:1254942492c24d2d9dd99072863fb0e014d982b58c123dd254e6820ca24b9cd1`

## v0.1.13-r6 Phase 2A · N1 真机通过 · 2026-11-09

N1 完成 r6 三阶段真机验证：

1. 正常播放稳定后：
   - Adaptive: active 100%
   - rolling PPS P50/P90 = 85/144
   - Pause hint = none
   - B/P P50/P90 = 3086/5246
   - 当前 PPS 144 >= learned active floor 138
   - 结论：即使播放阶段 B/P 极高，clear-active / rising evidence 仍能 veto pause hint。

2. 腾讯暂停稳定后：
   - Adaptive: active 95%
   - rolling PPS P50/P90 = 140/166
   - Pause hint = high_ratio_pause 95%
   - B/P P50/P90 = 4600/5184
   - 当前 PPS 137，略低于 active floor 138
   - trend = 0%
   - 结论：高流量暂停原型可稳定命中，同时 Phase 1 仍保持 active/charge，未放宽计时。

3. 恢复播放后：
   - Adaptive: active 100%
   - rolling PPS P50/P90 = 140/260
   - Pause hint = none
   - B/P P50/P90 = 4503/5290
   - 当前 PPS 260，明显进入 active 区
   - 结论：恢复播放后 Pause Shadow 可退出，即便 rolling B/P 仍维持高位。

因此 r6 完成 Phase 2A 的目标：
- high-ratio pause hint 有可重复的 paused 召回；
- 正常播放不会因为高 B/P 长期挂成 paused；
- pause → play 转换能退出暂停候选；
- Phase 1 billing 仍保持原有 active/idle 安全语义。

r6 可标记为当前 Phase 2A 真机通过基线。pause hint 仍不直接授予免计时；要进入 paused_verified 还需额外门槛与多轮真机重复验证。

## v0.1.13-r5 Phase 2A 真机结果与 r6 修正

N1 r5 三阶段真机结果：
- 正常播放稳定后：Adaptive active 100%，Pause hint = none；通过。
- 腾讯暂停约 60 秒：Adaptive 仍 active 95%，但 Pause hint = high_ratio_pause 95%；旁路暂停线索命中；通过。
- 恢复播放约 60 秒：Adaptive active 100%，但 Pause hint 仍 high_ratio_pause 95%；未通过“恢复播放后退出暂停候选”。

第三段关键数据：PPS P50/P90 144/213，当前 PPS 144 已超过 learned active floor 138，rolling B/P P50/P90 仍高达 2439/5022，trend=-68%。这证明“高 B/P”不是暂停独占特征，播放恢复/高吞吐阶段也可能出现。

因此 r5 仅证明 high-ratio pause hint 有召回价值，不具备免计时资格。r6 增加两个播放优先 veto：
- 当前 PPS >= learned active floor：立即取消 high_ratio_pause；
- rolling PPS trend < -20%（明显上升）：取消 high_ratio_pause，即使当前窗口暂时低于 active floor。

这两个 veto 只影响 pause shadow，不改变 Phase 1 idle/active/ambiguous 与计费逻辑。

## v0.1.13-r5 Adaptive Phase 2A · 暂停多原型（Shadow）

N1 在 Phase 1 真机确认 `idle ↔ active` 稳定后，又补充了两组不同视频 App 的暂停采集。高质量 paused 会话现呈现三种明显不同的网络行为：

- 低活跃型：PPS P10/P50/P90 = 19/21/35，BPS median/P90 = 2991/8020；与首页 idle 高度重叠。
- 低基线 + 突发型：12/18/101，BPS = 4501/16262；大部分时间低活跃，但偶有明显 burst。
- 高吞吐/高 B/P 型：45/115/184，BPS = 166296/380772；PPS 已进入播放重叠区，但 BPS/PPS 明显高于可信播放窗口。

可信 completed+high playing 会话仍显示：
- playing #1：PPS 138/160/233，BPS 50891/65964；
- playing #2：168/402/715，BPS 47375/99570。

Phase 2A 不再把所有 paused 会话平均成一个 profile，而是从高质量人工会话动态识别 pause prototypes：

1. `idle_overlap`：低活跃暂停候选，与首页不可可靠区分；
2. `bursty_pause`：低中位 + 高 P90 的突发型暂停候选；
3. `high_ratio_pause`：PPS 可像播放，但 60 秒窗口 B/P 中位显著高于 trusted playing。

安全规则：
- pause hint 是旁路诊断字段，不改变 Phase 1 的 `idle/active/ambiguous`；
- 即使 `high_ratio_pause` 命中且 Phase 1 仍为 `active`，儿童计时继续；
- 暂停线索不得直接修改 firewall gate；
- 只有后续 N1 真机证明正常播放不会误命中、暂停恢复播放能快速退出 pause hint 后，才讨论高置信 paused 是否进入免计时集合。

CI #42591748403：static + package success。
Package：`luci-app-tvguard_0.1.13-5_all.ipk`
IPK SHA256：`85e21a3a86b3c1343ef11501fb5bb5609f7f5fb24964db976f47083c50dc1d05`
Artifact：`tvguard-v0.1.13-r5-adaptive-pause-shadow-ipk`
Artifact digest：`sha256:2c8e1581330e817c67c856e4edd9646dbea34d696548bee58fd992e8ceedd919`

## v0.1.13-r4 Adaptive Phase 1 · N1 真机通过 · 2026-11-09

N1 已完成 r4 真机验证，`idle ↔ active` 状态切换稳定：

- 首页/低活跃状态可稳定进入 Adaptive idle；
- 旧 shadow_label 偶发漂移不再导致计时状态反复清零；
- 正常播放可稳定进入 Adaptive active；
- idle → active 恢复计时稳定；
- active → idle 可重新收敛为闲置；
- 本轮验证未发现 Phase 1 滚动窗口破坏 firewall/gate 行为。

因此将 `v0.1.13-r4-adaptive-phase1` 标记为当前 Adaptive Engine Phase 1 真机通过基线。
暂停仍不在 Phase 1 的免计时范围内；paused-like 流量继续按 `ambiguous → charge` 处理，待 Phase 2 增强证据后再评估。

## v0.1.13-r4 Adaptive Engine Phase 1 · 2026-11-09

N1 已完成四状态人工学习，机器可读高质量会话显示：
- system_home：PPS P10/P50/P90 = 9/14/34，BPS median/P90 = 6409/29194
- app_home：28/41/61，BPS = 37580/58416
- playing #1：138/160/233，BPS = 50891/65964
- playing #2：168/402/715，BPS = 47375/99570
- paused：12/18/101，BPS = 4501/16262
- 另有一条 playing stopped/low（8 samples，44% coverage），Adaptive Engine 明确忽略。

Phase 1 决策：
- 仅使用 `completed + high` 人工学习会话。
- 至少需要 2 个高质量 idle 会话（system_home/app_home 合并）和 2 个高质量 playing 会话才启用；否则回退旧 shadow。
- 从学习数据动态推导 idle P90 上界与 playing P10 下界，不把本机 61/138 写死。
- 使用最近约 60 秒（最多 6 个有效窗口）的滚动统计；单个 unknown/漂移不会清空历史。
- 明确 active 当前帧立即恢复计时；持续中高位活跃也可由滚动中位/投票识别为 active。
- idle 需要低 median + 低 P90 双重支持。
- paused 当前仍与低活跃/播放存在结构性重叠，Phase 1 保持 `ambiguous` 并继续计时；后续阶段再利用更多暂停会话和双向特征处理。

CI #42586216893：static + package 全部通过。
Artifact：`tvguard-v0.1.13-r4-adaptive-phase1-ipk`
IPK SHA256：`afcefa73d1ccfde61569ece6a28803c1ee2d7cf8f87a170ae68c439e60074e9c`
Artifact digest：`sha256:213f138fe9ad288e468ad95e3e4247e9711498aa2fe1fafa52fec0e41e492251`

## v0.1.13-r3 学习中心 · 2026-11-09

“智能识别 · 实验”已重构为面向 Adaptive Learning 的“智能识别学习”中心：

- 用户只需选择四种真实状态之一：电视系统首页、视频 App 首页、视频正常播放、视频暂停。
- 不再要求选择 App 名称；新学习会话统一按设备行为学习，旧 App 标签仅保留兼容。
- 采集时长可选 1 / 3 / 5 分钟，默认推荐 3 分钟。
- 到时自动结束，无需再次点击。
- 每次结束自动运行轻量分析器，计算有效样本数、有效时长、完整度、PPS P10/中位/P90、TCP/UDP 中位、BPS 中位/P90、窗口波动。
- 自动生成可读分析报告；r8 起机器可读摘要写入正式持久库 `/mnt/mmcblk2p4/tvguard/learning-sessions.csv`。
- 高质量人工会话被标记为 Adaptive Engine 的可信训练资料；低质量/提前结束样本会保留但不会单独改变模型。
- 该阶段只重构采集、分析和训练资料库；Phase 1 滚动窗口引擎接入前，单次学习结果不会直接改变儿童计时或防火墙。
- 包版本提升为 `0.1.13-3`，运行时构建标识 `v0.1.13-r3-learning-center`。

CI #42581313641：static + package 全部通过。
Artifact：`tvguard-v0.1.13-r3-learning-center-ipk`。
Artifact 容器摘要曾由 Actions 返回；它不是 IPK 文件本身的 SHA256。r3 起由 CI 直接输出 IPK 的 `sha256sum`，以该值作为安装包校验依据。

# TV Guard v0.1 · N1 联调计划

> 状态：v0.1.12 已在用户 N1 完成核心功能与可靠性真机闭环：操作日志、移动端界面、代理兼容、手动正式锁定/恢复、儿童额度与奖励自动控制、TV Guard service reload、全局 fw3/firewall reload，以及 N1 整机重启后的持久模式/额度/gate 恢复均已通过。实验性回程观测仍保持默认关闭，不作为稳定核心功能的前置条件。当前可作为首个稳定候选进入合并前收尾。

## v0.1.13-r2 计费状态与页面标签解耦 · 2026-11-09

用户继续在同一个视频 App 首页停留，观察到：
- 10 PPS / TCP 2 / UDP 7 / 3643 B/s → 被显示为 `system_home`
- 12 PPS / TCP 1 / UDP 11 / 3237 B/s → `system_home`，30 秒后暂停计时
- 16 PPS / TCP 0 / UDP 15 / 3154 B/s → 短暂掉为 `unknown`，计时恢复并多扣 10 秒
- 随后 11 PPS、7 PPS 又回到 `system_home` 并重新等待 30 秒确认

这证明仅靠当前出站网络特征，App 首页与系统首页并不能稳定区分；继续强行输出具体页面会产生虚假精度，同时单帧 unknown 会把识别抖动放大成实际计费误差。

r2 架构调整：
- 日常计费层不再依赖具体 `system_home / app_home` 名称；已有两类闲置证据时，匹配可信低活跃包络统一输出中性 `idle`。
- `system_home / app_home / paused / idle` 在计费层统一为可信闲置族。
- 已达到 `idle_verified` 后，若下一帧只是 `low_traffic + unknown`，进入最多 20 秒的 `idle_grace`；保持暂停计时并等待闲置证据恢复。
- `playing` 或中/高活跃 `unknown` 立即恢复 charge；低活跃 unknown 连续超过 20 秒也恢复 charge。
- r2 不把“低 PPS”直接当作免费时间：20 秒保持只在**之前已经确认 idle**之后生效。
- `brief` 增加明确构建标识和 `保持 x/20s`，避免同版本号不同测试包混淆。
- opkg 包提升为 `0.1.13-2`，运行时构建标识为 `v0.1.13-r2-adaptive-idle`。

CI #42577640545：static + package 全部通过。
Artifact：`tvguard-v0.1.13-r2-adaptive-idle-ipk`。
SHA256：`c1cbb5fab072a0c0e896b0ef3d2b3834136c807f65ad6b57709fa509bf279cd4`。

该候选待 N1 真机验证：在同一 App 首页持续停留 2～3 分钟，允许 scene 显示 idle/unknown，但计费不应因单次低活跃 unknown 反复重启 30 秒确认。

## v0.1.13 播放显示识别分层 · 2026-11-09

用户在正常播放中观察到：
- 144 PPS / TCP 2 / UDP 141 / 35441 B/s → 旧版为 `unknown`
- 405 PPS / TCP 79 / UDP 326 / 48857 B/s → 旧版仍为 `unknown`

计时行为本身正确：两种状态均继续 charge；问题仅在状态显示识别。

结合现有标注证据：
- playing：91–309 PPS（11 samples / 1 session）
- paused：65–157 PPS（12 samples / 1 session）

因此 144 PPS 落在播放/暂停明显重叠区，不能可靠断言正在播放；继续 `unknown` 是正确的保守结果。
405 PPS 已明显高于暂停与首页上界，可作为本机高置信度播放提示。

已调整：
- 跨 App 播放证据充分时继续输出 `playing general 100`；
- 仅有本机播放参考时，只要明确排除已验证 App 首页、系统首页与暂停包络，可输出 `playing general 95`；
- 对高于已标注播放范围的 burst 只允许有界外推，超出动态上界的异常流量仍为 `unknown`；
- 播放标签只用于显示/诊断，不改变 `USED_S`、gate 或免计时逻辑。

回归要求：
- 144/2/141/35441 → unknown
- 405/79/326/48857 → playing 95
- 5000 PPS 等明显异常值 → unknown

CI #42576556895：static + package 全部通过。

## v0.1.13 系统首页后台突发导致 unknown · 2026-11-09

用户在电视持续停留系统首页时观察到分类结果仍会在 `unknown` 与 `system_home` 之间抖动：

- 16 PPS / TCP 12 / UDP 4 / 4004 B/s → `unknown`
- 12 PPS / TCP 8 / UDP 3 / 3145 B/s → `system_home`
- 11 PPS / TCP 7 / UDP 3 / 45852 B/s → `unknown`

这说明旧分类器要求 PPS/TCP/UDP/bytes 四维全部命中历史首页矩形包络，无法容忍电视首页后台同步产生的单一 TCP 或字节突发。

已修正系统首页匹配：
- PPS 本身仍必须处于已校准系统首页的低活跃包络（仅小幅容差）；
- 四维至少 3/4 命中首页特征；
- 仍必须与播放参考明确分离；
- 允许一个次级维度（TCP 或 bytes）短暂噪声，不允许播放级 PPS 使用该例外。

新增真实形态回归：
- `16 / 12 / 4 / 4004` 必须识别 system_home；
- `11 / 7 / 3 / 45852` 必须识别 system_home；
- `98 / 1 / 96 / 99364` 不得识别 system_home。

CI #42574727506：static + package 全部通过。该修正待 N1 覆盖安装后真机复验。

## v0.1.13 App 首页边界与闲置标签切换真机发现 · 2026-11-09

用户继续在儿童模式测试视频 App 首页：

- 起始时 App 首页仍有约 98 PPS，状态为 `unknown / charge`。
- 45 秒后流量下降到约 25 PPS，分类器正确进入 `app_home`，连续闲置 41 秒，计时暂停；用量仅从 75m43s 增至 76m03s，对应前期保守确认窗口。
- 105 秒时电视仍停留 App 首页，但流量进一步下降到约 13 PPS / 7055 B/s，旧分类顺序将其改判为 `system_home`；控制器又把“闲置标签变化”当成新的 30 秒确认，导致连续闲置被重置为 10 秒并额外计时 10 秒，用量增至 76m13s。

该现象暴露两个独立问题：
1. 已确认的可信闲置状态在 `app_home / system_home / idle / paused` 之间切换时，不应重置闲置确认或恢复扣时。
2. 当多个已经验证的闲置包络同时命中时，不应按规则顺序伪装成具体前台页面，应输出中性的 `idle`。

已修正：
- 控制器把上述标签作为同一个“可信闲置族”，标签切换持续累加 `idle_streak_seconds`；只有 `unknown / playing` 才立即恢复 charge。
- 分类器在 system-home 与 local App-home 包络同时命中且均与播放分离时输出 `idle general 95`。
- 新增与真机边界相似的 13 PPS 重叠回归测试，以及 `app_home → system_home` 后 `USED_S` 不增长的状态机测试。
- CI #42573384625：static + package 全部通过。

该修正仍待下一轮 N1 覆盖安装后确认。

## v0.1.13 智能计时第一轮 N1 真机验证 · 2026-11-09

用户升级 v0.1.13 开发候选后完成儿童模式智能计时实测：

- 系统首页在家长模式下可稳定识别为 `system_home`，连续闲置超过 30 秒后显示“已暂停（系统首页已确认）”。
- 切换儿童模式后，前 21 秒仍处于保守确认期，`used_seconds` 从 56m47s 增至 57m08s；随后系统首页进入 `idle_verified`，在后续 105 秒观察窗口中用量保持 57m08s 不再增长。
- 开始正常播放后，状态立即回到 `unknown / charge / idle_streak=0`；用量随后从 57m08s 持续增长到 58m10s、58m51s，证明无法确认闲置时会立即恢复计时。
- App 首页现场流量降至约 29–33 PPS，但仍为 `unknown / charge`。现有校准数据为 App 首页 12 samples / 1 session，因此新增“本机已验证 App 首页”保守兜底：至少 10 samples / 1 labelled session，且当前四维特征必须落入该 App 首页包络并与播放参考明确分离，仍需连续 30 秒后才暂停计时。
- 暂停状态当前样本范围 65–157 PPS 与播放 91–309 PPS 存在明显重叠，因此暂不采用单会话暂停免计时，继续保持 unknown 时计时。

该轮确认 **系统首页暂停计时 + 播放立即恢复计时** 已真机通过；App 首页本机兜底待下一轮 N1 验证。

## v0.1.12 N1 整机重启持久状态恢复真机通过 · 2026-11-09

用户完成两轮 N1 整机重启，分别验证正式控制下的家长放行与锁定阻断：

- 开机自启检查 `/etc/init.d/tvguard enabled` 返回成功。
- **家长模式跨重启**：重启前 `mode=parent`、`enforce=1`、`armed=1`、`blocked=0`、`firewall_state=allowed`；重启后 `tvguardd` 正常运行，仍保持完全相同的家长模式与正式控制状态，`used_seconds=2926` 未丢失，核心 hook 为 `-s 192.168.101.76/32 -i br-lan -j TVG_RAW`，`TVG_GATE` 正确恢复为 `RETURN`。
- **锁定模式跨重启**：重启前 `mode=locked`、`enforce=1`、`armed=1`、`blocked=1`；重启后仍保持锁定，`used_seconds=2926` 未被清零，隔离审计为 `ok`，核心 hook 精确恢复，`TVG_GATE` 正确恢复为 `DROP`，现场 DROP 计数为 526 packets / 81700 bytes。
- 用户确认两轮重启后的电视联网/断网行为均符合预期。
- 最终恢复家长放行、关闭正式控制、清除 armed 并切回儿童模式后，状态为 `enforce=0`、`armed=0`、`blocked=0`、`firewall_state=allowed`；`tvguard-compat-check` 再次返回 `result=PASS`、`proxy_rules_unchanged=1`、`isolation_audit=ok`。

该结果确认 **TV Guard 的模式、已用额度与正式控制 gate 可以跨 N1 整机重启正确恢复**，且不会把持久状态错误重置为新的儿童额度或错误放行/封禁。

## v0.1.12 全局 firewall reload 策略重建真机通过 · 2026-11-09

用户在 N1 正式控制开启状态下执行两轮 `/etc/init.d/firewall reload`，验证 fw3 清空并重建整套 IPv4/IPv6 表后 TV Guard 能否通过独立 include 恢复当前策略：

- reload 前锁定状态为 `mode=locked`、`enforce=1`、`armed=1`、`blocked=1`，`TVG_GATE` 为 `DROP`；核心 hook 精确为 `-s 192.168.101.76/32 -i br-lan -j TVG_RAW`。
- fw3 输出明确显示清空并重新 populate IPv4 raw table，随后执行 `/usr/libexec/tvguard-firewall-include`；`firewall_reload_rc=0`。
- reload 后 `tvguardd` PID 仍为 `27433`，TV Guard 核心链和 hook 被重新建立，`TVG_GATE` 仍为 `DROP`，锁定状态保持，现场 DROP 计数 383 packets / 57494 bytes。
- 保持 `enforce=1` 切换家长模式后再次执行全局 firewall reload，reload 后仍为 `blocked=0`、`firewall_state=allowed`，`TVG_GATE` 正确重建为 `RETURN`。
- 最终退出正式控制后，`tvguard-compat-check` 再次返回 `result=PASS`、`proxy_rules_unchanged=1`、`isolation_audit=ok`、`gate=allowed`。
- fw3 reload 过程中出现的 WAN、ZeroTier 以及若干缺失 include 的 warning 属于现有防火墙/插件配置输出；本轮没有证据表明它们由 TV Guard 引入，且 reload 返回 0、TV Guard include 正常执行、最终兼容检查通过。

该结果确认 **全局 fw3/firewall reload 清空 raw 表后，TV Guard 能按持久状态自动重建目标电视专用 hook 与正确的 DROP/RETURN gate，且不会重启 tvguardd。**

## v0.1.12 TV Guard service reload 策略保持真机通过 · 2026-11-09

用户在 N1 正式控制开启状态下验证 `/etc/init.d/tvguard reload`：

- reload 前处于 `mode=locked`、`enforce=1`、`armed=1`，状态为 `blocked=1`、`firewall_state=blocked`。
- reload 前后 `tvguardd` PID 均为 `27433`，证明 reload 没有重启 daemon。
- reload 后仍保持 `mode=locked`、`blocked=1`，`TVG_GATE` 仍为 `DROP`，现场计数 6 packets / 1972 bytes。
- 保持正式控制开启，切换 `mode parent` 后再次执行 service reload，状态仍为 `blocked=0`、`firewall_state=allowed`，`TVG_GATE` 保持 `RETURN`。
- 退出正式控制并恢复儿童模式后，最终 `tvguard-compat-check` 再次返回 `result=PASS`、`proxy_rules_unchanged=1`、`isolation_audit=ok`、`gate=allowed`。
- 整轮测试中自动回滚保护正常可终止，未观察到代理或其他设备受影响。

该结果确认 TV Guard 自身 service reload **不会重启 daemon，也不会丢失当前正式控制策略**。

## v0.1.12 儿童额度 / 奖励自动控制真机通过 · 2026-11-09

用户在电视端逐步实测并确认全部通过。本轮将工作日额度临时设为 35 分钟，以便使用已累计的儿童用量直接触发额度耗尽，然后完整验证：

- 切回儿童模式后：`used_seconds=2281`、`quota_seconds=2100`、`policy_reason=quota`、`blocked=1`、`firewall_state=blocked`，`TVG_GATE` 为 `DROP`；电视实际无法联网。
- 执行 `bonus 15` 后：`quota_seconds=3000`、`bonus_seconds=900`、`policy_reason=none`、`blocked=0`、`firewall_state=allowed`，`TVG_GATE` 切回 `RETURN`；电视实际恢复联网。
- 执行 `bonus undo` 后：`quota_seconds=2100`、`bonus_seconds=0`、`policy_reason=quota`、`blocked=1`、`firewall_state=blocked`，`TVG_GATE` 再次为 `DROP`；电视再次断网。
- 随后切换家长模式可恢复 `allowed`。
- 结束测试后恢复工作日额度 60 分钟、退出正式控制并切回儿童模式，最终状态为 `enforce=0`、`armed=0`、`blocked=0`、`firewall_state=allowed`。
- 最终 `tvguard-compat-check` 再次返回 `result=PASS`、`proxy_rules_unchanged=1`、`isolation_audit=ok`，`observe_reply=0`。

该结果确认日常家庭控制的核心自动链路 **“儿童额度耗尽自动断网 → 奖励时间即时恢复 → 撤销奖励再次断网 → 家长模式放行”** 已在 N1 / iptables-legacy 真机通过。

## v0.1.12 正式控制完整手动链路真机通过 · 2026-11-09

用户在 N1 上完成 v0.1.12 的完整手动控制链路验证：

- `mode=locked`、`enforce=1`、`armed=1` 时，状态为 `blocked=1`、`firewall_state=blocked`，`TVG_GATE` 为 `DROP`；现场计数 63 packets / 26866 bytes，电视实际断网。
- **没有关闭 enforce**，直接执行 `mode parent` 后，状态变为 `would_block=0`、`blocked=0`、`firewall_state=allowed`，`TVG_GATE` 原位切回 `RETURN`；现场计数 2147 packets / 578531 bytes，电视实际恢复联网。
- 随后退出正式控制并恢复儿童模式，最终为 `enforce=0`、`armed=0`、`gate=allowed`。
- 最终再次运行 `tvguard-compat-check`：`result=PASS`、`proxy_rules_unchanged=1`、`isolation_audit=ok`、`observe_reply=0`。
- 用户同时确认断网与恢复网络的实际体验均正常。

该结果正式确认 **“家长放行 → 手动锁定断网 → 家长模式即时恢复 → 安全退出正式控制”** 的完整核心链路已在 N1 / iptables-legacy 真机通过。

## v0.1.12 N1 升级验证 · 2026-11-09

用户已在 N1 从 `0.1.11-1` 升级到 `0.1.12-1`，现场确认：

- `opkg status` 显示 `Version: 0.1.12-1`、`Status: install user installed`。
- `/usr/libexec/tvguardctl` 已包含整数秒 `sleep 1`，不再存在 `sleep 0.1`。
- 原有 `/etc/config/tvguard` 被 opkg conffile 机制保留；`enforce=0`、`allow_enforcement=0`、`observe_reply=0` 均保持安全默认状态。
- 升级后再次运行 `tvguard-compat-check`：`result=PASS`、`proxy_rules_unchanged=1`、`isolation_audit=ok`、`gate=allowed`。
- N1 环境没有 `diff` 命令；由于 v0.1.12 不新增 UCI 配置项，仅修复控制器锁等待，因此不影响本次升级结论。

## v0.1.12 N1 BusyBox 锁等待兼容修复 · 2026-11-09

在继续验证“锁定 → 家长模式即时恢复”时，N1 现场出现：

```text
sleep: invalid number '0.1'
```

根因是 `tvguardctl` 在互斥锁竞争时使用 `sleep 0.1`；该 LEDE/N1 的 BusyBox `sleep` 仅接受整数秒。命令在争锁路径直接失败，因此当次 `enforce on` 并未真正启用，后续 `mode locked` 仍保持 `allowed`。这不是防火墙 gate 逻辑失败。

v0.1.12 修复：
- 锁等待改为整数秒 `sleep 1`，最多约 5 秒后报 `tvguard lock busy`，不再依赖小数 sleep。
- 新增回归测试：模拟 BusyBox 拒绝小数 sleep，并制造一次 stale lock，要求控制器可以恢复后继续执行。
- 默认安全开关保持 `enforce=0`、`allow_enforcement=0`、`observe_reply=0`。

## v0.1.11 正式锁定真机验证 · 2026-11-09

用户在 N1 上按双开关与隔离审计流程开启正式控制后执行手动锁定，现场结果：

- 状态：`mode=locked`、`enforce=1`、`armed=1`、`would_block=1`、`blocked=1`、`firewall_state=blocked`。
- `TVG_GATE` 唯一规则已切换为 `DROP`；现场快照计数为 255 packets / 352456 bytes，证明目标电视 IPv4 流量确实命中 TVG gate。
- 电视实测无法继续播放网络内容。
- 同时手机、电脑保持正常联网，未观察到对其它设备的误阻断。
- 本轮仍保持 `observe_reply=0`，没有启用实验性回程观测。

该结果确认 **“手动锁定 → 仅阻断目标电视经过 N1 的 IPv4 流量”** 已在真实 N1 环境成立。尚未据此宣称恢复放行、儿童额度自动阻断、防火墙重载/重启恢复或旁路绕过防护已经通过；这些需继续独立验证。

测试收尾后用户执行恢复与兼容自检，现场最终安全状态为：

- `mode=child`、`enforce=0`、`armed=0`、`blocked=0`、`firewall_state=allowed`。
- `tvguard-compat-check` 返回 `result=PASS`、`proxy_rules_unchanged=1`、`isolation_audit=ok`、`gate=allowed`。
- `observe_reply=0`，仍未启用实验性回程观测。
- iptables 环境确认为 `iptables v1.8.7 (legacy)`。

这说明第一轮正式锁定测试结束后，TV Guard 能恢复到默认观察/放行安全状态，且兼容自检没有发现非 TVG 代理规则被改动。由于本轮反馈未单独提供“锁定状态下切换家长模式后电视恢复播放”的现场输出，因此该中间恢复步骤继续作为下一轮需显式确认的项目，不做超范围推断。

## v0.1.11 真机验收反馈 · 2026-11-09

用户确认：已在 N1 验收 v0.1.11 的操作日志、移动端界面和代理兼容检查，三项均通过。此前暴露的撤销奖励内部事件编号展示问题按本轮反馈已解决。该结论来自用户现场确认，本次未附原始 `tvguard-compat-check` 终端输出；不能据此认定真实网络阻断、回程观测或异常回滚已经通过。

**阶段结论：观察模式与 UI 功能可作为已验收基线；继续保持 `enforce=0`、`allow_enforcement=0`、`observe_reply=0`，正式网络控制需单独制定可回滚的 N1 现场测试。**

## v0.1.10 真机儿童模式与奖励验证 · 2026-11-09

### 跨日真机状态

从 2026-11-08 跨到 2026-11-09 的 N1 实机截图同时验证：

- 家长模式跨午夜保持，不因儿童日额度重置而退出。
- 2026-11-08 的周末儿童额度 120 分钟和当日奖励 30 分钟没有带入下一天。
- 2026-11-09 按工作日规则重置为儿童总额度 60 分钟、已计时 0、奖励 0。
- 说明“使用者模式”和“儿童每日额度”是两套独立状态：家长模式持久，儿童用量/奖励按自然日重置。

N1 实机已验证新版儿童模式与奖励撤销链路：

- 从家长模式切换回儿童模式成功，最近操作记录显示“已切换为儿童模式”。
- 点击 `+15 分钟` 后奖励生效，最近操作记录显示“+15 分钟”。
- 点击“撤销上次奖励”后，当日奖励恢复为 `0 / 120 分钟`，撤销状态正确。
- 整个过程仍处于观察模式，没有触发实际断网。
- v0.1.10 iPhone 深色主题实机 UI 的 2×2 状态卡、观看模式、奖励按钮、实验识别和折叠诊断布局均正常。
- 真机日志暴露出一个纯展示问题：旧记录显示“撤销奖励 #22”内部事件编号。v0.1.11 将新记录改为记录撤销分钟数，并在 UI 中兼容翻译旧 `#ID` 记录，不影响奖励逻辑。

## v0.1.7 真机家长模式验证 · 2026-11-08

N1 实机已验证新版持续家长模式跨服务重启保持：

- 切换家长模式后：`mode=parent`、`parent_until=0`、`policy_reason=none`。
- 重启 `/etc/init.d/tvguard` 后仍为：`mode=parent`、`parent_until=0`。
- 重启前后 `used_seconds=7088` 未增加，说明家长模式未消耗儿童额度。
- `quota_seconds=9000`、`bonus_seconds=1800` 保持一致，已有儿童奖励未因进入家长模式或服务重启丢失。
- `would_block=0`、`blocked=0`、`firewall_state=allowed`，观察模式下没有误阻断。
- `enforce=0`、`armed=0`、`observe_reply=disabled`，安全边界保持。

该结果确认新版语义：**家长模式无倒计时，持续生效直到手动切回儿童模式；儿童临时多看仍由奖励时间承担。**

## 自动化测试覆盖

当前开发分支的自动化测试分为四层，共 18 个测试文件：

- **LuCI / ACL**：`test-ui.js`、`test-settings-ui.js`、`test-status-wrapper.sh`，覆盖首页状态更新、精确命令派发、设置校验、高风险开关隐藏、只读 wrapper 命令白名单。
- **控制器 / 策略**：`test-controller.sh`、`test-policy.sh`、`test-enforcement.sh`，覆盖工作日/周末额度、普通/跨午夜时段、奖励上限与撤销、家长模式跨重启/跨日、旧定时家长迁移、正式控制双开关与现场隔离审计、儿童/家长/锁定 gate 切换、持久状态丢失后的 fail-closed 恢复。
- **防火墙 / 生命周期 / 代理隔离**：`test-firewall.sh`、`test-firewall-policy.sh`、`test-isolation-audit.sh`、`test-proxy-isolation.py`、`test-firewall-include.sh`、`test-package-safety.sh`、`test-init-service.sh`、`test-daemon.sh`、`test-compat-check.sh`，覆盖 raw-only 写入、TV 专属 hook、firewall reload 策略、代理规则不变、FW3 fail-open、安装卸载所有权、procd trigger、daemon tick 失败处理和一键兼容验收全部拒绝条件。
- **校准 / 识别**：`test-calibration.py`、`test-shadow.sh`、`test-generalization.py`，覆盖保守影子识别、证据重叠拒绝、未知 App 泛化和方向性校准数据边界。

这轮单元测试补齐过程中实际发现并修复了一项产品回归：v0.1.7 将长期家长模式定义为 `PARENT_UNTIL=0` 后，旧的 `tvguard-fw policy()` 在 firewall reload 时仍把 `0` 当作“已到期”，可能在正式控制开启时错误 DROP。现已明确规定：`0` = 长期家长模式允许；正数仅用于旧版本一次性定时迁移；缺失、损坏或未知状态继续 fail-closed。

自动化测试不替代 N1 真机验收。v0.1.12 的 LuCI、操作日志、代理兼容、手动正式阻断/恢复，以及儿童额度与奖励自动控制均已在 N1 / iptables-legacy 真机通过；当前仍需独立验证 firewall reload、服务/设备重启后的策略恢复，以及可选回程观测。

## 一、联调前确认

- 设备：斐讯 N1，LEDE R26.11.3，FW3 + iptables legacy。
- 在手机 / 电脑留有 SSH 管理入口；确认可从 LAN 登录 N1。
- 备份：`uci export tvguard`（如果已安装）、`uci export firewall`、`iptables-save -t raw`。
- 检查电视是否确实继续使用 `192.168.101.76`，接口 `br-lan`。
- 检查 N1 的 ICMP Redirect 配置及旁路由绕过路径，不随意改变主路由。
- 先检查已有单独手工封禁规则；如果存在，不能将 TV Guard 的“允许”当作完整恢复联网。

## 二、默认只读观察

IPK 初次部署：`enforce=0`，`allow_enforcement=0`。

先检查：
```sh
uci -q show tvguard
/usr/libexec/tvguardctl status
/usr/libexec/tvguard-fw inspect
iptables -t raw -S PREROUTING | grep TVG
```

期望：
- `tvguard-fw inspect` = `allowed`（仅代表 TV Guard 自身未阻断）。
- `tvguardctl status` 返回 JSON，`enforce=0` 且 `armed=0`，`blocked=0`。
- 记录“今日使用”在电视活动时变化，电视熄屏持续网络静默时暂停增长（允许有约 60 秒活动缓冲误差）。
- 观察模式下，即使切换到“手动锁定”或额度用尽，也**不应通过 TV Guard 拦截流量**。
- 不更改 SSR / PassWall / OpenClash 现有防火墙设置。

## 三、功能回归清单

1. LuCI “服务 → 电视时长 TV Guard”能打开，刷新、手机端适配正常。
2. 状态能显示设备计时、基础额度、奖励和实际 gate 状态；若规则不存在，不能谎报已封禁。
3. 工作日、周末额度分别保存；跨日重新分配基础额度和奖励归零。
4. 奖励 15/30/60 分钟；累计达到每日奖励上限时拒绝；撤销前一笔成功奖励后写新日志。
5. 家长模式无倒计时：进入后不扣儿童额度、不受儿童允许时段限制，重启/跨日后仍保持，直到手动切回儿童模式；旧版遗留的正数 `PARENT_UNTIL` 只按原到期时间迁移一次。
6. 手动锁定优先于儿童奖励；奖励不能解除锁定。
7. SSR 透明代理运行时，TV Guard 的计数链在 raw PREROUTING 统计电视进入 N1 的包。
8. `/etc/init.d/tvguard reload` 后 daemon 不重启、代理规则不变；由 fw3 正常 reload 时，独立 include 能恢复 TVG 入口规则。
9. r8 起重启 N1 后由 `/mnt/mmcblk2p4/tvguard/state` 恢复上次持久快照；确认不会因重启把已消耗额度清零。
10. 检查停服务时的策略保持，卸载时所有 TVG 规则均被清除而不触碰其他链。
11. 若使用电视前台场景推断，必须标注“疑似”，且不得直接启用不可信的免计时规则。

## 四、代理不干扰验收（v0.1.11 已由用户确认通过，未来改版可复验）

不需要逐个测试视频 App。升级候选版后，先保持 `enforce=0`、`allow_enforcement=0`、`observe_reply=0`，直接运行：

```sh
/usr/libexec/tvguard-compat-check
```

正常结果核心字段：

```text
result=PASS
proxy_rules_unchanged=1
isolation_audit=ok
gate=allowed
enforce=0
allow_enforcement=0
observe_reply=0
reply_coverage=unverified
```

这个命令不会 reload 全局 firewall，也不会调用任何代理服务；它只读取四张表，执行一次 TV Guard 自身的隔离同步，再确认**所有非 TVG 规则逐字未变**。

需要拆分诊断时，再分别执行：

```sh
/usr/libexec/tvguard-status isolation
/usr/libexec/tvguard-fw inspect
uci -q get tvguard.main.enforce
uci -q get tvguard.main.allow_enforcement
uci -q get tvguard.main.observe_reply
```

对应应为 `ok`、`allowed`、`0`、`0`、`0`。

只有第一项为精确 `ok` 时，后续才允许考虑正式控制。`unsafe:*` 或 `unavailable:*` 都必须视为未通过；TV Guard 的 fw3 include 即便自身同步失败，也不应让全局 firewall reload 返回失败。

为验证 TV Guard 自身操作不改变现有网络规则，可在**不触发全局 firewall reload** 的情况下做短时前后快照：

```sh
for t in raw mangle nat filter; do
    echo "### $t"
    iptables -t "$t" -S 2>/dev/null | grep -v 'TVG_'
done > /tmp/tvguard-nontvg-before.txt

/etc/init.d/tvguard reload
/usr/libexec/tvguardctl mode child
/usr/libexec/tvguardctl bonus 15
/usr/libexec/tvguardctl bonus undo

for t in raw mangle nat filter; do
    echo "### $t"
    iptables -t "$t" -S 2>/dev/null | grep -v 'TVG_'
done > /tmp/tvguard-nontvg-after.txt

diff -u /tmp/tvguard-nontvg-before.txt /tmp/tvguard-nontvg-after.txt
```

正常应无 diff。这里不跨越代理工具自己的重载动作，因为代理自身重载可能合法重建规则，不能归因给 TV Guard。

同时检查常用代理功能本身仍可正常访问；TV Guard 不要求停止或切换任何现有代理工具。

## 五、可选回程观测的安全测试（下一轮，尚未真机执行）

当前开发分支已经增加两处无动作目标的回程计数，但必须保留 `observe_reply=0`，直到完成兼容性测试。**无需安装 tcpdump/conntrack，不要改变现有 SSR、PassWall、OpenClash 或主路由设置。**

安全起点：`enforce=0`、`allow_enforcement=0`，且观察端默认关闭。真实 N1 上先备份配置和 RAW 规则，再经人工确认才测试：

```sh
uci -q get tvguard.main.observe_reply
/usr/libexec/tvguard-fw inspect-reply
/usr/libexec/tvguardctl status
```

未来明确允许启用时的最小化步骤（**开发记录，并非当前用户待办**）：

```sh
uci export tvguard > /root/tvguard-before-reply-observe.bak
iptables-save -t raw > /root/tvguard-before-reply-raw.rules
uci set tvguard.main.observe_reply='1'
uci commit tvguard
/usr/libexec/tvguard-fw sync-reply
/usr/libexec/tvguard-fw inspect-reply
/usr/libexec/tvguard-fw sample-reply
/usr/libexec/tvguardctl status
```

确认 `TVG_RX_LAN`、`TVG_RX_LOCAL` 都没有 `-j` 或其他目标，且原有 TVG_GATE 为 allowed。注意 `ready` 只意味着两条规则存在；`reply_coverage=unverified` 不会因为有回程流量而变成已验证。

快速撤回观测规则：

```sh
uci set tvguard.main.observe_reply='0'
uci commit tvguard
/usr/libexec/tvguard-fw sync-reply
/usr/libexec/tvguard-fw inspect-reply
/usr/libexec/tvguard-fw inspect
```

预期第一项为 `disabled`、第二项为 `allowed`。禁止使用 `iptables -F`、`iptables -t raw -F` 等影响其他服务的命令。

## 六、正式封禁前的放行路径

本开发版本存在额外上锁开关：
```sh
uci -q get tvguard.main.enforce
uci -q get tvguard.main.allow_enforcement
```
默认都是 `0`。**在完成上述现场测试之前，不要自行设置为 `1`。**

后续验证通过后才会提供受控的“启用”流程及失败回滚步骤；当前版本不建议开启强制模式。

## 七、恢复与卸载

已安装且希望保持电视可联网时，需先检查其它插件和原先的旧封禁规则。TV Guard 自身可用以下操作退出拦截：
```sh
/usr/libexec/tvguardctl enforce off
/usr/libexec/tvguard-fw inspect
```
应看到 `allowed`，但这不代表 SSR、主路由或其它规则一定放行。

卸载由 `prerm` 停止服务并移除 TVG 专用链；**不能使用 `iptables -F` 清空防火墙**。

## 八、仍未解决的功能限制

- 当前计时主要依据网络活动会话，尚无经证实的“小米系统首页 / App 首页 / 视频暂停”可信自动识别。
- 不区分电视是大人还是孩子，家长必须主动切换家长模式；孩子临时多看通过奖励时间处理，不使用家长模式。
- N1 单网口旁路由仅能观察经过它的 IPv4 流量；电视绕过 N1 时控制无效。
- 不基于 PPS 单阈值直接判断免计时。
- v0.1.12 的观察模式、手动正式控制、儿童额度自动阻断、奖励恢复与撤销重阻断均已在 N1 真机通过；firewall reload、服务/设备重启恢复及可选回程观测仍未完成专项真机验收。CI 通过不能替代这些测试。
