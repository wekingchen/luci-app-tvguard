# TVGuard 家长遥控器 · 受限预览版

状态：v0.1.16-r14 开发候选；r13 本地配对已通过真机验证，r14 新功能尚未真机验收。新增家长控制端完全独立，默认关闭。

## 第一阶段已开发

- LuCI「家长遥控」先启用服务（本机 127.0.0.1:18765），再手动开启家中 HTTP 直连；额外监听 br-lan 私有 IPv4:18765，不绑定 0.0.0.0。
- LuCI 生成 5 分钟有效的一次性随机配对码。服务端会话仅保存 SHA-256 摘要，授权默认长期有效直到单台/全部撤销，最多 4 台；配对设备列表显示匿名设备标识、浏览器类别及配对时间。浏览器会话 Cookie 一年滚动续期，不能保证无痕模式、清理 Cookie 或长期不使用时仍保留。
- 独立移动端 PWA 提供儿童、家长、锁定模式，15/30/60 分钟奖励与撤销、今日累计及断网状态。
- CGI API 仅允许配对、GET status 和受限 POST mode/bonus，验证标准 Origin/Referer 与服务端 Cookie；不依赖 uhttpd 不转发的自定义请求头，不允许执行任意系统命令或管理路由器。
- 只有 XFS 持久分区挂载时才能配对。持久化文件为 root 限权，配对码存在内存中。
- 不修改已有 TVGuard 计时、Agent、RAW 防火墙和代理控制逻辑。

## 重要限制

- 开启局域网 HTTP 后，iPhone 可直接访问 http://N1私有IP:18765/，仍需一次性配对。HTTP 链路无加密，已配对 Cookie 可能被同网段攻击者截获，只建议在可信家庭网络使用，不做公网端口转发。
- 不要在 Cloudflare Tunnel 配置任何指向 LuCI、RPCD、SSH 的公网路由。
- 外出通过 Cloudflare Tunnel + Access 使用公网 HTTPS，Tunnel 只转发到 localhost:18765；局域网 HTTP 与公网 HTTPS 为不同 Origin，不能靠 Split DNS 把两种协议变成同一 URL。统一桌面入口未来使用 iPhone 快捷指令按连接环境跳转。
- 家庭 LAN 依用户选择使用明文 HTTP，务必确保仅可信家庭网络可达。公网则必须通过 HTTPS、Cloudflare Access 与独立设备配对两道验证。
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

## r9 · uhttpd Origin 兼容修复

OpenWrt uhttpd 的 CGI 默认只转发特定 HTTP 头（Host/Origin/Referer/Cookie 等），不转发 X-TVGuard-Action。旧版本以缺失的自定义 CGI 变量作为必备条件，因此所有手机配对 POST 均会被误拒绝为 origin_rejected。r9 只依赖标准 CGI 头，优先严格比对 Origin 与 Host；仅在 Origin 缺失时允许同源 Referer 回退，同时改成只对同源请求发送 Referer，不泄露至外站。局域网 HTTP 额外要求 Host 等于实际监听 IP:18765，减少 DNS rebinding 风险。公网 HTTPS 回源时按严格比对过的 Origin/Referer 设置 Secure Cookie，不再依赖未转发的 X-Forwarded-Proto。跨站 Origin 即使 Referer 伪装成同源也必须拒绝；两者都不存在时仍拒绝，不允许匿名或任意 Origin。

## r11 独立状态与撤销保护

手机端只返回固定九个必要状态，不再透传 Agent/流量诊断字段。配对会话绑定服务端授权代际，LuCI 撤销全部设备后轮换代际，旧会话即使被并发进程写回也无法再登录。由于内部格式更新，从 r5-r9 开发预览版升级后需要重新配对一次。对于网络中断造成的 POST 操作结果不确定，手机会锁住控制按钮，直至成功刷新状态，以防重复奖励。本轮仍为开发候选，未经过 N1/iPhone 真机复验。

## r12 受限 Cookie 与 Access 会话恢复

家长授权 Cookie Path=/cgi-bin/tvg（浏览器 Cookie 不按 TCP 端口隔离），尽量避免请求同主机 LuCI 时发送。保留 HttpOnly、SameSite=Strict；外网 HTTPS 按严格 Origin/Referer 判定设置 Secure。Access 会话失效时，手机页面提供「重新打开页面」按钮，触发顶层导航以便完成 Cloudflare Access 登录。HTTP 家庭链路仍不是加密连接，不能防止同网段窃取 Cookie。


## r13：存储检查真机故障修复
N1 r12 上配对时报 storage_unavailable，但生成配对码及 XFS 检查正常。代码审计定位到 CGI 里的 awk index 传参缺少引号，导致存储检查表达式无法可靠执行；管理员端的对应表达式则不同。原测试通过替换 storage_ok 函数掩盖了这个缺陷。r13 将两端统一成 index("," $4 ",", ",rw,")，使只读挂载无法误判；新增真实 BusyBox awk、XFS 读写状态、generation 文件缺失/符号链接等反向测试，并将 CGI、管理员端测试改为运行真实存储函数。修正此前误写成单美元号的临时文件进程号，不改 TVGuard 核心或 Tunnel。

同时复核配对临时文件生命周期：使用 BusyBox mktemp 原子生成专用临时路径（授权代际、配对码、CGI claim），不再拼接固定后缀。CI 检查异常和并发路径；无需升级 N1 上的电视 Agent。


## r14 已配对设备管理与连接状态

- 手机端通过当前 URL 判断访问来源：RFC1918 局域网 IP 显示“内网直连 · 在线”；外部 HTTPS 域名显示“外网 HTTPS · 在线”。这只是浏览器可见连接类型，**不是对 cloudflared 或 Cloudflare Access 已启用的密码学证明**，上线仍必须做独立 Access 否定性测试。
- 配对 POST 如果已设置 Cookie 但响应体损坏，页面仅尝试一次不带副作用的 GET 状态确认；确认成功直接进入已配对页面，**不会重试一次性 POST**。
- LuCI 提供“已授权的家长设备”列表，显示浏览器分类、SHA-256 摘要前 16 个字符作为识别码、首次配对时间和长期状态；支持单独撤销或全部撤销。浏览器不一定提供准确设备型号，识别码也不代表真实硬件 ID。
- 会话文件新增 5 列（SHA-256 摘要、过期字段 0、授权代际、配对时间戳、固定枚举名称），默认服务端不再按 30 天自动失效；旧版仍有效的 3 列会话由升级钩子迁移，已过期记录不复活。
- Cookie 使用一年滚动有效期，手机每次读取状态可续期。浏览器可能主动删除 Cookie、对最长有效期设置上限或在无痕会话结束时删除数据，因此**无法保证绝对“永不需要重配对”**。公网 Cloudflare Access 的会话期限是独立的，即便设备仍配对也可能需要重新验证家长身份。
- 局域网 HTTP 明文会话仍存在被同网段攻击者截获风险，长期令牌不能用来取代网络隔离。请仅在可信家庭网络使用；若怀疑设备丢失或授权被窃取，立即在 LuCI 撤销该设备或全部设备。
