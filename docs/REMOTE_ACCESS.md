# TVGuard · 远程访问（Cloudflare Tunnel）

当前稳定版本：**v0.1.16-r16**。LuCI 远程访问页的 UI 已于 2026-11-18 获用户真机确认正常。N1 上原有专用 Tunnel 已由用户完成真实配置，iPhone 蜂窝网络通过 `https://tv.rqqr.de` 访问与控制正常。r15 仅改 LuCI 远程访问页面的视觉和交互。

## 页面结构

- **运行摘要**：专用 Docker 容器状态、Token 是否已保存、Metrics 是否仅本机监听。
- **外网家长遥控**：清晰展示 `https://tv.rqqr.de`，提供打开与复制；不把容器“运行中”误判为 Cloudflare 已 Healthy。
- **Tunnel 服务**：仅能启动、重启或停止 tvguard-cloudflared；停止前提示外网会中断，家中 HTTP 不会因此停止。
- **维护与诊断（高级）**：Token 修改和有限日志默认折叠，不干扰日常家长使用。Token 不回显，修改时需确认；读取日志仅限专用容器最近 60 行、最多 16 KiB。

桌面使用状态摘要和双栏卡片，移动端改为单栏并重排长地址与操作按钮。与家长遥控页面共用受作用域限制的 `panel.css`，不影响其它 LuCI 页面。

## 现有真实配置

| 项目 | 内容 |
| --- | --- |
| 公网地址 | `https://tv.rqqr.de` |
| Tunnel 容器 | `tvguard-cloudflared` |
| Published application route | `tv.rqqr.de` → `http://localhost:18765` |
| Docker 网络 | `host` |
| Metrics | `127.0.0.1:20241`，仅本机回环 |
| 家长遥控服务 | 本机 `127.0.0.1:18765`，家中另开放 br-lan 私有 IPv4 |
| Cloudflare Access | **当前未启用**（用户选择的简洁方案） |

**安全边界**：公网域名可公开加载页面，但所有模式/奖励操作依然由 TVGuard 自身设备配对授权保护。未经配对的会话不可直接控制。不得在 Tunnel 中发布 LuCI、RPCD、SSH 或 Docker socket；不得转发其它容器或调整 N1 防火墙。长期令牌泄露后可能长期有效，建议只给可信设备配对并及时撤销丢失设备。将来若需要增强安全性，可以选择额外配置 Cloudflare Access；不是当前配置的必需组件。

## 原有控制功能与安装限制

- 只有本模块创建且带有 `org.tvguard.owner=luci-app-tvguard` 标签的同名容器可被管理，不接管 Vaultwarden 或 ntfy。
- Token 以 N1 XFS 限权文件保存；不放入 UCI、Docker 环境变量或命令参数。前端通过权限受控的 `/tmp/tvguard-tunnel/token.pending` 提交新 Token，不回显。
- 新建容器默认 `--metrics 127.0.0.1:20241`。一次性“安全重建”按钮已在 r6 删除；正常升级无须重建容器。
- Docker 镜像必须已存在，本模块不会自动下载；原有 tvguard-agent-bridge、电视计费、NoMount、ZeroTier、其它 Tunnel 都不因 LuCI 的 UI 改版而改变。

## 版本与验收

- r14：家中和蜂窝网络真实配对、遥控与连接来源显示均已通过。
- r15：LuCI 远程访问 / 家长遥控视觉层、动作状态、日志折叠及设备列表移动排版已在源码与自动化层进行回归；**用户已完成桌面/手机视觉验收**。
- iPhone 使用 Safari 把统一 HTTPS 域名添加到主屏幕即可作为单一入口；用户已确认 N1 重启后运行正常，未来 OTA/长期运行另行观察。

## r16 · 标题遮挡修复

真机截图中「远程访问」主标题被 LuCI 主题绘制为蓝色横栏。r16 取消页面顶端会触发主题全局规则的 `header` 和 `h2` HTML 标签，替换为独立标题容器，并保留无障碍标题语义；不影响 Cloudflare 域名、配对、Token 或容器状态。
