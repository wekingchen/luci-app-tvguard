# TV Guard · 家庭电视时间管理
## v0.1.14-r2 · Agent Bridge 整合 + 明确暂停免计时（开发候选）

- N1 只安装 `luci-app-tvguard_0.1.14-2_all.ipk`，已包含 CGI、Fusion、Home-only billing hint、配对、观察报告和 bridge 服务；电视仍需单独安装原签名的 0.2.8 Agent APK。
- 主包声明 `Conflicts / Replaces: tvguard-agent-bridge`，由 opkg 正规替换旧独立包，不使用 `--force-overwrite`。配对密钥由 N1 生成、保持 0600 且从不打进 IPK；UCI 与持久统计保留。首次迁移时旧 Bridge 的卸载脚本会清理其 RAM 暂存信息，之后电视重新上报即可恢复。
- 本版不修改 v0.1.13 的 Home-only 正式计时和默认非强制断网策略；回退 v0.1.13 时需一并安装旧的独立 Bridge IPK 才能恢复电视联动。
- 本分支已通过首次 N1 真机无损整合迁移；正式发布前继续完成 Home-only 计时与重启恢复复验。


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

> **状态：v0.1.14-r2 整合候选。** 当前 LuCI 顶部页签为“概览 / 设置”；N1 主包已整合 Bridge，首次从 v0.1.13-r21 + 独立 Bridge 升级到单主包的真机迁移已通过。 v0.1.1 已通过 N1 的基础安装、LuCI、RAW 出站计数验证；v0.1.5 完成代理隔离硬化，v0.1.6 完成 LuCI 信息架构重构，v0.1.7 将家长模式明确为持续模式，并把孩子临时多看的需求统一归入奖励时间。 v0.1.8 根据 iPhone 深色主题实机截图重新收紧移动端响应式布局：顶部状态固定 2×2、模式/奖励按钮规则化、卡片改为深浅主题兼容的透明层级，并去掉 Argon 下过重的嵌套标题块。v0.1.9 进一步把 LuCI 顶部导航改成明确的“概览 / 时间规则”双 tab，去掉单独悬着的“时间规则”导航块。v0.1.10 收口移动端文案与视觉：顶部改为“儿童剩余”，家长模式摘要压缩，观察/家长状态提示改为轻量边框样式，减少深色主题中的高饱和色块。 v0.1.11 仅收口操作记录：奖励撤销日志记录具体分钟数，并兼容隐藏旧版本内部事件编号。2026-11-09 用户确认 v0.1.11 在 N1 完成日志、手机端界面与代理兼容检查的真机验收；同日第一轮正式锁定实测也通过：`TVG_GATE=DROP` 时电视实际断网，而手机、电脑保持正常联网。正式锁定测试结束后的安全收尾也已验证：恢复为 `enforce=0 / armed=0 / gate=allowed`，且 `tvguard-compat-check` 再次 `PASS`、`proxy_rules_unchanged=1`。v0.1.12 又完成了正式控制完整手动链路真机验证：`locked` 时 `TVG_GATE=DROP` 且电视断网，不关闭 enforce 直接切换 `parent` 后 gate 原位恢复为 `RETURN`、电视恢复联网；最终退出正式控制后兼容检查仍 `PASS`。儿童额度自动控制也已真机通过：额度耗尽自动 `DROP`，+15 分钟奖励立即恢复 `RETURN`，撤销奖励再次 `DROP`，家长模式可随时放行；最终兼容检查仍 `PASS`。TV Guard 自身 service reload 也已真机通过：daemon PID 不变，locked 时继续 `DROP`，parent 时继续 `RETURN`，最终兼容检查仍 `PASS`。全局 fw3/firewall reload 也已真机通过：fw3 清空并重建 raw 表后，TV Guard include 能按当前持久状态恢复目标电视 hook，locked 继续 `DROP`、parent 继续 `RETURN`，daemon PID 不变，最终兼容检查仍 `PASS`。N1 整机重启持久恢复也已真机通过：parent 模式跨重启恢复 `RETURN`，locked 模式跨重启恢复 `DROP`，已用额度保持不变，开机自启和代理兼容检查均正常。至此 v0.1.12 的**控制执行层**（模式、额度封禁、奖励恢复、reload/reboot、代理隔离）已完成真机闭环并作为稳定基线发布；但它仍按网络活动扣儿童时间，尚未完成最初要求的“系统首页/App 首页/明确暂停不计时”。v0.1.13 开始把经过保守验证的闲置识别正式接入儿童计时。实验性回程观测仍默认关闭。正式恢复链路复测时又暴露 N1 BusyBox `sleep` 不接受 `0.1` 的锁竞争兼容问题；v0.1.12 将锁等待改为整数秒重试并新增回归测试。默认 `enforce=0`、`allow_enforcement=0`、`observe_reply=0`。

## 已实现的基础能力

- LuCI 中文管理页面：顶部聚合今日剩余、当前模式、控制状态和代理隔离；日常模式/奖励优先展示，算法实验、网络诊断和原始日志按需折叠
- 儿童模式、家长模式、手动锁定三种策略；家长模式持续生效，直到手动切回儿童模式
- 工作日 / 周末基础额度、允许时段、每日清零
- 儿童奖励时间 +15 / +30 / +60 分钟，可撤销最近一次未撤销奖励；孩子临时多看统一走奖励，不借用家长模式
- 独立 fw3 RAW PREROUTING 计数链：电视出站总包、TCP、UDP；不覆盖现有 SSR 透明代理、Docker 防火墙链
- **实验性回程观测（默认关闭）**：另在 raw PREROUTING、OUTPUT 增加无动作目标的只计数规则，分别观察经过 N1 的回程包与本地代理回程包；与计时、封禁完全隔离，尚未完成真机验证
- 10 秒间隔的轻量级联网活动影子计时
- **可选的手工校准**：仅用于开发验证，家长可以标记 120 秒的播放、暂停、应用首页、系统首页或待机。视频 App 名称是实验标签，不是日常使用条件；不需要逐个配置所有视频 App
- 设置页按“每日额度 / 可使用时段 / 计时判断 / 每日观看日报 · Bark / 设备绑定”分区，时间输入有格式校验；正式控制和实验回程观测不出现在普通设置页
- 数据持久化及规则重载恢复，模拟环境回归测试和 GitHub Actions 开发版 IPK

## 默认智能平衡策略：设计目标与现状

**当前正式规则（v0.1.14-r2，Bridge 0.2.8-r4 已并入主包）**：正常播放计时；明确识别为电视系统首页或视频 App 首页时不计时；只有 Fusion 输出当前确认态 `paused_confirmed_learned_context` 时暂停免计时；`paused_temporal_hold`、普通 pause hint、`stable_low/idle_overlap`、unknown/ambiguous、Agent 失联/过期均继续计时。网络真正静默仍沿用 `idle_silent` 免计时。家长模式不扣儿童额度。

**v0.1.12 稳定版现状**：控制执行层已真机闭环，但儿童计时仍主要依据网络活动，所以电视停留系统首页也可能持续消耗额度。这是已确认的功能缺口，不应把“断网控制稳定”误认为“智能计时完成”。

**v0.1.14-r2 正式计时规则：**
- fresh Agent + Fusion 明确 `system_home` → `idle_verified/system_home`，不扣儿童时间；
- fresh Agent + Fusion 明确 `app_home` → `idle_verified/app_home`，不扣儿童时间；
- Fusion 当前明确 `paused_confirmed_learned_context` → `idle_verified/paused`，不扣儿童时间；
- `paused_temporal_hold`、普通 pause hint、`stable_low/idle_overlap`、`playing / unknown / ambiguous` → 有网络活动时继续 `charge`；
- Agent missing/stale/invalid 或 bridge 异常 → fail-closed，继续计时；
- bridge 0.2.8-r4 防止 App 首页加载突发覆盖已学习的播放器 Activity；新 Activity 必须连续 3 次 strong-play 才能晋升为播放上下文；
- 网络静默继续沿用既有 `idle_silent`；主动封禁产生的零流量不会被当作可用额度恢复依据；
- 2026-11-12 N1 + 小米电视真机已验证：儿童模式 App 首页 30 秒 `117→117`、正常播放 `117→170`、暂停继续增长、系统首页 30 秒 `297→297`。

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
