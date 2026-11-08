# TV Guard · 家庭电视时间管理

面向 OpenWrt/LEDE 的电视使用时间管理。当前优先适配 **Phicomm N1 / LEDE R26.11.3 / fw3 / iptables-legacy** 的单网口旁路由环境。

> **状态：v0.1.6 开发候选。** v0.1.1 已通过 N1 的基础安装、LuCI、RAW 出站计数验证；v0.1.5 完成代理隔离硬化，v0.1.6 在不放宽任何网络安全边界的前提下重整 LuCI 信息层级、日常操作逻辑、设置校验和人话状态反馈。仍待 N1 实机验收。默认 `enforce=0`、`allow_enforcement=0`、`observe_reply=0`。

## 已实现的基础能力

- LuCI 中文管理页面：顶部聚合今日剩余、当前模式、控制状态和代理隔离；日常模式/奖励优先展示，算法实验、网络诊断和原始日志按需折叠
- 儿童、家长限时授权、手动锁定三种策略
- 工作日 / 周末基础额度、允许时段、每日清零
- 家长奖励 15 / 30 / 60 分钟，可撤销最近一次未撤销奖励
- 独立 fw3 RAW PREROUTING 计数链：电视出站总包、TCP、UDP；不覆盖现有 SSR 透明代理、Docker 防火墙链
- **实验性回程观测（默认关闭）**：另在 raw PREROUTING、OUTPUT 增加无动作目标的只计数规则，分别观察经过 N1 的回程包与本地代理回程包；与计时、封禁完全隔离，尚未完成真机验证
- 10 秒间隔的轻量级联网活动影子计时
- **可选的手工校准**：仅用于开发验证，家长可以标记 120 秒的播放、暂停、应用首页、系统首页或待机。视频 App 名称是实验标签，不是日常使用条件；不需要逐个配置所有视频 App
- 设置页按“每日额度 / 可使用时段 / 计时判断 / 设备绑定”分区，时间输入有格式校验；正式控制和实验回程观测不出现在普通设置页
- 数据持久化及规则重载恢复，模拟环境回归测试和 GitHub Actions 开发版 IPK

## 默认智能平衡策略：设计目标与现状

**预期目标**：可靠判断正在观看时计时；可靠判断电视系统首页、App 首页、视频暂停或待机时不计时；无法判断则按使用计时。

**当前 v0.1 仅实现第一阶段：** 根据经过 N1 的电视出站 IPv4 网络活动统计儿童联网使用时长。实验性影子识别器已改成 **App 无关的通用网络状态候选**，并提供留出整个 App 的泛化测试，但不能确证当前前台应用与画面。因此：
- 低 PPS、流量静默、连接数减少 **不等于** 已确认首页或暂停；零流量还可能是电视绕开 N1。
- 当前 `raw PREROUTING` 计数电视**向外发出的** IPv4 包，不是完整视频下行流量。
- 对首页、暂停的校准样本目前只用于后续训练和验证，**不会自动免计时**。
- 家长模式可以主动授权，不扣儿童额度。
- 不增加智能插座，也不安装电视端 App。

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

双开关未同时开启时不允许 TV Guard 主动封禁电视。回程观测开关也默认关闭，其开启不赋予封禁权限。**不要在还未完成 N1 真机验收前打开正式封禁。**

网络控制仅覆盖实际经过 N1 的 IPv4 数据包。电视如果手动换网关直接走主路由，N1 无法可靠阻止；严格防绕过需要主路由配合。

## 开发和验证

- 代码：[PR #1](https://github.com/wekingchen/luci-app-tvguard/pull/1)
- 构建：PR Checks 下 `package` 产出开发版 IPK（具体版本以相应 Action 产物为准）；N1 早期包安装已验证，后续版本仍需逐版验收。
- `tests/test-controller.sh` 验证额度、奖励以及“高回程流量不能影响计时/gate”；`tests/test-firewall.sh` 验证代理样例规则在同步、观测、gate 切换和卸载前后保持原样。
- `tests/test-proxy-isolation.py` 是源码硬门禁；`tests/test-isolation-audit.sh` 验证 N1 运行时隔离审计；`tests/test-package-safety.sh` 验证安装/卸载不会取得或删除外部 firewall section。
- 候选包内置 `tvguard-compat-check`：仅在三项安全开关均为 0 时运行，执行一次 TVG 自身 sync，并验证 raw/mangle/nat/filter 的所有非 TVG 规则前后完全一致。
- 新增回程观测仅在开发分支和模拟环境中通过测试；当前用户 N1 无需升级、启用或采样。
- [通用识别、验证方法及已知限制](docs/CALIBRATION.md)
- [设计与已知限制](docs/DESIGN.md)
- [N1 联调与回滚清单](docs/TESTING.md)

> 开发版 IPK 能打包不代表已在 N1 验证。请勿将其视作稳定可用版本。
