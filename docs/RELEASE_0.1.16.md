# TVGuard v0.1.16-r16 · 稳定版交付记录

## 交付内容

- **N1**：`luci-app-tvguard_0.1.16-16_all.ipk`，Build ID `v0.1.16-r16-title-and-device-labels`。
- **小米电视 Agent**：保持固定签名 `0.3.7`（versionCode 20）；原先已装同版本且权限正常，无需重复安装。
- **GitHub Release**：正式版标签 `v0.1.16`，同时提供 N1 主 IPK 与已验证固定签名的 Agent APK；Bridge/Fusion 已包含在 N1 主包。
- **受控的数据与服务**：家长设备授权/备注、TVGuard 计时和学习数据、Bark 设置、Cloudflare Tunnel Token 均在 N1 保留；软件升级不要求重新配对或重建 Docker 容器。

## 用户真机确认

| 功能 | 验收说明 |
| --- | --- |
| 儿童、家长、锁定模式与正式控制 | N1 先前通过模式切换、电视断网/恢复及代理隔离检查 |
| Adaptive / Fusion / Agent | 低码率正常计时，系统首页、视频首页与高可信暂停免计时；多款 App 的播放/暂停/恢复已测试 |
| Bark 日报与观看总时长 | 用户曾收到实际每日推送，统计仅按儿童模式计时规则 |
| 家中 HTTP 遥控 | `http://192.168.101.99:18765/`：访问、配对与控制正常 |
| 外网 Cloudflare Tunnel | `https://tv.rqqr.de/`：公网访问、配对与控制正常 |
| LuCI 两页 UI | 桌面与手机显示、标题遮挡修复、设备改名已获用户确认正常 |
| N1 正常重启 | 用户反馈“重启后 ok”，作为本次正常重启恢复验收 |
| GitHub 自动化 | LuCI/CGI/BusyBox、包安全、控制器、Bridge 与 Android 6 Agent 工作流均成功 |

## 使用方式

1. N1 已安装并稳定使用 r16，无需重复安装主包。
2. iPhone 在 Safari 打开 `https://tv.rqqr.de/`，通过“添加到主屏幕”制作唯一入口（是否完成此个人设置尚待用户自行决定）。
3. 家里和外面均使用同一公网域名，可避免快捷指令和分流 DNS；如有需要，可保留局域网 HTTP 作为备用。
4. 已配对授权默认长期有效，清除浏览器 Cookie/无痕模式仍可能导致重配；LuCI 可单台撤销或撤销全部。
5. 当前不启用 Cloudflare Access。外网配对页面可被公众打开，**控制操作必须通过 TVGuard 配对授权**；禁止公开 LuCI/RPCD/SSH/Docker Socket。

## 限制与维护

- 暂停/App 首页的保守判断阶段可能有短暂多计时，不因个别采样随意降低识别门槛。
- 不声称已验证未来 OTA、极端断电、跨设备浏览器清理、长时间离线后的所有恢复路径。
- 后续以修复故障、适配 OpenWrt/Android 环境与必要的安全更新为主，不再持续叠加实验性功能。
- 历史版本、旧 Release 及必要的 Actions 审计记录保留，不批量删除。
