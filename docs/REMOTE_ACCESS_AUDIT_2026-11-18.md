# TVGuard 家长遥控 / Cloudflare 全链路审计

审计日期：2026-11-18  
审计基线：开发 PR #13（尚未合并）。  
范围：LuCI → 家中 HTTP → uhttpd/CGI → 配对会话 → TVGuard 控制器 → Cloudflare Tunnel/Access → iPhone 主屏入口、系统重启与 OTA。

**目前只确认用户的 Tunnel 连接已 Healthy、metrics 重建已完成。r9 手机配对与其后新增修复仍未真实验收，不能因 CI 通过就声称可正式使用。**

## 已发现问题

| 优先级 | 具体问题 | 状态 |
| --- | --- | --- |
| P0 | N1 精简系统没有 od：配对和会话令牌生成失败 | 已修复，补无 od 的随机生成测试 |
| P0 | uhttpd CGI 不转发自定义 X-TVGuard-Action 头：iPhone 配对触发 origin_rejected | r9 使用严格 Origin / Referer / Host，待真实 iPhone 验证 |
| P0 | 过去只做静态测试：编译成功不代表配对/控制成功 | 补真实 CGI 模拟运行测试，覆盖完整认证和操作 |
| P0 | 配对锁目录被强杀后可能残留，导致新配对永久卡住 | 已改为同目录原子领取，失败可重发码；并发最多成功一次 |
| P1 | 四台设备已满时，先消耗有效配对码再报错 | 已调整上限检查顺序 |
| P1 | 远程 API 把全部 Agent/网络诊断状态交给手机，而不是最小必要数据 | 待在公网启用前收窄 |
| P1 | uhttpd/分区/Docker 在重启、OTA、网络变更后的自动恢复还没有实测闭环 | 待真机回归 |
| 风险 | 家庭 HTTP 传输明文，Wi-Fi 内监听者可能截获登录 Cookie | 用户选择 HTTP；需隔离访客网络，禁止公网端口映射，不能宣称加密安全 |
| 阻断 | 独立外网域名、Cloudflare Access 策略和 Tunnel 的 Protect with Access 尚未部署 | 未完成前不得创建公网应用路由 |
| 体验 | 本地 HTTP 与外网 HTTPS 不是同一 Origin，iOS 主屏 Web App 可能有独立 Cookie 容器 | 不承诺自动共用登录；统一图标需单独实测快捷指令 |

## 发布强制门禁（不可跳过）

### 1. N1 / OpenWrt

- shell、CLI 和 package 必须适配真实 BusyBox，不能偷偷引入 od、hexdump、xxd、bash 等未声明依赖。
- 本机 uhttpd 默认只监听 127.0.0.1:18765；家中 HTTP 由 LuCI 手动启用，只绑定 br-lan 私有 IPv4:18765。
- XFS 未挂载时严格拒绝存储授权；Docker、Cloudflared、ZeroTier 或 TVGuard 计时不能被此模块异常连带修改。
- 新 IPK 必须保留 UCI 控制配置、计时数据、Agent 密钥、Bark、Tunnel Token，并保持正式控制状态。升级不擅自开启独立家长遥控器。
- 升级、停机、重启、OTA 后，对比 mode、watch_seconds、enforce、armed、blocked、Agent 状态和隔离审计。

### 2. 配对 / 会话 / API

- 未认证只允许加载静态网页；GET 状态为 401，不能执行任何控制。
- 5 分钟一次性码，错误尝试不得消耗；并发仅成功一次；已满 4 台不消耗码。
- 30 天令牌服务端只存摘要，撤销和过期立即失效；不得出现在日志、URL 或明文持久数据。
- POST 严格验证标准 CGI Origin/Referer/Host，恶意 Origin、null、伪造 Referer 前缀和 DNS 重绑定拒绝。
- CGI 白名单只含 mode child/parent/locked 和 bonus 15/30/60/undo，不允许 enforce、UCI、rpcd、任意 shell、Docker 控制。
- 控制失败必须真实报告；不使用虚假的“成功”响应。公网数据最小化，只输出手机 UI 需要的状态。
- 本地 HTTP 的 Cookie/配对码有固有窃听风险，不能被 HttpOnly/SameSite 误称为已加密。

### 3. Cloudflare（P0 阻断）

1. **先建 Access Self-hosted Application**，精确匹配 TVGuard 子域名，Allow policy 仅准许家长身份，不用 Everyone/Bypass。
2. 再为同一 Tunnel 的 Published Application Route 开启 **Protect with Access**（cloudflared 验证对应 Access JWT/AUD）。只在边缘看到登录页仍不够。
3. 路由 Service URL 只指向 http://127.0.0.1:18765；绝不能指向 LuCI、RPCD、SSH、Docker socket 等管理服务。
4. 蜂窝网未授权账户必须被 Access 拒绝；已通过 Access 但未配对必须返回 401；完全授权后才能操作。
5. Cloudflare 故障不能影响 LAN 控制；Tunnel 容器仅操作 tvguard-cloudflared，metrics 固定 127.0.0.1:20241。
6. 公网不开放 18765 端口，也不调整 N1 对其他业务的代理和防火墙规则。

### 4. iPhone / 长稳体验

- 在家庭 Wi-Fi 真机完成首次配对、今日统计、三种模式、奖励/撤销。
- 在蜂窝网络完成 Access 登录、可能需要单独配对、授权失效重登和错误提示。
- Safari 与添加到主屏幕后的 App 可能隔离 Cookie；必须真实检查，不能用纯 JS 模拟来声称支持。
- 同一桌面图标拟采用快捷指令按网络选择 HTTP LAN 或 HTTPS 外网 URL；两种协议不能靠 Split DNS 无缝合并成同一 URL。
- 恢复网络、后台返回、Cloudflare 重连时只刷新状态，不重放有副作用的奖励/模式指令。
- 完成开机、OTA、XFS 挂载延迟、Docker 重启、Agent 保活与正式控制状态保持的联动回归。

## 门禁状态

- **已通过**：源码语法、IPK 构建、tvguardctl 调用格式复核、随机数无 od 测试、Origin 负面用例、CGI 模拟配对/会话/控制测试、配对并发/上限测试。
- **未通过真实设备验收**：r9 修改后的 iPhone 配对、局域网模式/奖励操作、系统重启与 OTA 后恢复。
- **尚未实现**：数据最小化、Access 身份与 JWT 强制验签、iOS 单一图标切换。
- **处理原则**：P0 全部关闭前保持 PR Draft，不合并 main，不发布正式 Release。不得删除失败的测试以凑绿色。

仓库 tools/tvguard-remote-preflight.sh 提供只读现场检查，但不能替代真实 iPhone 和 Cloudflare Access 测试。
