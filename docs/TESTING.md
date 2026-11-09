# TV Guard v0.1 · N1 联调计划

> 状态：v0.1.11 已由用户于 2026-11-09 确认真机完成操作日志、移动端界面和代理兼容检查验收，并完成第一轮正式网络阻断实测：`mode=locked`、`enforce=1`、`armed=1` 时实际 gate 为 `DROP`，电视无法播放网络内容，而手机、电脑保持正常联网。恢复放行、儿童额度自动阻断、firewall reload/重启恢复及可选回程观测仍待专项验收。当前仍为开发构建，不是稳定 Release。

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

自动化测试不替代 N1 真机验收。v0.1.11 的 LuCI 主题渲染、操作日志与代理兼容检查已由用户确认通过，但 iptables-legacy/fw3 下的**正式阻断、代理共存期间的故障恢复与回滚**仍需独立真机验证。

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
9. 重启 N1 后 `/etc/tvguard/state` 恢复上次持久快照；确认不会因重启把已消耗额度清零。
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
- v0.1.11 观察模式下的日志、界面和代理兼容检查已由用户确认在 N1 通过；正式阻断、异常回滚及回程观测仍未完成专项真机验收。CI 通过不能替代这些测试。
