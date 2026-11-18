# TVGuard 家长遥控器 · 受限预览版

状态：v0.1.16-r8 开发候选；尚未经过 N1 真机验收。新增家长控制端完全独立，默认关闭。

## 第一阶段已开发

- LuCI「家长遥控」先启用服务（本机 127.0.0.1:18765），再手动开启家中 HTTP 直连；额外监听 br-lan 私有 IPv4:18765，不绑定 0.0.0.0。
- LuCI 生成 5 分钟有效的一次性随机配对码。会话服务端仅保存 SHA-256 摘要，30 天过期，最多支持 4 台设备；支持撤销所有已配对设备。
- 独立移动端 PWA 提供儿童、家长、锁定模式，15/30/60 分钟奖励与撤销、今日累计及断网状态。
- CGI API 仅允许 GET status 和 POST mode/bonus，检查同源 Origin、自定义请求头与服务端 Cookie；不能执行任意命令或管理路由器。
- 只有 XFS 持久分区挂载时才能配对。持久化文件为 root 限权，配对码存在内存中。
- 不修改已有 TVGuard 计时、Agent、RAW 防火墙和代理控制逻辑。

## 重要限制

- 开启局域网 HTTP 后，iPhone 可直接访问 http://N1私有IP:18765/，仍需一次性配对。HTTP 链路无加密，已配对 Cookie 可能被同网段攻击者截获，只建议在可信家庭网络使用，不做公网端口转发。
- 不要在 Cloudflare Tunnel 配置任何指向 LuCI、RPCD、SSH 的公网路由。
- 外出通过 Cloudflare Tunnel + Access 使用公网 HTTPS，Tunnel 只转发到 localhost:18765；局域网 HTTP 与公网 HTTPS 为不同 Origin，不能靠 Split DNS 把两种协议变成同一 URL。统一桌面入口未来使用 iPhone 快捷指令按连接环境跳转。
- 未来开放局域网前必须先启用受 iPhone 信任的 HTTPS，避免 HTTP 明文 Cookie 被网络窃取。公网也必须通过 Access 与独立配对两道验证。
- 不需要新 Docker 容器。服务只有手动在 LuCI 启用后才会开机自动启动；停用不会影响电视计时控制。
- 安装和升级不主动启用或清空授权，卸载主包会停止遥控服务，但默认保留持久授权记录供人工处理。

本阶段不能视为公网访问已投入使用，必须等 N1 验收与配套安全部署完成。

## r7 家中直连启用顺序

1. LuCI → 电视时间管理 → 家长遥控 → 启用本机遥控服务；确认之后再点击「启用家中 HTTP 直连」。
2. 界面自动显示 `http://N1私有IP:18765/`，家中 iPhone 连接 Wi-Fi 后直接点击打开。
3. LuCI 生成五分钟一次性配对码，在手机首次完成配对，测试状态查看、儿童/家长模式与时间奖励。
4. 如果 br-lan 无私有地址，或 LAN 设备被网络隔离，会拒绝启用或无法访问。不会自动绑定全网卡。
5. 公网前先设置 Cloudflare Access 仅授权家长身份，再为 TVGuard 专用 Tunnel 创建 Published Application Route，Service URL 使用 `http://127.0.0.1:18765`；禁止暴露 LuCI、RPCD、SSH。

HTTP 明文可能泄露 Cookie，即便启用 HttpOnly、SameSite 也不等于加密，请隔离访客 Wi-Fi，勿做公网端口映射。

## r8 · 生成配对码兼容性修复

r7 的随机码生成使用 `od`，但 N1 精简固件不含该命令，导致配对失败。r8 在一次性配对码和 30 天会话令牌两处统一使用独立的 `/usr/libexec/tvguard-random-hex`，从 `/dev/urandom` 读取 16/32 字节并校验实际读取长度，使用 sha256sum 输出 32/64 位十六进制编码。CI 模拟缺少 `od`、`hexdump`、`xxd` 的运行环境。无需安装 coreutils，且不会在电视端写日志。
