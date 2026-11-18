# TVGuard · v0.1.16-r16 稳定版验收记录与后续观察

本项目在 2026-11-18 已完成当前 N1 环境的核心功能验收；用户明确反馈 **N1 重启后运行正常**。后续监测继续遵循只读优先，不为了测试主动重启、清空授权或改变正式控制。

## 已确认的范围（截至 2026-11-18）

- r14 家中 HTTP / Tunnel 公网 HTTPS：N1 + iPhone 真机配对、状态与操作可用。
- r16 LuCI「家长遥控」「远程访问」：桌面/手机 UI 及修复标题遮挡后由用户确认显示正常。
- N1 正常重启后的 TVGuard 使用：用户确认正常；不把这一条扩大解释为对未来所有 OTA、异常断电或长时间运行的验证。
- GitHub CI：核心与静态检查、LuCI 控件/备注名测试、IPK 构建、Bridge 与 Android 6 Agent 集成检查通过。
- 外网使用 `https://tv.rqqr.de`；当前无 Cloudflare Access，公网能打开配对页，实际控制受 TVGuard 自身长期设备授权保护。

## 后续维护时可持续复查的边界（不是本轮发布阻塞项）

| 项目 | 最小检查 | 通过条件 |
| --- | --- | --- |
| N1 当前版本与 TVGuard 规则 | `cat /usr/share/tvguard/build-id`，`/usr/libexec/tvguard-status status` | r16；模式、额度、计时与正式控制与升级前一致 |
| 防火墙/代理隔离 | `/usr/libexec/tvguard-isolation-audit` | 输出 `ok` |
| 独立遥控 CGI | `curl --noproxy '*' -sS -o /dev/null -w '%{http_code}\\n' 'http://127.0.0.1:18765/cgi-bin/tvg?action=status'` | 匿名请求为 `401`，而不是 `200` 公开状态 |
| Tunnel 容器 | `docker inspect --format '{{.State.Status}}' tvguard-cloudflared` | `running`，其它 Tunnel 不受影响 |
| XFS 持久化 | `mount | grep ' /mnt/mmcblk2p4 '` | 预期 XFS rw 挂载 |
| 浏览器持久授权 | 关闭/重开普通浏览器后进入已配对的地址 | 不重复请求配对（除非浏览器主动清理 Cookie） |
| 设备备注持久化 | LuCI 改名、刷新、之后再次访问 | 名称保留、其它设备未改变；不需要重新配对 |
| iPhone 单一入口 | 在 Safari 将 tv.rqqr.de 加入主屏幕 | 统一 HTTPS 访问，首次可能需要独立配对；用户尚未反馈图标安装结果 |
| 设备撤销 | 选择可作废的测试设备单独撤销 | 只有被撤销设备需重新配对，其它设备正常 |
| 正常重启 / OTA / 异常断电 | 正常重启已由用户确认运行正常；后两项仅在自然发生时观察 | 不以一次正常重启推断未来 OTA、断电恢复能力 |
| 磁盘写入与留存 | 检查 tvguard 数据目录、电视 Agent 日志策略 | 不出现无界日志/缓存增长 |

## 安全约束

只读检查不输出 Token、配对码或明文 Cookie，也不发起 mode/bonus/stop/restart 等控制操作；安全报告只保存必要字段，分享终端输出前可遮盖设备标识与 IP。

当前功能已达到用户认可的收尾条件；此记录保留后续复查项目，不阻止稳定版正式发布。
