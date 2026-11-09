# TV Guard 技术设计（v0.1 开发基线）

## 已知设备与限制

- 目标：Phicomm N1，LEDE R26.11.3 / OpenWrt 24.10.5，Linux 6.12.114
- 实际防火墙：**fw3 + iptables v1.8.7 legacy**；不能套用 fw4/nftables 的规则
- 单网口旁路由：N1 `192.168.101.99/24`，主路由 `192.168.101.1`，电视 `192.168.101.76`
- 电视 MAC `B0:41:1D:65:8B:94`；已在 N1 配 DHCP 静态规则，但不代表电视不能手动改网关/IP
- SSR 使用 `nat PREROUTING REDIRECT` 和 `mangle PREROUTING TPROXY`：FORWARD 不能覆盖所有代理接管流量
- N1 的 `send_redirects` 曾为 1；实际运行时须校验。即使关闭 ICMP Redirect，也无法阻止电视手动直连主路由
- 不增加智能插座、不依赖电视 App

## 实测数据（2026-11-08）

| 状态 | 腾讯极光 | 爱奇艺 | 芒果 TV |
|---|---:|---:|---:|
| 正常播放 PPS | 180 | 228 | 270 |
| 暂停平均 PPS | 166 | 50 | 25 |
| 暂停后 30 秒 PPS | 154 | 7 | 12 |
| 应用首页 PPS | 53 | 15 | 9 |

电视系统首页约 7 PPS；熄屏待机试验中连续 60 秒为 0 PPS。**PPS 不能区分所有暂停和首页：零发包也可能是网络路径变化。**

## 默认策略：智能平衡

- 可靠确认观看：计时。
- 可靠确认系统首页、视频 App 首页、暂停、熄屏待机：不计时。
- 不能确认：计时（防止误判绕过）。
- 家长模式：不扣儿童额度、不受儿童允许时段限制，并持续生效直到手动切回儿童模式；锁定模式禁联网。
- v0.1.12 稳定基线仍只按联网会话计时；v0.1.13 开始接入保守闲置免计时，但仍**绝不自动把低 PPS 当作闲置**。系统首页需重复设备级证据并与播放特征分离；App 首页/暂停需跨应用证据；连续确认 30 秒后才暂停扣时。
- `enforce=0` 默认只记录；在现场验证后须家长主动启用真实阻断。

## 数据路径

```
电视发出 IPv4 包
   ↓
raw PREROUTING → TVG_RAW (无判决计数) → TVG_GATE (DROP/RETURN)
   ↓
mangle PREROUTING / nat PREROUTING / FORWARD / INPUT
   ↓
SSR 透明代理或正常路由
```

- RAW 早于 NAT/TPROXY 的常见入口，但**只包含实际经过 N1 的流量**。
- 允许时在子链 RETURN，不覆盖其他插件或防火墙的结论。
- 在 `/etc/config/firewall` 注册独立 script include（`reload=1`），不修改 `/etc/firewall.user`。
- 手动封禁和额度耗尽使用同一 gate；不能被「封禁后零流量」自动解锁。
- 计数器归零（防火墙重载）不被解释为电视熄屏。
- **FW3 的旧规则若仍在**，新页面显示“允许”也可能无法联网；安装前先核查。

## 代理隔离硬约束

代理工具兼容不是经验性约定，而是代码结构和 CI 门禁：

1. `tvguard-fw` 的全部 iptables 写操作只能经过 `raw_ipt()`，固定使用 `iptables -w 2 -t raw`；不能选择其他表。
2. TV Guard 不创建或修改 `nat/mangle/filter` 规则，不使用 `MARK/CONNMARK/TPROXY/REDIRECT/DNAT/SNAT/NOTRACK`，不修改 `ip rule`、策略路由、网络 sysctl。
3. 核心 hook 只能是 `PREROUTING -i br-lan -s <电视IPv4> -j TVG_RAW`。运行时审计拒绝宽匹配、重复 hook 或非电视地址。
4. 允许状态下，`TVG_GATE -j RETURN` 只从 TVG 自有子链返回调用链，后续 raw/mangle/nat 规则继续执行。
5. 回程观测仅允许电视目标地址的 target-free 计数规则；观测异常不能影响 `USED_S`、`ACTIVITY`、`BLOCKED`。
6. procd 只监听 `tvguard` 配置，不监听全局 `firewall` trigger。fw3 重载只通过独立 include 恢复 TVG 专属规则；include 即使 TV Guard 同步失败也必须记录后 `exit 0`，不能使全局 firewall/代理 reload 失败。
7. 正式 `enforce on` 在双开关之外必须实时执行隔离审计，只有精确 `ok` 才能进入控制；`unsafe` 或 `unavailable` 均拒绝。
8. 安装/卸载前校验 `firewall.tvguard` 所有权；同名外部 section 不覆盖、不删除。
9. `tvguard-isolation-audit` 只读扫描四张表。任何表无法读取都只能是 `unavailable`，不能按空表判安全；异常布局下核心写操作拒绝继续。
10. CI 同时运行源码隔离扫描、模拟代理规则保留测试、运行时审计测试和 package 所有权测试。

这套设计不能证明任意第三方固件/内核永远不存在实现层 bug，因此真实 N1 仍需验收；但 TV Guard 自身没有获得修改代理配置、代理表或其他客户端路由的代码路径。

## 可选回程观测（当前开发分支，默认不启用）

`tvguard.main.observe_reply=0` 默认关闭；保持以前的计时、RAW 门控、SSR/PassWall/OpenClash 配置不变。**尚未在真实 N1 验证，不能直接宣称已支持完整的双向流量统计。**

经过人工授权后，`tvguard-fw sync` 在 `raw` 中配置两条仅带匹配和注释、**没有跳转目标（无 `-j`）**的计数规则：

| 观测点 | 匹配 | 适用情况 |
|---|---|---|
| `TVG_RX_LAN` | `PREROUTING -i br-lan -d 电视IP` | 到达 N1 且目标为电视的 IPv4 包 |
| `TVG_RX_LOCAL` | `OUTPUT -o br-lan -d 电视IP` | N1 自己（含本地代理）产生、发往电视的 IPv4 包 |

- 不修改已有的 `TVG_GATE`、DROP/RETURN、MARK、路由表，也不使用 `tcpdump` 或 `conntrack`。两规则只计数，匹配结束后仍按原防火墙规则继续处理。
- `TVG_RX_LAN` 与 `TVG_RX_LOCAL` 不是“完整下载流量”的保证。经硬件卸载、旁路、桥接直达主路由、IPv6 或不同路径到达的回包可能没被看到。
- 连续差值独立计时，计数器首次出现、FW3 清空后、异常回跳时不产生虚假瞬时速率；缺少规则显示 unavailable，不解读为电视熄屏。
- 状态字段 `reply_prerouting_pps/bps` 和 `reply_local_pps/bps` 仅用于诊断，`reply_coverage` 恒为 `unverified`；**永不用于 `USED_S`、免计时或防火墙判决**。
- 仅删除自己精确匹配的注释规则，不清空 PREROUTING 或 OUTPUT。旧版本没有 `observe_reply` 选项时视作关闭，升级后也不会自动启用。
- 启用前、写入后都必须通过运行时隔离审计；否则观测规则拒绝创建或立即回滚。

## 控制、计时与日志

- `/etc/config/tvguard` 保存可配置限额、时段和观测参数；`/etc/tvguard/state` 保留额度状态。
- `/var/run/tvguard.state` 每 10 秒刷新；磁盘状态每约 60 秒或封禁状态变化时持久化。
- 当天使用时长以秒保存；工作日、周末独立配置；每天归零并清除未使用完的奖励。
- 儿童日额 = 基础额度 + 奖励（15/30/60，可累加至上限）。
- 手动锁定不能被奖励解除；家长模式不设倒计时。孩子临时多看的需求只通过当日奖励时间处理。
- 操作日志为 `时间戳|事件序号|类型|备注`，最多约 256 KiB 后截取最近 1500 行，避免日志无限增长。
- 重要限制：当前 LuaCI 只能确认操作者具备管理权限，不记录精确的个人身份。
- v0.1.12 对网络活动采取 60 秒静默窗口，系统首页仍可能被计时。v0.1.13 增加 `billing_state=idle_verified`：高可信闲置连续约 30 秒后暂停儿童计时；无法确认仍计时。它仍不是操作系统级“真实亮屏/观看时长”。

## 安全边界

- 只有 `tvguard-status` 可由只读权限调用；变更模式、奖励和执行控制须写权限。
- 绝不向 rpcd ACL 授予 `/bin/sh` 或通配命令执行权限。
- 在设备上不开放额外 Web 端口；使用原有 LuCI 身份认证。
- 兼容旧版本：若状态文件中存在 `MODE=parent` 且 `PARENT_UNTIL>0`，仅保留这一次旧定时会话的原到期行为；新版主动选择家长模式会写 `PARENT_UNTIL=0`，表示持续生效。旧缓存请求 `mode parent 30/60/120` 会被拒绝，避免误转为无限期家长模式。
- 默认观察模式，家长主动确认后才启用防火墙门控。
- 旁路由无法保证对电视全流量的强制控制；严格防绕过应由主路由配合限制该 MAC/IP 直连互联网。
- 当前是开发分支，不应直接部署在生产 N1。

## 开发阶段

1. v0.1：FW3 统计门控、影子计时、儿童/家长/锁定、奖励与 LuCI 基础页面。
2. N1 试点：只读复测、重启恢复、SSR 兼容、页面及日志审核。
3. 深度连接采样：按连接目的地/端口/协议做校准，不使用总 PPS 作为免计时唯一证据。
4. 经过影子识别评估后逐项开启高可信空闲免计时，保留保守回退策略。
5. IPK 构建及发布、用户安装文档、测试与恢复流程。

## 尚需处理的工程风险

- 电视 IP 或进入接口变更时，当前门控暂不自动撤销旧 hook；此版本应保持这两项固定。
- 内存丢失后的磁盘快照最多落后约 60 秒；启动时应核查额度恢复。
- 防火墙规则变更会影响全局转发；在真实 N1 上测试前不得启用 `enforce=1`。
- 已在 N1 验证 v0.1.1 的 opkg 安装、LuCI 打开、RAW 出站统计及双重封禁开关的默认关闭；后续开发分支及被动回程计数仍待单独真机验证。
- LuCI 上传 v0.1.3 曾报 malformed package，但同一用户通过页面文件局部修复继续了标注；包兼容性仍须独立于 CI 检查。

## 当前最高优先级：低码率正常观看不漏计（2026-11-09 决策）

**P0 — 儿童真实观看必须计时，特别是无会员视频 App 的免费 576p / 720p 播放。** 这不是边缘压力测试，而是日常使用场景。原先主要依据 4K 片源标注形成的 Adaptive PPS 阈值，不能默认推广到低码率播放。

现场证据（N1，电视固定 IPv4 `192.168.101.76`，Shadow Soak schema=v2 / Phase 2A）：

- 芒果 TV 576p，已由现场确认画面持续播放、进度条前进：2026-11-09 21:25 与 21:28 两个窗口分别仅 24 / 22 PPS，Adaptive `idle/stable_low`，`billing_state=idle_verified`，`idle_streak_seconds` 从 101 增至 290。当前 `mode=parent`，因此 `used_seconds` 不增加**不能**作为儿童模式漏计已经实证的结论；仍须审计并在 `enforce=0` 下核验儿童计时。
- 同日 4K 正常播放，21:40 与 21:43 两个窗口为 109 / 182 PPS，Adaptive `active`，`billing_state=charge`；`high_ratio_pause` 候选累计数保持 98 不变。结果支持现有模型的清晰度泛化不足，但**不能**单凭此排除缓存、出站包方向和网络路径差异。
- 当前现场阈值 `adaptive_idle_ceiling=70`、`adaptive_active_floor=138`（来自旧模型）；这不是应继续盲目降低的推荐阈值。Shadow Soak 中 `high_ratio_pause` 只是重叠特征，不是暂停概率。

工作顺序（按优先级；修改前先诊断，不能跳过验收）：

1. **P0**：核对 `tvguard-adaptive` 的 `idle/stable_low → billing_state=idle_verified` 路径与儿童模式实际 `USED_S` 增量；在观察模式 `enforce=0` 下验证 576p / 720p 正常播放不能长期被免计时，未知状态应遵循“证据不足则计时”。
2. **P0 观测完整性**：利用固定电视 IP 归属流量；确认 `raw PREROUTING -i br-lan -s 电视IP` 目前只统计出站 IPv4，测试既有 `TVG_RX_LAN` / `TVG_RX_LOCAL` 无动作回程计数器的覆盖程度与硬件卸载、透明代理、IPv6、旁路限制；先独立只读/旁路验证，**不直接拿回程计数驱动计费或 gate**。如需连接级特征，优先考虑轻量、有界、隐私最小化的 IP 五元组/方向/速率/持续性统计；不把加密 TLS/QUIC 负载当作可直接识别的视频内容。
3. **P1**：同时保持 4K/1080p 播放不退化，首页/暂停不能轻易误判为播放；以独立状态标注、跨清晰度与跨 App 反例、离线回放为门槛，拒绝按 App 名称硬编码和直接下调 PPS 阈值。
4. **P2**：暂停免计时继续保留在 Shadow Soak 旁路研究；不能让 `high_ratio_pause` 或未验证的回程观察影响 `USED_S`、`billing_state` 或防火墙。
5. **工程保护**：保留儿童/家长/锁定、奖励及撤销、额度、正式 gate、SSR/代理隔离和已有回滚保障；所有实际防火墙变更必须继续满足原隔离门禁。严禁为了观测新增 NAT/mangle/路由改写。

**可观测性边界**：固定 IP 能识别这台电视**经过 N1** 的包及连接，不等于能观察所有网络路径；能够识别高吞吐连接或疑似视频流量，不等于能从 HTTPS/QUIC 加密流量断言屏幕正在播放、暂停或使用哪个前台 App。长缓冲或本地缓存播放与暂停可能网络表现相同。必须承认不可判定状态，避免“低流量=已确认停止观看”的推断。

## r12 P0 验证候选：先撤销 TX-only 闲置的计费授权

r12 的第一步不是重新调低 PPS 阈值，而是把“识别标签”和“免计时授权”重新分开：

- `tvguard-adaptive`、`tvguard-shadow` 和 Shadow Soak 继续原样输出，用于观察、学习和离线回放；
- 生产代码固定 `TX_IDLE_BILLING_AUTHORITY=0`，不是 UCI/UI 开关；在该门关闭时，只要电视仍有经过 N1 的非静默网络窗口，儿童模式保持 `billing_state=charge`，即使 Adaptive 输出 `idle/stable_low` 或 Shadow 输出首页/idle；
- 旧的智能闲置状态机暂时保留在代码中但没有生产授权，测试可以显式开启它，避免后续恢复时失去回归覆盖；
- `ACTIVITY=silent → idle_silent` 暂时保留为“网络会话结束”边界，而**不是屏幕空闲证明**。这一点仍是 P0 剩余风险：必须用真实 576p/720p 长时间播放确认是否会出现超过当前 `silence_seconds=60` 的无包缓冲间隔；若出现，优先设计有界的 recent-playback hold，而不是让电视关机后无限计时；
- Reply Observer 仍默认关闭且没有 billing authority。r12 只给兼容检查增加 flow-offload 风险报告；若系统启用 software/hardware flow offload 或实际存在 `FLOWOFFLOAD` 规则，只标记观测完整性风险，不自动关闭/修改全局加速。

r12 的 P0 验收硬门槛：真实正常播放（含免费 576p/720p）不得出现 `dangerous_idle_false_hints` 导致的免计时；暂停/首页暂时继续计时属于保守退化，可以接受，但必须显式记录，不能伪装成识别成功。

## 分支生命周期

- `main`：只承载已经完成 N1 真机验收、可作为稳定恢复基线的版本；不直接在 `main` 上做实验。
- `feat/v0.1.13-smart-billing`：v0.1.13 这一代的临时集成分支。P0/P1/P2 的验证成果先汇总到这里，直到 v0.1.13 完成真机验收。
- `feat/v0.1.13-rNN-*`：一次性任务/验证分支，只从当前 v0.1.13 集成分支创建；通过 CI 后以 PR 合回集成分支，合并完成即应删除，不作为新的长期开发线。
- v0.1.13 真机验收完成后：将集成分支合入 `main`，以稳定 release/tag 固化，然后删除 `feat/v0.1.13-smart-billing`；后续版本从最新 `main` 新建自己的集成分支，不沿用旧版本开发线。
- 禁止长期同时维护多个互相分叉的同版本集成分支；若出现临时分支，必须在 PR/文档中明确目标基线和退出条件。
