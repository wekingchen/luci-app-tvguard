# TV Guard v0.1 · N1 联调计划

> 状态：v0.1.1 已在用户 N1 完成基础安装、LuCI 页面、RAW 出站计数和默认双重封禁开关验证；当前开发分支新增的代理隔离审计、打包加固和可选回程观测仍待下一轮 N1 验收。尚未证明可投入正式家庭控制，IPK 仍是开发构建，不是稳定 Release。

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
5. 家长模式授权 30/60/120 分钟，过期转儿童模式且不会清除儿童已用时长。
6. 手动锁定优先于儿童奖励；奖励不能解除锁定。
7. SSR 透明代理运行时，TV Guard 的计数链在 raw PREROUTING 统计电视进入 N1 的包。
8. `/etc/init.d/tvguard reload` 后 daemon 不重启、代理规则不变；由 fw3 正常 reload 时，独立 include 能恢复 TVG 入口规则。
9. 重启 N1 后 `/etc/tvguard/state` 恢复上次持久快照；确认不会因重启把已消耗额度清零。
10. 检查停服务时的策略保持，卸载时所有 TVG 规则均被清除而不触碰其他链。
11. 若使用电视前台场景推断，必须标注“疑似”，且不得直接启用不可信的免计时规则。

## 四、代理不干扰验收（下一轮只需做一次）

不需要逐个测试视频 App。升级候选版后，先保持 `enforce=0`、`allow_enforcement=0`、`observe_reply=0`，验证：

```sh
/usr/libexec/tvguard-status isolation
/usr/libexec/tvguard-fw inspect
uci -q get tvguard.main.enforce
uci -q get tvguard.main.allow_enforcement
uci -q get tvguard.main.observe_reply
```

期望依次为 `ok`、`allowed`、`0`、`0`、`0`。

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
/usr/libexec/tvguard-fw sync
/usr/libexec/tvguard-fw inspect-reply
/usr/libexec/tvguard-fw sample-reply
/usr/libexec/tvguardctl status
```

确认 `TVG_RX_LAN`、`TVG_RX_LOCAL` 都没有 `-j` 或其他目标，且原有 TVG_GATE 为 allowed。注意 `ready` 只意味着两条规则存在；`reply_coverage=unverified` 不会因为有回程流量而变成已验证。

快速撤回观测规则：

```sh
uci set tvguard.main.observe_reply='0'
uci commit tvguard
/usr/libexec/tvguard-fw sync
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
- 不区分电视是大人还是孩子，家长必须主动切换家长模式。
- N1 单网口旁路由仅能观察经过它的 IPv4 流量；电视绕过 N1 时控制无效。
- 不基于 PPS 单阈值直接判断免计时。
- 已完成 v0.1.1 的部分 N1 实机初测，但后续开发包及新增回程观测尚未完整验收；CI 通过不能替代 N1 测试。
