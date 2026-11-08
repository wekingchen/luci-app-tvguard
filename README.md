# TV Guard · 小米电视使用时间管理

适配目标：**斐讯 N1 / LEDE R26.11.3（OpenWrt 24.10.5）/ firewall3 / iptables-legacy / opkg / ARM64**。

> **目前是 v0.1 开发预览版，默认只观察不封禁，不建议直接给家庭生产网络开启正式控制。**
> 开发中的 Draft PR：[#1](https://github.com/wekingchen/luci-app-tvguard/pull/1)。

## 核心行为

- 每日儿童联网会话额度：工作日 60 分钟，周末 120 分钟（可修改）。
- 家长授权模式：30、60、120 分钟，结束后自动切换回儿童模式。
- 时间奖励：+15/+30/+60 分钟；默认每天最多 120 分钟，可撤销上笔奖励，保留操作日志。
- 手动锁定、允许时段、每日自动重置、持久化状态。
- LuCI 后台「服务 → 电视时长 TV Guard」提供中文概览、奖励与设置。
- 默认 `enforce=0` 只记录。如果需要启用真实封禁，开发版要求管理员先从 SSH 显式设置 `tvguard.main.allow_enforcement=1`；**在实机确认安全性之前请勿开启**。

**本版本尚不具备可靠的电视前台状态识别**。虽然设计目标是智能平衡（确认系统首页、App 首页、视频暂停或待机后不计时；无法确认时计时），v0.1 的实际算法仍是联网会话估算计时，会把一些首页及暂停流量计入额度。不要将其解释为真实屏幕观看分钟数。

## 运行与安全限制

- 仅管理**实际经过 N1** 的电视 IPv4 数据包。若电视直接使用主路由 `192.168.101.1`，本插件可能无法控制。
- 使用独立 `raw PREROUTING → TVG_RAW → TVG_GATE`，规避 SSR 透明代理绕过传统 FORWARD 计数。
- 不修改已有 SSR、PassWall、OpenClash 或 Docker 规则；但防火墙重载、旧规则和设备 IP 变动需要实机回归。
- v0.1 暂不支持安全热变更受控电视 IP/入站接口：这两项在 LuCI 只读。
- 额外的 `allow_enforcement` 开关是**开发安全门槛**，不是已经通过安全认证的标志。
- 旁路由的硬件和系统设置不能证明电视全部流量必经 N1；若要严格防绕过，需要主路由配合。

## 文件布局

```
Makefile
root/etc/config/tvguard                   # UCI 配置
root/etc/init.d/tvguard                  # procd
root/usr/libexec/tvguardctl              # 计时、额度、奖励与模式
root/usr/libexec/tvguardd                # 10 秒循环
root/usr/libexec/tvguard-fw              # FW3 统计及封禁
root/usr/libexec/tvguard-status          # 只读 RPC 入口
root/usr/share/rpcd/acl.d/               # 精确 ACL
htdocs/luci-static/resources/view/tvguard/ # 中文页面
scripts/build-ipk.sh                     # 开发用 IPK 组包
docs/DESIGN.md                           # 实测数据和状态规则
```

## 开发打包

GitHub Actions 的 `TV Guard static checks` 流程执行 Shell/JavaScript/JSON 静态检查，并构建 **all 架构开发版 IPK** 到工作流 Artifacts。它不依赖 N1 私有的 SDK，但也不意味着已验证在该固件上兼容。

本地（Linux/macOS 可用 GNU ar）：

```sh
sh scripts/build-ipk.sh 0.1.0
```

生成 `dist/luci-app-tvguard_0.1.0-1_all.ipk`。

## N1 观察模式验收（暂勿启用封禁）

在准备测试设备、完成备份后，安装 IPK 并确认 LuCI 菜单出现。后台接口可读：

```sh
/usr/libexec/tvguardctl status
/usr/libexec/tvguardctl log
/etc/init.d/tvguard status
iptables -t raw -S PREROUTING | grep TVG_RAW
```

应能观察到计数增长，但执行 `uci -q get tvguard.main.enforce` 应为 `0`。不要在验证前将其修改为 1。

## 尚未验证

- 真实 N1 上的 LuCI 权限、服务安装/卸载行为和 IPK ABI/依赖兼容性
- 停止服务、跨日、意外重启及 FW3 重载边界
- 主路由绕行检测，透明代理残留连接与功能共存
- 高可信系统首页/App 首页/暂停自动免计时

详细设计及观察限制见 [docs/DESIGN.md](docs/DESIGN.md)。
