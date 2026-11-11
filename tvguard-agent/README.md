# TVGuard Agent · 小米 Android 6 验证版

目标电视：MiTV4-ANSM0 / xmen / Android 6.0.1 / API 23。

此目录是独立实验 Agent，**不会改变现有 N1 TVGuard 的计时和防火墙实现**。首次验证只回答：未 Root 的普通 APK 获得 UsageStats AppOps 授权后，能否记录前台包名和 Activity；关闭 ADB、重启电视后是否恢复。

## 资源与隐私硬约束

- 不声明 INTERNET 权限，不上传任何数据；v0.1.0 不连接 N1。
- 不创建本地日志、SQLite、缓存文件、离线补传队列、崩溃上传组件。
- 仅保存一个 enabled 布尔配置，用户主动切换时才写入一次 SharedPreferences。视频 App 最近页面和最近 24 条前台事件全部是 RAM 内存数据，不写入私有存储。
- 事件仅在内存中遍历，初次最多查询 60 分钟；随后每 5 秒短窗口采样，单轮最多处理 4096 条事件；有上限为 24 条的纯内存最近前台事件环；界面最多展示 6 条，重启时不写入本地历史。
- 关闭或重启后运行时状态清空。操作系统可能自行生成缓存、安装元数据或系统诊断，不能承诺系统级绝对零写入。
- 服务由 BOOT_COMPLETED 尝试恢复；小米固件后台保活和权限跨重启保留仍需真机验收。

## 安装 / 验证

到 GitHub Actions 的 TVGuard Agent Android 6 build 工作流下载固定 Release 签名 APK。首次安装旧 Debug 签名切换到永久 Release 签名时可能需要卸载一次；从永久签名版开始后续均使用 `adb install -r` 覆盖。首次在电视开启 ADB 并连接（当前电视 IP 以实际为准），Windows 平台执行：

    adb install -r app-release.apk
    adb shell appops set com.tvguard.agent GET_USAGE_STATS allow
    adb shell appops get com.tvguard.agent GET_USAGE_STATS

电视桌面打开「TVGuard 助手」，选择「开始监测」。再切换到银河奇异果、云视听极光或 SmartTube，然后返回助手，观察“最近视频 App”“最近非桌面 App”和“最近前台页面切换”。经过电视桌面不会覆盖最近视频 App；默认最近 60 分钟 Android UsageEvents 可用于恢复已被系统结束的 Agent 进程，但并不证明 Agent 在整个播放期间连续存活。

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

## 功能正确性与安全门禁（2026-11-10）

**测试过不等于设计完成。** API23 模拟器目前证明普通 Android 6 环境可用，小米固件以及 N1 联动仍未验证。Agent 0.1.0 不申请 INTERNET 权限，不连接 N1，不能完成最终计时目标。

### 分层验收与不可跨越的边界

| 层级 | 验收证据 | 不得推导出 |
| --- | --- | --- |
| Java | 视频 App 切换、同 App 首页→播放器、迟到后台事件、长时间采样中断、时间倒退回归 | 小米 UsageStats 不会漏报 |
| API23 虚拟机 | 安装、权限、前台切换、服务、重启、短时存储对比 | 小米电视可无限后台保活 |
| 小米电视 | 银河奇异果、腾讯视频、SmartTube 切换；ADB 关闭；待机唤醒；整机重启，采样仍新鲜 | Activity=Player 证明真正播放 |
| N1 Shadow Soak | 低码率 576p/720p 免费视频、1080p/4K、暂停、首页、待机与人工标注对齐 | 仅凭 App 名称可扣时 |
| 长期稳定 | 24 小时目录大小及其增量、内存、卡顿、异常告警 | 12 秒无增长代表绝对零系统写入 |

### 不许假阳性

- 前台包名只说明谁在屏幕上，播放器页面不等于视频在播放；Agent 不得独立操控计时、奖励、封禁。
- 事件溢出、读取错误、缺权限、时钟回拨、采样间断后，不得继续呈现失效的前台状态为有效证据。必须显示未知或待确认。
- 监测开关开启≠服务正在监测；采样时间新鲜≠播放已确认。
- Agent 不可用时 N1 原有独立算法继续工作，Agent 不得依赖特殊隐藏权限、无限自启、Root、VPN 或无关授权。
- 本地历史、日志文件、数据库和离线队列持续为零；一个 enabled 配置只在用户明确操作时落盘一次。

### P0 最终业务验收（尚未开始）

儿童观看无会员免费视频、576p/720p 等低码率播放应正常计时；暂停、首页、待机不能因为 PlayerActivity 或视频 App 名称就持续误计；4K/1080p 不应产生退化。需用人工标注起止时间与 N1 的 used_seconds 及 Shadow Soak 对齐，检验漏计、误计和未知窗口。没有实测闭环证据之前，不合入稳定分支、不接入正式计费决策。

## v0.1.1 · 小米真机后台恢复修复（2026-11-10）

真机出现「监测开关：已开启」「状态：未启动」「未确认正常采样」，说明持久开关不能代表后台服务健康。Home 返回再从桌面打开应用是正确操作，不能要求用户必须用任务切换器。

处理：
- 用户开启监测时，采用 Android 6 标准 **foreground service**（持续系统通知，透明可见、不隐藏）；不使用循环拉活、无障碍/VPN/Root。
- 如果服务被系统回收，用户再次打开助手时，按已开启的开关单次恢复 Service；不增加磁盘队列、日志、定时唤醒。
- 仍无法保证小米定制系统不会清理进程；视频 App 后台运行时的稳定性必须在设备实测，不能把 UI 恢复当作后台持续采样证明。
- 模拟器追加「force-stop 进程 → 再次打开助手 → 服务与采样恢复」以及系统通知存在性验证。
- 升级旧 Debug APK 可能遭遇签名不一致，因为不同 GitHub Actions runner 使用不同临时 Debug 密钥；可以先卸载旧测试版再安装新版，重新 AppOps 授权。唯一持久配置 enabled 会随卸载清除。

## v0.1.2 · 正确解决 Home 经过桌面导致“最近 App 永远是桌面”

真实小米电视没有可靠的最近任务切换入口；用户正常操作「视频 App → Home → 应用菜单 → TVGuard 助手」始终经过 com.mitv.tvhome。旧版只展示 lastOtherPackage，被桌面覆盖，因而无法证明视频 App 页面识别成功。

修复：增加 VideoActivityHistory 纯内存上限 24 条的前台页面环，仅展示最近 6 条；**最近视频 App** 单独匹配银河奇异果 com.gitvdemo.video、云视听极光 com.ktcp.video、SmartTube org.smarttube.stable 和芒果TV com.hunantv.license（另有少量常见包名）。**最近非桌面 App** 对未知第三方视频包仍有意义，不会被电视桌面覆盖。无新权限、没有文件日志、数据库和待传队列。

首次查询 Android 系统 UsageEvents 可回放最近 60 分钟前台事件，这些记录来自系统现有使用事件，并不是本 APK 在闪存中积累日志。进程被终止后能否查到过去的视频 Activity，仍取决于小米厂商对 UsageStats 的支持和事件保留。权限失效、读取错误、时间回拨/长间断等情况继续明确标注待确认，禁止宣称历史页面必然被捕获。

**模拟器回归覆盖视频→桌面→助手的纯 Java 逻辑，以及 Settings→Home→助手的真实 Android 6 UI 路径。** 之后必须在小米电视上复现银河奇异果首页→PlayerActivity→暂停→Home→助手流程，并核对界面。暂停是否发生无法只靠 Activity 判断，需 N1 进一步融合网络证据。

## v0.2.3 · Android 6 采样与心跳分离

用户真实电视播放期间后台上报约 69 秒未更新，且 `AudioManager.isMusicActive()` 返回 false，即使 N1 PPS 很高。

上报不再依赖 5 秒 UsageStats 轮询完整成功；专门的低优先级 HandlerThread 每约 10 秒读取 RAM 最新快照并向 N1 上报，系统/权限异常时发送 unknown（快照最长 20 秒有效），网络失败直接丢弃，无离线队列、SQLite、运行日志或多余权限。采样线程阻塞的情况可以继续报告“未知”；系统杀死整个进程仍需真机排查。

## v0.2.4 · 小米电视后台进程回收自恢复

真机 v0.2.3 在独立 uplink 线程下仍出现 `report_seq=6` 后数分钟无新报告，说明问题不再只是 UsageStats 采样阻塞，而是整个进程/Service 后台存活失败或等价级故障。

监测开启时新增 Android AlarmManager 30 秒低频 watchdog。使用 **ELAPSED_REALTIME 非唤醒闹钟**：电视待机时不会主动唤醒设备；电视正在观看、系统处于唤醒状态时，如果进程被普通后台回收，闹钟会重新启动前台 MonitorService。显式关闭监测会取消 watchdog。Android 的 force-stop 会按系统规则取消闹钟，因此 force-stop 后仍需用户重新打开 App。

无新增权限、无文件日志、数据库或离线队列；仅保留原本用户显式保存的 enabled / N1 配对设置。

## v0.2.5 · 冷开机双保险恢复

真机 v0.2.4 在“电视开机后从未手动打开助手”的场景下，N1 看到 `report_seq=30` 后约一小时完全无新报告；这说明运行中 Alarm watchdog 不是跨重启方案，因为 AlarmManager 闹钟会随整机重启丢失，必须由开机初始化重新建立。

v0.2.5 使用两条互相独立的恢复链：
- **快速路径：** 标准 `BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` receiver，立即启动 MonitorService、重挂 30 秒非唤醒 watchdog，并确认持久 Job 已安排。
- **兜底路径：** API 21+ 原生 JobScheduler，`setPersisted(true)` + 15 分钟低频周期任务。任务在用户明确开启监测时安排，显式关闭监测时取消；用于某些厂商固件不可靠投递第三方 BOOT_COMPLETED 的情况。它不是计时依据，也不会写视频日志、数据库或离线队列。
- UI 首屏显示“开机恢复：已安排/未安排”，便于无需 ADB 判断持久恢复任务是否存在。

如果厂商连 persisted JobScheduler 也压制，Agent 仍可能冷开机后离线；此时 N1 原 Adaptive Engine 继续独立工作并按网络证据计时，不把 Agent 缺席当成免计时条件。Android force-stop 仍按平台规则取消后台恢复，需要用户再次打开 App，这个边界保持不变。


## v0.2.6 / r2 · 小米后台杀进程后的快速系统恢复

真机日志已经把三条路径区分清楚：

- MiTV ROM 会主动 `kill background` 结束 `com.tvguard.agent`，并拒绝普通 Service 自动重启；
- 30 秒 Alarm 的 Broadcast 路径被拒绝；
- v0.2.6 的 `PendingIntent.getService()` 也在真机明确出现
  `ignore start service ... from alarm pending intent`，因此 AlarmManager 不能承担快速恢复；
- `RecoveryJobService` 能由 system_server 重新创建整个 Agent 进程，是真机唯一已验证可靠的恢复入口。

因此 r2 最终采用两层 JobScheduler：

- **快速恢复：** 7026 / 7027 两个 `setPersisted(false)` one-shot Job 交替续约，
  `setMinimumLatency(20s)` + `setOverrideDeadline(30s)`。每次 Job 运行时先安排另一个
  Job ID，再检查 `MonitorService`，避免当前 Job 用同 ID 覆盖自己。
- **跨重启兜底：** 7025 保持 15 分钟 `setPersisted(true)` periodic Job，只负责设备重启后
  BOOT_COMPLETED 被厂商压制时重新种下快速链。
- **AlarmManager watchdog 已彻底移除。**

存储约束仍保持：Android AOSP 的 JobStore 只有 `JobInfo.isPersisted()==true` 才触发
JobStore 写盘，因此 20–30 秒 fast Job 链不会成为每轮一次的持久磁盘写入；电视端仍不创建
运行日志、SQLite、缓存、流量历史或离线队列。15 分钟 persisted fallback 是唯一持久系统 Job。

固定 Release 签名继续使用 v0.2.6 已建立的永久证书；r2 提升 `versionCode=9`，可直接
`adb install -r` 覆盖永久签名的 v0.2.6。

上线判定仍以 MiTV4-ANSM0 真机为准：模拟器要求后台 `am kill` 后不打开 UI，45 秒内由
JobScheduler 恢复 `MonitorService`；真机还必须再次验证 stale 空窗是否稳定压缩到约
30–45 秒。通过前不进入 v0.2.7 的 paused 状态融合。
