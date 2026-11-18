# TV Guard · 家庭电视时间管理

## 当前稳定版 · v0.1.16-r16

- **N1 主包**：luci-app-tvguard_0.1.16-16_all.ipk；原有 Android 6 电视 Agent 0.3.7 保持固定签名，已安装则无需重复安装。
- **真实验收**：儿童模式与正式控制、Adaptive 低码率计时和高可信暂停/首页免计时、Bark 日报、LuCI 两页桌面/手机 UI、家长配对与设备管理、家中直连和 tv.rqqr.de 外网 Tunnel 均已验证；用户于 2026-11-18 确认 N1 重启后功能正常。
- **外网**：https://tv.rqqr.de（无需家庭公网 IP），当前未配置 Cloudflare Access；操作仍须 TVGuard 配对授权。不要发布 LuCI、RPCD、SSH、Docker Socket。
- **iPhone 入口**：建议在 Safari 将 https://tv.rqqr.de 添加到主屏幕。该用户侧操作不需要 N1 软件新功能，尚未提供单独的桌面图标验收证据。
- **维护**：以后以 Bug 修复与 OpenWrt/Agent 兼容为主；不再为优化单次样本放宽计时安全门槛。
- [正式 Release 说明](docs/RELEASE_0.1.16.md) · [家长遥控](docs/PARENT_REMOTE.md) · [远程访问](docs/REMOTE_ACCESS.md) · [稳定性验收记录](docs/FINAL_STABILITY_REVIEW.md)


## v0.1.16-r16 · 标题遮挡修复与可编辑设备备注

- r15 真机截图显示两页主标题被 LuCI 主题的全局 header/h2 样式覆盖，出现跨页面的蓝色遮挡栏。r16 将两页标题改为带 role=heading 的独立 div 元素，并收紧 CSS 作用域。
- LuCI「已授权的家长设备」新增「修改名称」，支持中文和空格，例如「妙妙的 iPhone」。最长 24 个界面字符、后端上限 96 UTF-8 字节。
- 备注持久保存于 N1 XFS 的独立受限文件，不修改授权 Token、会话、代际或有效期，不需要重新配对；撤销时清除对应备注。
- RPCD 只允许对合法设备标识执行 rename-device，服务器拒绝恶意字符、无效设备与过长名称；不会把改名能力开放给公网遥控 API。
- 新增标题主题兼容、修改设备名、中文持久化、非法输入拒绝与撤销清理测试；本轮不修改计时、电视 Agent、Tunnel Token 和 Docker 逻辑。r16 的 LuCI UI 已于 2026-11-18 获用户真机确认正常。

## v0.1.16-r15 · 家长遥控与远程访问 UI 产品化（历史阶段）

- **已真机验收的功能基线（r14）**：N1 家中 HTTP 直连及 iPhone 配对/模式/奖励、Cloudflare Tunnel 公网 HTTPS `https://tv.rqqr.de` 均正常使用；当前方案不启用 Cloudflare Access，公网操作继续依赖 TVGuard 自身配对授权。
- **r15 主要变化仅涉及 LuCI UI**：家长遥控与远程访问两页共享响应式视觉体系；桌面端卡片与摘要、手机端单栏/可点击的大按钮；状态、访问信息、配对设备、Token/日志维护合理分区。
- 家长遥控页新增清晰的三项状态、局域网入口与复制提示、5 分钟配对码倒计时、设备空状态与每台设备单独撤销；有危险性的操作保留确认。
- 远程访问页将外网入口、专用 Docker 容器状态和维护操作分层；高级 Token/诊断信息默认折叠，容器运行不被误报为 Cloudflare 连接 Healthy；直接展示既有外网域名。
- **核心计时、Adaptive 识别、RAW/正式控制、电视 Agent、Cloudflare Token、Docker 命令及 RPC 权限均未改动**。r15 需新一轮 LuCI 桌面/手机实际视觉验收，不能将源码/CI 测试等同于真机像素级验收。
- 后续阶段才推进 iPhone 单一主屏入口和最终全链路长期稳定性复查。详见 [家长遥控](docs/PARENT_REMOTE.md)、[远程访问](docs/REMOTE_ACCESS.md)。

## v0.1.16-r14 · 已真机验收的功能历史

- r14：手机端按访问地址区分「内网直连」/「Cloudflare Tunnel」；配对响应格式异常时通过只读状态确认；LuCI 管理长期授权设备列表及单独撤销。
- r13：修复 N1 实机 CGI XFS awk 存储检查错误，改为真实 BusyBox awk 与生产函数回归测试。
- r12：配对 Cookie 限定到 CGI 路径、完善 CSRF 和错误恢复。
- r11：状态字段最小化及会话撤销代际保护。
- r10-r7：逐步完善白名单 API、OpenWrt/uhttpd 兼容、HTTP 直连与安全约束。
- r6：Metrics 强制为 127.0.0.1:20241，并移除真机已迁移完成的一次性安全重建入口。
- 此前 r3-r5 Cloudflare Tunnel 管理与容器隔离演进记录保留在历史提交中；家长控制的具体使用与安全边界以当前文档为准。

## v0.1.15-r11 · 多 App 泛化与独立 App 首页画像（历史版本）

- N1 主包：`luci-app-tvguard 0.1.15-11`，build-id：`v0.1.15-r11-standalone-app-home-profile`；Bridge/Fusion 已整合进主包，不再单独安装 Bridge IPK。
- 电视 Agent：`0.3.7` / versionCode 20，沿用固定签名；Accessibility 自恢复、UI Structure、TVG5 诊断与 bounded-RAM 约束保持不变。
- 真机已完成爱奇艺、腾讯极光、芒果 TV 三条不同识别路径的儿童模式回归：正常播放计时、稳定暂停不计时、恢复播放重新计时；未发现真实播放被误判为 free。
- 系统首页已验证稳定不计时；r11 新增 standalone app-home profile 后，芒果独立 `ChannelHomeActivity` 首页经高可信人工 app_home 学习可稳定 `idle_verified/app_home`，首页停留 60 秒 `watch_seconds +0`。
- r11 不按 App/Activity 名称猜首页：只有 exact package+Activity 的 completed/high/joint-high app_home 会话、无同 context playing/paused 冲突、学习音频活跃率低，并在运行时连续两个 fresh audio-off report 后才授予 app_home/free。
- 当前仍保守 fail-closed：unknown、stale、上下文不完整或证据冲突继续 charge。暂停/首页从播放切换时存在约 10～22 秒确认延迟，暂不为了单次样本继续调参。

## 历史：v0.1.15-r1 · 多 App 泛化：共享上下文 generic nonplaying

- 新增 Type-D shared-context profile：只有同一 exact package+Activity 下同时存在 high/joint-high 的 playing + paused + app_home 三类人工会话，且 playing audio 高、paused/app_home audio 低并强分离时，才启用 generic nonplaying。
- Type D 下 audio=1 直接确认 playing；audio=0 第 1 个 fresh report 继续 charge，第 2 个 fresh report 才确认 `nonplaying` 并正式免计。网络即使表现 active/high PPS 也不能单独覆盖这份三态人工真值。
- `nonplaying` 是诚实的计费语义：系统知道“当前不是播放”，但不伪造 paused 或 app_home。UI 显示“已确认非播放 · 已暂停计时”。
- 腾讯极光真机已完成三态 180 秒学习：三态均为 `com.ktcp.video / HomeSingleTaskActivity`、上下文稳定 100%、joint=high；playing audio=100%，paused=5%，app_home=0%。静音继续播放连续 5 个 fresh report 仍 audio=1。
- r7 的芒果 Type-A playing/paused profile 保持不变；Type-D 只在同 exact context 存在高可信 app_home 冲突时启用，不用品牌/App 白名单。

## v0.1.14-r7 · Agent 联合学习 + 更快暂停确认（稳定基线）

- N1 只安装 `luci-app-tvguard_0.1.14-7_all.ipk`，已包含 CGI、Fusion、billing hint、配对、观察报告和 bridge 服务；电视继续使用同一签名的 0.2.9 Agent APK（versionCode 12）。
- r6 把 r4 已采集的 Agent 联合特征真正写入可复用学习模型：在原 18 列 `learning-sessions.csv` 后追加 joint quality、Agent 覆盖率、dominant package/Activity、audio/screen 比例和前台切换次数；旧 18 列历史行继续兼容，但不会获得新的 Agent 暂停授权。
- 只有人工标注的 playing 与 paused 会话在**同一 exact package+Activity** 下均为高可信联合样本，且音频活跃率存在强分离（playing 高、paused 低）时，Fusion 才启用 learned-audio profile。此时 audio=0 需连续 2 个新 Agent 心跳才确认 paused；网络即使突然升到高 PPS 也不能覆盖该人工学习出的暂停证据。audio=1 则立即恢复 playing，并保护 576p/720p 低码率播放不因低 PPS 漏计。
- app_home / system_home 仍要求 fresh + full_context；package-only / unknown Activity 永远不能授予首页或暂停免计时。没有成对高可信 Agent 样本时，继续走原有保守网络/Fusion 路径，不把 audio=0 写死成暂停。
- 2026-11-12 小米电视 + 芒果 TV 真机已确认四态上下文：播放/暂停同为 `com.hunantv.license / com.mgtv.tv.vod.activity.VodDynamicActivity`，区别为 audio 1/0；App 首页为 `com.mgtv.tv.launcher.ChannelHomeActivity`；系统首页为 `com.mitv.tvhome / com.mitv.tvhome.NewMyAppActivity`。r6 用这些现象验证“学习特征设计”，代码本身不包含芒果包名或 Activity 白名单。
- r5 的 Bridge clean-stop 修复与 r4 的 TVG2 前台诊断全部保留。
- r7 只收紧 learned-audio 专属暂停确认：从 3 个新 Agent report 调整为 2 个；旧的网络/时序暂停路径仍保持 3 个。2026-11-12 真机静音播放 50 秒期间 `audio_active` 始终为 1，因此该优化不会把“静音但仍播放”直接当成暂停；仍需 exact package+Activity 的成对高可信人工画像才生效。


## v0.1.13-r21 · Home-only 计时、儿童累计时长与双 Bark 日报（历史基线）

- **每日正式推送**：仅在前一天儿童模式有观看记录时推送；零记录当天不通知，也不会用设定额度截断累计时长。标题：`小明的电视观看小结`；内容示例：`11月11日，小明全天累计看了约2小时1分钟电视。`。家长模式不参与统计；这是网络活动计时的估算值，而非严格的播放时长。
- **手动测试**：LuCI「设置 → 每日观看日报 · Bark → 发送测试推送」，请先保存服务器和推送 ID。点击即由 N1 重新采集一次并持久化当天最新儿童计时，发送「截至某月某日 HH:MM」的测试通知；今日没有儿童观看记录则不发送，并在 LuCI 明确提示。即使日报开关未打开也可以测试连接，测试不占用每日正式日报去重标记。
- **安装**：主包为 `luci-app-tvguard_0.1.13-21_all.ipk`。儿童累计时长与 Bark 日报只依赖主包及 OpenWrt 依赖（包括 curl）；要启用已真机验证的系统首页/App 首页免计时，还需电视端 Agent 0.2.8 与 N1 bridge `tvguard-agent-bridge_0.2.8-4_all.ipk`。

- LuCI 概览新增 **今日累计观看** 和上一完整自然日时长。计时判断复用现有儿童 `charge` 状态，只在儿童模式下计时，家长、锁定模式均不计入。`watch_seconds` 与儿童 `used_seconds` 一致；观察模式超过额度也继续累计，不截断实际统计。
- **这不是严格的播放时长**：网络活动可能包含后台流量，Agent 尚未确认的暂停仍按保守规则计时；家长模式不计入。升级至 r19 时会丢弃 r18 可能包含家长时间的上一日旧归档，避免误报。
- 在「设置 → 每日观看日报 · Bark」设置孩子称呼、Bark 服务器根地址、设备推送 ID 和推送时间，启用后每天按 N1 本地时间发送**前一天完整自然日中仅儿童模式的累计时长**，默认 00:05；即使超过每日额度，也按完整累计时长发送。关闭通知时不发送请求、不影响本地累计。
- 推送仅由 N1 发出，使用 `curl` HTTP POST 与 Bark 官方 `/push` 接口；失败每 300 秒最多重试一次，成功记录日期避免重复；整个功能不会开启实际断网，也不会向电视写入额外日志。
- Bark 推送 ID 保存在 N1 的 UCI 配置（以及现有配置持久备份）中，不进入状态 JSON 或操作记录。r21 最多支持两个 ID：两个设备会收到同一份日报；若其中一台发送失败，5 分钟后只补发失败设备。公网服务器应启用 HTTPS。网络长期离线可能造成未及时发送，不保证 Bark App 最终投递成功。



面向 OpenWrt/LEDE 的电视使用时间管理。当前优先适配 **Phicomm N1 / LEDE R26.11.3 / fw3 / iptables-legacy** 的单网口旁路由环境。

> **当前稳定版本：v0.1.16-r16。** 详细历史验收记录保留在下文，实际使用和安装以顶部稳定版说明、正式 Release 为准。

## 已实现的基础能力

- LuCI 中文管理页面：顶部聚合今日剩余、当前模式、控制状态和代理隔离；日常模式/奖励优先展示，算法实验、网络诊断和原始日志按需折叠
- 儿童模式、家长模式、手动锁定三种策略；家长模式持续生效，直到手动切回儿童模式
- 工作日 / 周末基础额度、允许时段、每日清零
- 儿童奖励时间 +15 / +30 / +60 分钟，可撤销最近一次未撤销奖励；孩子临时多看统一走奖励，不借用家长模式
- 独立 fw3 RAW PREROUTING 计数链：电视出站总包、TCP、UDP；不覆盖现有 SSR 透明代理、Docker 防火墙链
- **实验性回程观测（默认关闭）**：另在 raw PREROUTING、OUTPUT 增加无动作目标的只计数规则，分别观察经过 N1 的回程包与本地代理回程包；与计时、封禁完全隔离，尚未完成真机验证
- 10 秒间隔的轻量级联网活动影子计时
- **四状态智能识别学习**：家长只选择系统首页 / App 首页 / 正常播放 / 视频暂停和采集时长；N1 保留原有网络窗口，同时自动同步 fresh Agent 的 package、Activity、audio、screen、report seq。App 不再需要手工选择；Agent 不可用时自动降级为 network-only 学习，不伪造联合高可信样本
- 设置页按“每日额度 / 可使用时段 / 计时判断 / 每日观看日报 · Bark / 设备绑定”分区，时间输入有格式校验；正式控制和实验回程观测不出现在普通设置页
- 数据持久化及规则重载恢复，模拟环境回归测试和 GitHub Actions 开发版 IPK

## 默认智能平衡策略：设计目标与现状

**当前正式规则（v0.1.15-r11，Bridge 已并入主包）**：正常播放计时；fresh/full-context Fusion 明确确认的系统首页、已学习 App 首页、严格 paused/nonplaying 画像可以免计。暂停可来自 learned-audio、Type-D recent-play transition 或高可信 learned-UI 结构画像；独立 App 首页可来自 standalone app-home profile。`unknown`、Agent stale/invalid、上下文不完整、UI/学习证据冲突均继续 fail-closed 为 charge。网络低流量本身不授予暂停或首页免计权限；家长模式不扣儿童额度。

**v0.1.12 稳定版现状**：控制执行层已真机闭环，但儿童计时仍主要依据网络活动，所以电视停留系统首页也可能持续消耗额度。这是已确认的功能缺口，不应把“断网控制稳定”误认为“智能计时完成”。

**v0.1.15-r11 正式计时规则（继续沿用严格免计时门槛）：**
- fresh Agent + Fusion 明确 `system_home` → `idle_verified/system_home`，不扣儿童时间；
- fresh Agent + Fusion 明确 `app_home` → `idle_verified/app_home`，不扣儿童时间；
- Fusion 当前明确 `paused_confirmed_learned_context`，或 exact context 的成对高可信人工 playing/paused 会话学出 audio profile 后连续 2 个新心跳得到 `paused_confirmed_learned_audio_context` → `idle_verified/paused`，不扣儿童时间；
- `paused_temporal_hold`、普通 pause hint、`stable_low/idle_overlap`、`playing / unknown / ambiguous` → 有网络活动时继续 `charge`；
- Agent missing/stale/invalid 或 bridge 异常 → fail-closed，继续计时；
- Bridge/Fusion 继续防止 App 首页加载突发覆盖已学习的播放器 Activity；新 Activity 必须连续 3 次 strong-play 才能晋升为播放上下文；package-only/unknown Activity 永远不能产生首页或暂停免计时；
- 网络静默继续沿用既有 `idle_silent`；主动封禁产生的零流量不会被当作可用额度恢复依据；
- 2026-11-16 N1 + 小米电视真机已验证：Agent 0.3.7 可稳定取得 full_context；爱奇艺 learned-UI structural、腾讯 Type-D/recent-play transition、芒果 learned-audio 三条路径均完成儿童模式播放→暂停→恢复计时回归，稳定暂停 60 秒均为 `watch_seconds +0`。芒果独立 App 首页经 r11 standalone app-home 学习后同样稳定 `+0`，小米系统首页也已验证 `+0`。

### r4 · Agent-assisted Learning + Foreground diagnostics

- `calibration-v3.csv` 继续保存旧网络特征，保持现有 Adaptive/Shadow 模型与历史数据兼容；
- `calibration-v5.csv` 在原字段后追加 Usage Access、前台来源、诊断状态和 context quality；旧 14 列数据继续兼容；
- `tvguard-learn` 分开统计 Agent 传输在线率、已知 package 覆盖率与完整 package+Activity 覆盖率；只有完整上下文覆盖和稳定度都达标时才称为“高可信 Agent 联合人工学习会话”，fresh + unknown 不再可能误升高可信；
- LuCI 开始学习前直接显示电视 Agent 当前识别的 App/Activity；Agent stale/missing 时仍允许采集，但明确降级为 network-only；
- `scripts/evaluate-generalization.py` 同时支持旧 v3 和新 v5。读取 v5 时直接按真实 package 做 leave-one-app-out，不再依赖人工填写腾讯/爱奇艺/芒果标签；
- v5 与 v3 一样由 N1 持久数据根管理，mmc 暂不可用时只落 `/var/run`，恢复后一次性合并；总 append-only 持久预算仍为 1 MiB；
- Agent package/Activity/audio/screen 与 TVG2 诊断字段都是学习证据，不是独立计费授权；package-only 与 unknown 上下文不会绕过 confirmed-pause / home-only 安全门槛。

## 代理工具隔离是硬约束

TV Guard 的网络控制实现遵循以下不可越界规则：

- 所有 iptables 写操作统一经过一个硬编码的 `raw` 表入口，并使用短时 xtables 锁等待；禁止写 `nat`、`mangle`、`filter`。
- 禁止 `TPROXY`、`REDIRECT`、`MARK/CONNMARK`、`DNAT/SNAT`、`NOTRACK`、策略路由修改、网络 sysctl 修改和全局链清空。
- 核心入口必须同时限定 **电视 IPv4 + br-lan**；正式封禁只可能命中这台电视经过 N1 的 IPv4 流量。
- 回程观测规则没有 `-j` / `-g` 判决目标，只计数；默认关闭，而且不参与儿童计时或 gate。
- TV Guard daemon 不订阅全局 firewall reload，不重启/重载代理服务，也不调用全局 firewall restart/reload。
- FW3 调用 TV Guard include 时，即使 TV Guard 自身同步失败也只记录日志并返回成功；不能把自身故障传播成全局 firewall/代理 reload 失败。
- 正式 `enforce on` 除双开关外还要求运行时隔离审计精确返回 `ok`；未知或异常状态都拒绝开启。
- 安装和卸载只操作经路径/type 校验确认属于 TV Guard 的 `firewall.tvguard` include；同名外部 section 会被保留。
- 运行时只读隔离审计会检查 TVG 规则是否越界；异常时实验观测拒绝启用，核心规则也拒绝继续修改。
- CI 会扫描并拒绝任何未来引入的代理表、策略路由、全局链或代理服务操作。

这些约束用于保证 TV Guard **不重新配置现有代理工具，也不改变其他设备的代理路径**。正式封禁开启后，电视自身被 TV Guard 阻断时当然不会再把该电视流量交给代理，这是产品的预期控制结果，不属于代理配置被修改。

## 保护开关

`/etc/config/tvguard` 中默认：

```uci
option enforce '0'
option allow_enforcement '0'
option observe_reply '0'
```

双开关未同时开启时不允许 TV Guard 主动封禁电视。回程观测开关也默认关闭，其开启不赋予封禁权限。**不要在完成正式网络阻断专项验收及可靠回滚准备前打开正式封禁。**

网络控制仅覆盖实际经过 N1 的 IPv4 数据包。电视如果手动换网关直接走主路由，N1 无法可靠阻止；严格防绕过需要主路由配合。

## 开发和验证

- 代码：[PR #1](https://github.com/wekingchen/luci-app-tvguard/pull/1)
- 构建：PR Checks 下 `package` 产出开发版 IPK（具体版本以相应 Action 产物为准）；v0.1.11 观察模式下的操作日志、移动端界面与代理兼容自检已由用户确认在 N1 通过；后续版本仍需逐版验收。
- `tests/test-controller.sh` 验证额度、奖励以及“高回程流量不能影响计时/gate”；`tests/test-firewall.sh` 验证代理样例规则在同步、观测、gate 切换和卸载前后保持原样。
- `tests/test-proxy-isolation.py` 是源码硬门禁；`tests/test-isolation-audit.sh` 验证 N1 运行时隔离审计；`tests/test-package-safety.sh` 验证安装/卸载不会取得或删除外部 firewall section。
- 候选包内置 `tvguard-compat-check`：仅在三项安全开关均为 0 时运行，执行一次 TVG 自身 sync，并验证 raw/mangle/nat/filter 的所有非 TVG 规则前后完全一致。
- 新增回程观测仅在开发分支和模拟环境中通过测试；N1 尚未启用或验收回程观测，继续保持关闭。
- [通用识别、验证方法及已知限制](docs/CALIBRATION.md)
- [设计与已知限制](docs/DESIGN.md)
- [N1 联调与回滚清单](docs/TESTING.md)

> 开发版 IPK 能打包不代表已在 N1 验证。请勿将其视作稳定可用版本。
