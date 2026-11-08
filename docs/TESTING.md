# TV Guard v0.1 · N1 联调计划

> 状态：开发分支联调计划，**未在用户 N1 上执行、未证明可投入实际家庭控制**。IPK 是构建产物，不是正式 Release。

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
8. `/etc/init.d/tvguard restart` 后状态正常，`/etc/init.d/firewall reload` 后入口规则恢复。
9. 重启 N1 后 `/etc/tvguard/state` 恢复上次持久快照；确认不会因重启把已消耗额度清零。
10. 检查停服务时的策略保持，卸载时所有 TVG 规则均被清除而不触碰其他链。
11. 若使用电视前台场景推断，必须标注“疑似”，且不得直接启用不可信的免计时规则。

## 四、正式封禁前的放行路径

本开发版本存在额外上锁开关：
```sh
uci -q get tvguard.main.enforce
uci -q get tvguard.main.allow_enforcement
```
默认都是 `0`。**在完成上述现场测试之前，不要自行设置为 `1`。**

后续验证通过后才会提供受控的“启用”流程及失败回滚步骤；当前版本不建议开启强制模式。

## 五、恢复与卸载

已安装且希望保持电视可联网时，需先检查其它插件和原先的旧封禁规则。TV Guard 自身可用以下操作退出拦截：
```sh
/usr/libexec/tvguardctl enforce off
/usr/libexec/tvguard-fw inspect
```
应看到 `allowed`，但这不代表 SSR、主路由或其它规则一定放行。

卸载由 `prerm` 停止服务并移除 TVG 专用链；**不能使用 `iptables -F` 清空防火墙**。

## 六、仍未解决的功能限制

- 当前计时主要依据网络活动会话，尚无经证实的“小米系统首页 / App 首页 / 视频暂停”可信自动识别。
- 不区分电视是大人还是孩子，家长必须主动切换家长模式。
- N1 单网口旁路由仅能观察经过它的 IPv4 流量；电视绕过 N1 时控制无效。
- 不基于 PPS 单阈值直接判断免计时。
- 尚未对 LEDE R26.11.3 的实际 rpcd、LuCI、fw3 重载、opkg 安装进行真机验收。
