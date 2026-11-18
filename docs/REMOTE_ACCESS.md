# TVGuard Cloudflare Tunnel 管理 · v0.1.16-r6 候选

当前包含独立的 Tunnel Docker 容器管理与受限家长遥控 PWA/CGI。**本地 API 尚未完成新版 N1+iPhone 验收，Cloudflare Access 与公网路由尚未配置**。不要向公网发布 LuCI、RPCD 或其他路由管理服务。

## 首次配置

1. 在 Cloudflare Zero Trust → Networking → Tunnels 创建独立 remotely-managed Tunnel，建议取名 tvguard-n1，并复制 Cloudflare 提供的 Tunnel Token。
2. N1 必须有正在运行的 Docker、已下载的 cloudflare/cloudflared:latest 镜像和可写挂载的 /mnt/mmcblk2p4 XFS 分区。镜像中的 cloudflared 必须至少为 2025.4.0。
3. LuCI → TV Guard → 远程访问 → 粘贴 Token → 保存 / 更换 Token。浏览器先通过固定路径把 Token 传到 /tmp/tvguard-tunnel/token.pending（RAM），后端将 Token 原子保存在 /mnt/mmcblk2p4/tvguard-cloudflared/token。
4. 点击 创建并启动 / 启动，刷新状态、查看日志，并在 Cloudflare 后台核实连接状态。**容器运行中不代表 Tunnel 已经连通。**
5. 日后可以在同一页启动、停止、重启和查看专用日志。升级 TVGuard 不自动删除或重建容器。

## 安全与隔离

- 只操作名称为 tvguard-cloudflared、标签 org.tvguard.owner=luci-app-tvguard 的容器；同名外部容器将拒绝接管。vaultwarden-cloudflared 和 ntfy_cloudflared 均不在目标范围。
- 不自动下载镜像。挂载检测要求 /mnt/mmcblk2p4 为 XFS、读写可用，否则拒绝写入持久凭据或启动容器。
- Token 位于 root 700 目录下的 600 权限文件中，启动时以只读目录挂载并通过 --token-file 读取；不放入 /etc/config/tvguard、容器环境变量、Docker 命令参数或日志。
- 文件仅限制非特权用户：N1 的 root、Docker 管理员和有权限的备份工具仍可能读取，所以必须保护 N1 管理权限。只有已登录 LuCI 的 TVGuard 写入权限可修改容器和 Token。
- LuCI 只读 RPC 仅允许 status 和 logs，写入 RPC 仅允许 prepare、save-token、start、stop、restart；不开放通用 Docker 命令执行入口。
- 容器使用 host 网络但不会自动开放端口映射；capabilities 全部清空、no-new-privileges、只读令牌绑定。为了读取 root-only Token，容器内仍以 UID 0 启动，不能将其称为完全无特权隔离。
- Docker 日志每文件不超过 2 MiB，最多 3 个；页面读取最后 60 行与最多 16 KiB。日志中疑似包含凭据的行会被过滤。
- TVGuard 原有计时、Agent、RAW 防火墙与代理规则不因这项功能改变。Tunnel 断开也不会让本地电视控制失效。
- Docker 重启策略为 unless-stopped。**应保证 XFS 分区在 Docker 守护进程启动前挂载**，否则 Docker 开机尝试恢复容器时仍可能遇到路径问题；本功能的操作按钮会自行检查 XFS 挂载。

## r1 保存 Token 权限故障修复

r1 的临时文件路径使用 /var/run 软链接，但 rpcd 可能在 ACL 检查时进一步验证 /tmp/run 的真实路径，导致写入被拒绝。r2 统一改用 /tmp/tvguard-tunnel/token.pending，避免路径重定向，同时页面区分三个步骤的失败信息。升级后建议重新登录 LuCI，使 ACL 重新载入。**请勿把 Tunnel Token 发到聊天或日志。**

## Metrics 默认限制与迁移记录

所有新创建的 TVGuard 专用容器默认带有 `--metrics 127.0.0.1:20241`，监控接口仅绑定本机回环地址。已有容器的启动参数由 Docker 保存，启动和重启不会修改；请通过 LuCI「远程访问」的 Metrics 状态核对，或以 Docker inspect 读取现有配置。

v0.1.16-r3 至 r5 曾提供一次性的「安全重建（限制 Metrics）」迁移按钮，N1 真机已完成迁移并确认 Cloudflare Tunnel Healthy。v0.1.16-r6 起从 LuCI 与 RPC 白名单移除这一高权限重建入口，同时保留监控地址校验和新建容器的强制回环参数。确需迁移历史未修复容器或升级镜像的场景，应另行设计经审计的维护流程，不要通过普通的「重启」按钮期望修改现有容器参数。

## 公网开放前尚需完成

家长控制页面、配对和受限 CGI 已在开发分支实现，新增端到端模拟测试；仍需 N1+iPhone 真实验收。之后才可建立 Cloudflare Access 家长身份应用、开启连接器 JWT 验签、验证蜂窝网络。Tunnel 只可代理本机独立的 127.0.0.1:18765，不得代理 LuCI、rpcd、SSH。家庭 HTTP 与外网 HTTPS 是不同 Origin，无法仅靠 DNS 分流实现一个 URL 自动兼容两种协议。

## 家长遥控预览

v0.1.16-r5 引入默认禁用且仅监听 127.0.0.1:18765 的独立家长控制服务，LuCI 可生成一次性配对码和撤销会话。当前可按需开启家庭 HTTP，但尚未配置 Cloudflare Access，请勿对外发布未经验收的入口。详情参见 PARENT_REMOTE.md。

## r7 家庭 HTTP 访问

局域网改为 LuCI 显式启用 HTTP，绑定 br-lan 的私有 IPv4:18765，同时保留 127.0.0.1:18765 供 Tunnel 回源。Cloudflare 公网仍必须使用 Access 和 HTTPS，不允许把 LuCI 公开。不同协议、域名对应不同浏览器 Origin；若要一个桌面入口，后续通过 iOS 快捷指令按当前网络选择 URL。


## Cloudflare Access 外网发布前执行清单（尚未执行）

必须先在 Cloudflare Zero Trust 中建立 Access 自托管应用，再设置 Tunnel 公网路由。以下操作不能由安装 IPK 自动完成；在 N1+iPhone 本地配对真实验收之前，不进行公网路由配置。

1. Access → Applications 创建 Self-hosted 应用，仅绑定 TVGuard 精确子域名，例如 tv.example.com（仅示例，不是实际域名）。不要使用根域通配符。
2. Allow 策略只允许家长邮箱或明确授权的身份组，不使用 Everyone / Bypass。需要时配置双因素认证。
3. 在 TVGuard 专用 Tunnel 的 Published Application Route 中，只配置精确主机名，源站 URL 固定为 http://127.0.0.1:18765，不指向 LuCI、RPCD、SSH 或 Docker Socket。
4. 在对应 Origin Request 中开启 Protect with Access 并输入 Access Application AUD，使 cloudflared 在代理请求前验证 Cf-Access-Jwt-Assertion。仅看到边缘登录页面不代表源站验证已启用。
5. 在 iPhone 蜂窝网络、退出登录的浏览器或无授权账户下检查：必须被 Access 要求登录或拒绝；通过 Access 但未设备配对时，状态 API 必须返回 401。完成配对后才允许模式切换及时间奖励。
6. Access 失效与设备会话失效属于两层控制。LuCI 执行撤销全部设备后，即使 Cloudflare Access 会话还有效，也必须重新配对。
7. 禁止 WAN 端口映射至 18765，禁用任何绕过 Access 的同名路由。测试 Tunnel 断网不影响本地家长 HTTP、原有电视计时、ZeroTier 与其他容器。
8. 家中 HTTP 和外网 HTTPS 对浏览器来说是不同 Origin，可能需要分别配对。Safari 与主屏 Web App 也可能隔离 Cookie；iPhone 单一图标使用快捷指令选地址，必须在设备上实际验证。

官方参考：
- https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/
- https://developers.cloudflare.com/tunnel/reference/origin-parameters/
- https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/application-token/
