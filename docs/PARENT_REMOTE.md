# TVGuard · 家长遥控

当前稳定版本：**v0.1.16-r25**。家长遥控的家庭 HTTP、Cloudflare Tunnel 外网功能已在 N1 + iPhone 验收；r16 的 LuCI 家长遥控/远程访问两页 UI（标题、移动适配及设备备注）也已在 2026-11-18 获用户确认正常。N1 重启后的功能也由用户确认正常。iPhone 主屏幕图标可使用同一个公网 HTTPS 地址，无须对 N1 增加分流功能。

## 页面布局

LuCI「电视时间管理 → 家长遥控」在电脑宽屏显示三个状态摘要与双栏服务卡片，手机窄屏自动堆叠。主要内容：

1. **状态摘要**：独立服务是否正常、家中 Wi-Fi HTTP 是否开放、已授权的设备数量。
2. **遥控服务**：启用 / 停止独立 uhttpd，影响家长遥控入口，不影响 TVGuard 计时、正式断网。
3. **家中 Wi-Fi 直连**：显式开启或关闭 br-lan 私有 IPv4 的 HTTP:18765；显示实际地址，浏览器支持时可复制。
4. **家长设备配对**：生成有效期 5 分钟、一次性使用的配对码，显示前端倒计时；不在页面载入时回显旧配对码。
5. **设备管理**：最多 4 台设备，浏览器类别与匿名标识、配对时间和授权期限；单台撤销、全部撤销。

技术说明默认折叠显示；停止服务、关闭内网入口、撤销权限等操作需要确认。若状态读取失败，控制按钮会禁用，不将旧状态误报为成功。

## 真正的访问地址

| 使用网络 | 地址 | 认证 |
| --- | --- | --- |
| 家庭 Wi-Fi | `http://192.168.101.99:18765/` | TVGuard 一次性配对 |
| 外出公网 | `https://tv.rqqr.de/` | TVGuard 一次性配对（当前未启用 Cloudflare Access） |
| N1 本机 CGI | `127.0.0.1:18765` | 受限 API，不对外作为 LuCI 入口 |

外网使用现有 TVGuard 专用 Cloudflare Tunnel 的 Published application route，回源 `http://localhost:18765`。Tunnel Docker 使用 host 网络，因此指向 N1 localhost；不得配置指向 LuCI、SSH、RPCD 或 Docker socket 的公开路由。

家里使用明文 HTTP，**无法防御同网段抓包与中间人攻击**；只在可信家庭 Wi-Fi 使用，不做 WAN 端口映射。外网虽然有 Cloudflare 提供的 HTTPS，但因未启用 Access，网页可被公众打开；实际控制权限由独立配对码与 Cookie 保护。若怀疑授权泄露，在 LuCI 撤销设备。

## 配对与长期授权

- 5 分钟随机码只可使用一次，手机提交后服务端保存授权令牌的 SHA-256 摘要，不以明文保存 Token。
- 设备服务端授权默认长期有效（期限字段为 0），除非 LuCI 单台/全部撤销；失效旧会话在升级时不会复活。
- 浏览器 Cookie 最多一年，使用时滚动续期。浏览器清理 Cookie、无痕模式关闭、系统清理网站数据、浏览器自设限制时仍可能需要重新配对。**不承诺绝对永久登录**。
- 本地 HTTP 与外网 HTTPS 是不同的 Origin，可能需要分别配对。Safari 和 iPhone 主屏 Web App 的 Cookie 存储也可能不同。

## 版本边界及下一步

r15 专注 LuCI 两页结构、CSS、状态反馈和按钮展示，不改控制器、独立 API 的配对规则、Agent 或 Docker 配置。后续 r16 修复 LuCI 主题标题遮挡并支持设备备注；桌面与手机界面已经真机确认正常。

iPhone 推荐统一将 https://tv.rqqr.de 设为 Safari 主屏幕 Web App，家中和外网走同一个域名和配对授权；个人图标创建不属于 N1 的必需升级。

## r16 · 自定义设备备注与 LuCI 标题兼容

每条「已授权的家长设备」新增「修改名称 → 保存名称」，可使用中文、空格等常用文字，例如「爸爸的 iPhone」「妙妙的平板」。备注显示为主名称，原始浏览器类型和设备短标识仍保留，方便区分多个浏览器会话。

备注最多 24 个界面字符，服务器额外限制在 96 UTF-8 字节，拒绝换行、引号、反斜杠、竖线与控制字符。备注写入 N1 的 `/mnt/mmcblk2p4/tvguard-remote/device-names/`，按授权哈希独立持久保存，文件权限 0600、目录权限 0700。修改不影响配对 Cookie 或会话，撤销设备时清除其备注，全部撤销时清除整个目录。公网家长遥控网页不能修改备注，只有 LuCI 管理员可操作。

原 r15 两页标题被主题蓝条遮挡，原因是 LuCI 主题对 `header`、`h2` 的全局规则与页面标签冲突。r16 使用独立 div 容器及 `role=heading`/`aria-level`，保持桌面和手机布局；已由用户在实际浏览器中确认视觉修复正常。

## r25 · N1 冷启动 br-lan 地址竞态修复（待真机重启复验）

用户确认 r24 运行正常，但某次 N1 重启后家长遥控不可用，手动停用并启用即恢复。审查发现 `/etc/init.d/tvguard-remote` 启动时立即调用 `tvguard-remote-lan-ip`，一旦 br-lan 私有 IPv4 未出现，原逻辑 `return 1` 而且没有完成 `procd_close_instance`。这是能够导致所述现象的**确定代码缺陷**，但无法单靠源码证明历史现场一定由它引起。

修复原则：
- 启动时只在家长遥控与 LAN 均显式开启时短暂等待（最多约十秒）网络地址；
- 即便 LAN IP 仍暂不可用，也先注册只监听 `127.0.0.1:18765` 的 uhttpd，以保护 Cloudflare Tunnel 的本机回源；不扩大为 `0.0.0.0`；
- 在 LuCI 控制的独立 procd 服务上注册逻辑 `lan` 的 `interface.up` 和 `interface.update` 恢复触发，网络真正就绪后重新运行本服务、自动绑定私有 br-lan IPv4；不做全局网络重启；
- 实时状态新增 `lan_listener`（只读布尔值），通过从 N1 访问私有 LAN HTTP 200 校验监听；前端区分「已开放」「待恢复」，避免「配置已开启」冒充「网络实际可达」；
- 既有长效家长授权文件、配对 Cookie、时间控制与 Tunnel 不变化，家长遥控已停用时不会被触发器重新启用。

新 CI 使用真实 init Shell / mock procd 和延迟 LAN-IP helper 模拟冷启动 IP 缺失、有限重试、LAN 恢复、禁用模式与安全监听范围；真实 N1 开机以及网络事件是否按预期触发，仍需实机检查。

如再次出现问题，可以只读诊断：
```sh
/etc/init.d/tvguard-remote enabled; echo "enabled_rc=$?"
/etc/init.d/tvguard-remote status
/usr/libexec/tvguard-remote-admin status
ip -4 -o addr show dev br-lan
ss -ltnp | grep ':18765' || netstat -ltnp | grep ':18765'
logread | grep -Ei 'tvguard-remote|uhttpd|procd|br-lan' | tail -80
```
