# TVGuard Agent 0.1.0 · 小米 Android 6 验证版

目标电视：MiTV4-ANSM0 / xmen / Android 6.0.1 / API 23。

此目录是独立实验 Agent，**不会改变现有 N1 TVGuard 的计时和防火墙实现**。首次验证只回答：未 Root 的普通 APK 获得 UsageStats AppOps 授权后，能否记录前台包名和 Activity；关闭 ADB、重启电视后是否恢复。

## 资源与隐私硬约束

- 不声明 INTERNET 权限，不上传任何数据；v0.1.0 不连接 N1。
- 不创建本地日志、SQLite、缓存文件、离线补传队列、崩溃上传组件。
- 仅保存一个 enabled 布尔配置，用户主动切换时才写入一次 SharedPreferences。
- 事件仅在内存中遍历，初次最多查询 60 分钟；随后每 5 秒短窗口采样，单轮最多处理 4096 条事件；无历史事件列表。
- 关闭或重启后运行时状态清空。操作系统可能自行生成缓存、安装元数据或系统诊断，不能承诺系统级绝对零写入。
- 服务由 BOOT_COMPLETED 尝试恢复；小米固件后台保活和权限跨重启保留仍需真机验收。

## 安装 / 验证

到 GitHub Actions 的 TVGuard Agent Android 6 build 工作流下载 Debug APK。首次在电视开启 ADB 并连接（当前电视 IP 以实际为准），Windows 平台执行：

    adb install -r tvguard-agent-app-debug.apk
    adb shell appops set com.tvguard.agent GET_USAGE_STATS allow
    adb shell appops get com.tvguard.agent GET_USAGE_STATS

电视桌面打开「TVGuard 助手」，选择「开始监测」。再切换到银河奇异果、云视听极光或 SmartTube，然后返回助手，观察“最近其他 App”和 Activity。因为返回助手后助手自身就是当前前台，所以应以最近其他 App 栏检查刚才使用的视频 App。

接着关闭电视 ADB 调试，重复 App 切换验证；再重启电视（ADB 会自动关闭），打开助手检查权限和采样时间是否仍正常，必要时观察是否先前后台服务已恢复。

如果电视拒绝 AppOps 授权或事件为空，**不要宣称已通过**；记录实际命令输出和助手界面。不要尝试 Root、修改系统分区或为权限写入持久化脚本。

## Windows 卸载 / 回退

    adb shell am force-stop com.tvguard.agent
    adb uninstall com.tvguard.agent

不涉及 N1 配置、TVGuard 计时、代理防火墙或路由网络；卸载只移除这个测试 APK 的数据。

## 局限与下一阶段

- Activity 类名仅反映当前 UI 页面；PlayerActivity 不能证明视频正在播放，也不能直接决定是否计时。
- Android 6 厂商 UsageStats 事件可能不完整；接入 N1 Shadow Soak 之前必须评估漏报、断流、待机和后台回收。
- 正式版未来在明确本地认证与最小事件协议后，再加入只向 N1 上报最新状态的网络能力；不补传、不写电视盘、不改现有计时路径。
- 本 APK 为测试构建，GitHub Actions 不同运行生成的 Debug 签名可能不同；更新失败时需要先卸载旧测试版再安装，生产签名另行设计。
