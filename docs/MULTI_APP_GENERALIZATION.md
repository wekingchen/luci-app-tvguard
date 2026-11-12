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
