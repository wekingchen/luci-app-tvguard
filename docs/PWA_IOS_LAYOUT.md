# TVGuard · iPhone 主屏 Web App 视觉修复（r17）

## 故障记录

2026-11-18 用户实机截图显示：通过 Safari「添加到主屏幕」打开 `https://tv.rqqr.de` 后，卡片和控制区可用，**顶部 TVGuard 标题及连接状态却位于 iPhone 系统状态栏背后，无法正常看见**。这是页面布局缺陷，不能解释为截图经过模糊处理。

代码原因：既有 `viewport-fit=cover` + `apple-mobile-web-app-status-bar-style=black-translucent` 会允许页面绘制到状态栏区域，但 r16 的 `.shell` 只有固定 `20px` 顶部 padding。iOS 27 的 Web App 安全区域又可能返回不同的 inset 值，因此不能仅在普通 Safari 页面上检查。

## r17 修改

- 将独立主屏模式的顶部 padding 设置为 `max(88px, env(safe-area-inset-top) + 18px)`，给状态栏/灵动岛提供安全留白；普通 Safari 仍使用紧凑顶部间距。对旧版 `navigator.standalone` 提供 JS 类名回退。
- 页眉改用明确的 `.app-header`、`.brand`、`.brand-copy` 层级：可见标题、副标题、独立在线状态标签；调整 PWA 主题色与页面背景一致。
- 适当收紧信息卡片和操作区的垂直留白，维持至少 48px 操作热区、窄屏断点、深色模式、减少动画设置。
- 当前模式按钮保持「不可重复切换」，但仍以浅蓝选中态标示实际模式；锁定状态使用红色。保留家长模式、锁定和撤销奖励的危险确认。
- 仅在儿童或锁定模式展示实际进度；家长模式不限时，隐藏没有意义的额度进度条。正式控制状态以轻提示展示，**不自动改变 N1 上的 enforce 开关**。
- 修正文案：当前外网不启用 Cloudflare Access；不能错误写成必须先配置 Access。
- 前端 CSS/JS 引用升级为 r17 查询参数，避免旧版样式仍被缓存。没有加入 Service Worker、第三方依赖或新的网络请求。

## 不变的安全边界

控制 API、Cookie、设备配对、Agent/Bridge、看电视时长、正式断网策略、Cloudflare Tunnel/Token 与 LuCI 均不更改；未经确认的 POST 仍需刷新状态后再操作，不重复发放奖励。

## 验收

- CI：执行 `node tests/test-remote-pwa.js` 和 `node tests/test-remote-pwa-layout.js`，同时要求 OpenWrt IPK 打包、隔离和 Android 6 Agent 集成通过。
- iPhone 真实主屏：首先用 Safari/主屏已安装图标重新打开，确认顶部显示 TVGuard、家长遥控器、远程连接正常；再检查模式选中态、家长不限时进度隐藏、按钮大小与底部安全区。
- 家长模式与儿童模式在前端正确显示即可，不必为了 UI 验收实际切换 N1 模式。如需测试模式切换，必须确认当前控制策略。
- 如果独立 Web App 保留旧布局，先关闭后重新打开、检查 Safari 同域名的版本。只有在判明确实是旧图标安装时缓存的视口配置时才考虑移除并重新添加；重新添加后可能需要再次配对。

**2026-11-18 验收**：用户已提供 r17 iPhone 主屏独立模式截图，标题、副标题及控制卡片均完整可见。收尾将原过长的「Cloudflare Tunnel · 在线」精简为「远程连接正常」，避免状态标签断行为「在/线」；代码测试验证该文案和离线/待配对状态，最终安装效果仍以升级后的真机显示为准。
