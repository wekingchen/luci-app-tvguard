# TVGuard · r16 最终稳定性验收清单

此清单是发布前的**只读审计**，不要为了检查而重启 N1、重新签发配对码或切换正式控制。

## 已确认的范围（截至 2026-11-18）

- r14 家中 HTTP / Tunnel 公网 HTTPS：N1 + iPhone 真机配对、状态与操作可用。
- r16 LuCI「家长遥控」「远程访问」：桌面/手机 UI 及修复标题遮挡后由用户确认显示正常。
- GitHub CI：核心与静态检查、LuCI 控件/备注名测试、IPK 构建、Bridge 与 Android 6 Agent 集成检查通过。
- 外网使用 `https://tv.rqqr.de`；当前无 Cloudflare Access，公网能打开配对页，实际控制受 TVGuard 自身长期设备授权保护。

## 仍需实机验证的边界

| 项目 | 最小检查 | 通过条件 |
| --- | --- | --- |
| N1 当前版本与 TVGuard 规则 | `cat /usr/share/tvguard/build-id`，`/usr/libexec/tvguard-status status` | r16；模式、额度、计时与正式控制与升级前一致 |
| 防火墙/代理隔离 | `/usr/libexec/tvguard-isolation-audit` | 输出 `ok` |
| 独立遥控 CGI | `curl --noproxy '*' -sS -o /dev/null -w '%{http_code}\\n' 'http://127.0.0.1:18765/cgi-bin/tvg?action=status'` | 匿名请求为 `401`，而不是 `200` 公开状态 |
| Tunnel 容器 | `docker inspect --format '{{.State.Status}}' tvguard-cloudflared` | `running`，其它 Tunnel 不受影响 |
| XFS 持久化 | `mount | grep ' /mnt/mmcblk2p4 '` | 预期 XFS rw 挂载 |
| 浏览器持久授权 | 关闭/重开普通浏览器后进入已配对的地址 | 不重复请求配对（除非浏览器主动清理 Cookie） |
| 设备备注持久化 | LuCI 改名、刷新、之后再次访问 | 名称保留、其它设备未改变；不需要重新配对 |
| iPhone 单一入口 | 按 `docs/IPHONE_SINGLE_ENTRY.md` 验证家中和蜂窝 | 同一图标切换至相应地址，模式/奖励正常 |
| 设备撤销 | 选择可作废的测试设备单独撤销 | 只有被撤销设备需重新配对，其它设备正常 |
| OTA / 断电重启 | **只在自然 OTA/正常维护重启后观察** | XFS、tvguard、Agent、遥控服务、Tunnel 自动恢复 |
| 磁盘写入与留存 | 检查 tvguard 数据目录、电视 Agent 日志策略 | 不出现无界日志/缓存增长 |

## 安全约束

只读检查不输出 Token、配对码或明文 Cookie，也不发起 mode/bonus/stop/restart 等控制操作；安全报告只保存必要字段，分享终端输出前可遮盖设备标识与 IP。

PR #13 继续保持 Draft，待 iPhone 单一入口及上述实机项目完成后再决定合入和正式发布。
