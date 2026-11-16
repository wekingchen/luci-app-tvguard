# TVGuard v0.1.15 · 多视频 App 泛化验证与自适应画像

## 目标

v0.1.14-r7 已证明：在芒果 TV 真机上，电视 Agent 的 full-context 与人工 playing/paused 联合学习可以可靠完成播放计时、暂停免计时、首页免计时、低码率保护和 Agent 自恢复。

v0.1.15 不把芒果结论直接外推到其它视频 App。本阶段目标是验证并扩展“通用机制 + 每 App 自学习”，让腾讯极光、爱奇艺等具有不同前台结构和音频行为的 App 也能在不引入品牌白名单的前提下获得可靠识别。

## 不变的安全原则

1. 决策引擎不得写死真实视频 App package / Activity 名称。
2. 人工选择的电视状态仍是真值；Agent / 网络特征只作为学习证据。
3. unknown、Agent stale、package-only、Activity unknown 默认继续计时。
4. 新的暂停机制必须先证明不会把真实播放变成免费时间。
5. 576p / 720p 低码率正常播放不得因为低 PPS、stable_low 或 idle_overlap 漏计。
6. 电视端继续保持零持久运行日志、无 SQLite、无历史队列；长期模型只保存在 N1。
7. 不为了“提高识别率”牺牲当前 r7 已通过的芒果行为。

## Phase A · 只读结构探测

先不改 Fusion，不要求重新学习。对每个待验证 App 分别观察：

- 正常播放
- 视频暂停
- App 首页

记录：

- package
- Activity
- audio_active
- screen_on
- usage_access
- foreground_source
- foreground_status
- combined_state / candidate
- network_pps / Adaptive 状态

重点回答：

1. playing 与 paused 是否共用同一 Activity？
2. playing / paused 的 audio_active 是否稳定分离？
3. app_home 是否使用独立 Activity？
4. Agent 是否能持续得到 usage_events + full_context？
5. 是否存在“首页与播放器共 Activity + audio=0”冲突？
6. 是否存在“暂停仍 audio=1”的 App？

## App 能力分类

### Type A · 同 Activity，audio 1/0 可分

与芒果类似。优先复用现有 learned-audio profile：

- playing：exact context + audio=1
- paused：exact context + audio=0，2 个 fresh report 后确认
- 网络 active / 高 PPS 不能单独覆盖已学习的 paused

### Type B · playing / paused 使用不同 Activity

优先利用 exact context 的人工画像。不得因为 Activity 名称包含 Player / Pause 等文字就自动授予权限。

### Type C · playing / paused 同 Activity 且 audio 都为 1

现有 learned-audio profile 必须拒绝成立。需要寻找第二类可靠证据，例如：

- 独立 Activity/window context
- Agent 可读取但目前未上报的播放状态
- 更强的时间序列/网络组合特征

在找到可靠证据前继续计时，不做“低流量=暂停”的回退。

### Type D · app_home 与播放器共享 Activity + audio=0

这是危险冲突。现有 profile 应禁用，不能把首页证据和暂停证据混为一类。需要额外上下文后才能授予暂停免计。

### Type E · package-only / Activity unknown

只允许正向辅助 playing；不允许 system_home / app_home / paused 免费。

## Phase B · 最小人工学习

只对 Phase A 证明有必要的状态学习，不要求每个 App 固定采四类。

优先顺序：

1. playing 180s
2. paused 180s
3. 若首页 Activity 与播放器不同且运行时已能直接稳定识别，则首页可不重复长时间学习
4. 只有出现上下文冲突时才补 app_home / 其它必要人工样本

每次 completed+high 会话继续写 29 列 learning-sessions.csv，并以 exact package+Activity 为画像键。

## Phase C · 真机计时验收

每个支持的 App 至少验证：

- 正常播放 40s：used_seconds 明显增加
- 暂停确认后 40s：used_seconds +0
- 恢复播放 40s：used_seconds 再次增加
- 低 PPS 播放不得免费
- 静音继续播放不得误判暂停
- 首页不得计时
- Agent stale/incomplete 必须恢复 charge
- report_seq 重启不能破坏持久画像

## Phase D · 跨 App 泛化评估

当至少 3 个独立视频 App 都有完整高可信样本后，再运行 leave-one-app-out：

```sh
python3 scripts/evaluate-generalization.py calibration-v5.csv
```

目标不是证明“所有未知 App 都准确”，而是：

- 危险方向（playing → free）为 0
- 未识别的新 App 可以保守多计时
- 能识别出不同 App 的行为类型
- 需要人工学习时给出明确提示，而不是偷偷套用其它 App 的画像

## 后续 UI 方向

学习中心应逐步展示当前 App 的能力，而不是只显示全局按钮，例如：

```text
当前 App：某视频 App
前台上下文：完整

正常播放   已学习 · 高可信
视频暂停   已学习 · 高可信
App 首页   已识别
播放/暂停画像：可用
```

切换到一个新的 package 后，页面应自动显示“未学习 / 基础识别”，并只建议真正缺失的样本。

## 本阶段第一批真机对象

1. 腾讯视频极光
2. 爱奇艺

芒果 TV 作为已通过的 Type A 基准，不重复做无意义的长时间采集，除非后续代码改动需要回归。


## Type D · 共享 Activity 的 generic nonplaying 画像

腾讯极光真机已经证明一种比芒果更难但仍可安全处理的结构：

- playing / paused / app_home 三态共享同一 exact package+Activity；
- playing 时 audio_active=1；
- paused 与 app_home 均为 audio_active=0；
- 静音但继续播放时 audio_active 仍保持 1。

对这种结构，运行时不应强迫计费层区分 paused 与 app_home，因为两者都属于“非播放、应免计时”集合。新的 generic nonplaying profile 只能在**同一 exact context** 下同时具备以下三类人工证据后成立：

1. completed + high + joint-high playing 会话；
2. completed + high + joint-high paused 会话；
3. completed + high + joint-high app_home 会话；
4. 三类 dominant package/Activity 完全一致，package/Activity 稳定度均 ≥75%，screen ratio ≥90%；
5. playing 平均 audio-active ≥70%；
6. paused 与 app_home 平均 audio-active 均 ≤30%；
7. playing 相对 paused/app_home 的 audio 分离均至少 50 个百分点。

满足后，exact context + audio=1 可直接确认 playing；exact context + audio=0 仍需至少 2 个 fresh report 才确认 generic nonplaying。generic nonplaying 可以获得 billing free，但展示层可以继续利用网络/时间画像尝试区分 paused 与 app_home；若无法可靠区分，宁可显示中性 nonplaying，也不能为了漂亮的标签牺牲计费安全。

该机制不得覆盖现有 r7 Type-A learned-audio profile：如果 exact context 没有 app_home 冲突，继续沿用 playing/paused 成对画像；只有共享 exact context 的 app_home 高可信样本明确存在时，才允许切换到 Type-D generic nonplaying 画像。


## r5：Type-D 四状态运行时细分

真机再次验证后，Type-D 共享前台上下文的 paused 与 app_home 会被旧运行时诚实地折叠为 nonplaying。这保证了计费安全，但没有兑现 Learning Center 的四状态诊断目标。

r5 在不扩大免计时授权的前提下增加 **Activity trail 分类层**：

- playing 仍由已经通过三态人工学习的 Type-D audio profile 确认；
- audio=0 仍必须先通过原有两个 fresh report 的 nonplaying 确认门槛；
- 只有人工 paused / app_home 会话的 Activity trail 覆盖率与稳定度均达到 75% 以上，且两类 dominant trail 不冲突时，才允许把已确认的 nonplaying 进一步标为 paused 或 app_home；
- trail 缺失、未知、冲突或不匹配时继续输出 nonplaying，绝不猜测；
- PPS/TCP/UDP/BPS 不参与 paused 与 app_home 的细分，也不能获得新的 free authority；
- 新会话把 trail 摘要追加到 learning-sessions.csv 41–43 列；旧 29/40 列会话可从最新高可信 calibration-v5.csv 会话回溯，避免要求用户重采。

因此 r5 的安全层次是：**Type-D learned nonplaying 决定“是否可免计时”，Activity trail 只决定“免计时状态叫什么”**。


## r6：Activity trail 前缀画像泛化

r5 真机验证发现，Activity trail 是“最近历史窗口”而不是静态页面 ID：同一个腾讯 App 首页，人工学习时可出现 `Home~Exit~Home~Exit`，而后续真实返回首页时出现 `Home~Exit~Home~Main`。两者的最新三段路径一致，但最老历史残留不同。整条字符串 exact match 会因此退回 `nonplaying`。

r6 保留 r5 的计费安全边界，只改分类层：

- trail 按 Agent 当前的 newest-first 顺序计算“从最新 Activity 开始”的最长公共前缀；
- 得分 = 公共前缀长度 / 人工画像 trail 长度；
- 人工画像至少需要 2 个 Activity，只有单个共享前台 Activity 不具备分类权；
- paused/app_home 某一类得分必须 ≥60%，并且至少领先另一类 20 个百分点，才允许细分；
- 不满足最低分、领先幅度不足或两类冲突时继续输出 `nonplaying`；
- exact match 自然得到 100%，因此完全兼容 r5 已验证的暂停场景；
- PPS/BPS、App 名称、Activity 名称关键词都不参与这一步，也不新增 free authority。

真机腾讯样例：

- paused 人工画像：`HomeSingleTaskActivity~MainActivity`
- app_home 人工画像：`HomeSingleTaskActivity~TVCommonExitActivity~HomeSingleTaskActivity~TVCommonExitActivity`
- app_home 实时：`HomeSingleTaskActivity~TVCommonExitActivity~HomeSingleTaskActivity~MainActivity`

实时首页对 app_home 得分 75%，对 paused 得分 50%，领先 25 个百分点，因此 r6 可细分为 `app_home`。如果实时只剩共同的 `HomeSingleTaskActivity`，则两类都达不到 60%，继续保持 `nonplaying`。


## r7：Type-D 播放→暂停时序状态机

r6 真机验证进一步暴露了 Activity trail 的边界：腾讯视频从 App 首页进入播放，再按暂停时，package、Activity、UI Structure 以及 Activity trail 都可能保持完全不变；唯一可靠变化是已经确认的 playing 随后出现 audio 1→0。此时继续单独依赖 trail 会把暂停错误地“黏”在 app_home。

r7 不扩大任何免计时权限，只增加 RAM-only Type-D 时序分类状态：

- 每个 fresh、已确认的 Type-D playing report 记录最近播放时间与当时 Activity trail；
- audio=0 仍必须先通过原有两个 fresh report 的 nonplaying/free 门槛；
- 在门槛通过后，如果距最近 playing ≤45 秒、当前 trail 非 none 且与最后播放 trail 完全不变，则优先细分为 paused；
- 一旦通过该播放→暂停转移确认 paused，只要 audio 继续为 0 且 trail 仍与最后播放 trail 相同，即使超过 45 秒也保持 paused；
- 如果后续真实页面导航让 trail 发生变化，则释放 paused 语义锁，再由人工 learned trail 画像判断 app_home / paused；
- 若没有最近 playing、trail 缺失或证据冲突，仍回退到 learned trail 或 generic nonplaying；
- 这些状态只保存在 /var/run 的 fusion.state schema v5 中，不写电视、不写持久存储；
- PPS/BPS 仍不参与 Type-D paused/app_home 分类，也不产生 free authority。

这条规则专门解决真实顺序：app_home → playing → paused，且三者可能共享同一个 Activity、UI 不可用、trail 在播放/暂停之间不更新的场景。

## r8：AccessibilityEvent 只读诊断探针

r7 真机确认了 playing → paused 的时序分类，但 paused → app_home 在腾讯视频上仍可能完全看不到 package、Activity、Activity trail、UI Structure 或 audio 的变化。继续调 N1 阈值无法凭空创造信息。

r8 暂不改变四状态和计费决策，只扩展电视 Agent 诊断信号：
- Agent 0.3.7 在现有 AccessibilityService 的 onAccessibilityEvent 中仅保存最新事件元数据：package、class、单调 sequence、event type、window id、content-change types 和 age；
- 不读取 text/contentDescription，不新增日志、SQLite、文件历史或离线队列；
- TVG5 将这些字段随 latest-only 心跳发送给 N1；
- N1 只在 bridge-report 中展示，Fusion 和 billing 明确不读取 AccessibilityEvent 字段；
- 只有事件 package 与当前前台 package 一致、事件年龄不超过 30 秒时才上报有效事件，否则归零；
- TVG1–TVG4 保持向后兼容。

目标不是立即判定 app_home，而是先在真机对比 paused 与“返回 App 首页”时事件 type/class/seq/window/content-change 是否形成稳定、可泛化的差异。

## r9：UI 结构画像泛化

r8 真机继续验证了 UI Structure 的价值与 exact fingerprint 的边界：同一视频 App、同一播放器 Activity 的暂停界面可以长期稳定保持相同的节点结构（例如 node/clickable/focused/view-id 计数），但 32 位 structure fingerprint 在重新进入播放器、控件树细节变化或 App 演进后可能改变。把 hash 当成长期唯一身份会把真实暂停退回 unknown。

r9 保留 exact fingerprint 作为最高置信证据，同时增加保守的结构画像回退：

- Billing 将 Agent 已经上报的 node_count、clickable_count、focused_count、view_id_count 一并传给 Fusion；电视端 Agent 与 TVG5 协议不需要变化；
- learned UI 仍只读取 completed + network-high + joint-high + UI-high 的人工学习会话，并继续以 exact package+Activity 为边界；
- exact fingerprint 唯一命中时沿用原路径；同一 fingerprint 若曾出现在多个人工标签下，仍直接冲突并 fail-closed，结构相似度不得覆盖该冲突；
- fingerprint 未命中时，把运行时四项结构计数与各高可信 playing/paused/app_home 会话的结构原型比较；
- 单项相似度按相对差异计算，四项取平均；只有最佳标签 ≥90/100 且至少领先第二名 25 分才允许结构匹配，否则保持 unknown；
- playing 的结构匹配可立即确认，因为它只会保持 charge；paused/app_home 仍沿用两个 fresh report 的确认门槛后才可能获得 free authority；
- PPS/BPS、App 名称和 Activity 名称关键词仍不参与 learned UI 结构分类。

真实爱奇艺样本验证了该需求：人工 playing 画像为 4/0/0/1，paused 画像为 26/12/0/8；后续暂停 fingerprint 从已学习值变化为新 hash，但结构连续 60 秒仍保持 26/12/0/8。r9 的目标是把这种明显属于同一 UI 结构簇的 fingerprint 漂移正确泛化为 paused，而不是不断要求用户为每个新 hash 重做 180 秒学习。
