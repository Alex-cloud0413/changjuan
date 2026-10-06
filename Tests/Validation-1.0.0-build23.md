# Build 23 — iOS 27 体验优先

日期：2026-09-07。用户已明确：控制中心开始不跳 App、快速完成和结果预览优先，上架可以暂停。Build 22 的 iOS 26 配置被取代，未安装真机。

## 已完成

- 默认开启 LONGSHOT_SCREEN_CAPTURE_KIT，最低 iOS 27.0，Xcode 27 beta 27A5252f。
- 主 App 与所有扩展构建号 23；主 App 与 Widget 的已构建 MinimumOSVersion 均核验为 27.0。
- 已构建主 App 链接 ScreenCaptureKit，Info.plist 含 screen-capture 后台模式。
- 主 App 和 Widget 的已生成 AppIntents metadata 均核验 Toggle/Finish 的 openAppWhenRun=false、supportedModes=background。
- 主 App 的 LiveActivityIntent 直接调用 AppModel，等待 picker 授权和 stream 启动；清除旧 ReplayKit 共享命令，不把请求排队后立即结束。
- picker generation、单次启动门闩、待启动 stream 保留、晚到回调过滤、取消后停止迟到 stream、pipeline 故障时真正停止 stream。
- 封住新帧后停止系统采集，后台运行保护衔接到拼接和相册保存；无固定结束等待、无固定首尾删帧。
- App 内独立的一次性缩略图，点开完整预览，关闭不删除照片；通知独立处理，不把通知问题计为保存失败。
- 正常打开 App 时检查通知权限；仅活跃且空闲、首次未决定时请求。后台开始与完成不弹通知权限框。用户拒绝不自动更改设置。
- 真机安装与启动成功，原有数据保留；尚未进行 Build 23 端到端真机录制。
- 安装后读取真实通知设置：authorizationStatus=2、alertsEnabled=true、configuredForBanner=true。当前无需再次申请通知权限；设置允许横幅不等于已验证本次横幅实际送达。

## 验证

- Xcode 27 iPhoneOS Release 完整构建成功。
- 真实 iPhoneOS 27 SDK 类型检查：SCK 协调器、pipeline、主 App Intent 与 Widget Intent 均通过。
- 5 项生产 JPEG/队列逻辑测试通过；在现有 iOS 26.5 模拟器运行时明确排除 SCK metadata 解读。1206×2622 的 16 个合成帧，JPEG/原子写入中位 0.1633 秒、最大 0.1659 秒，封口完成记录约 0.0005 秒。这是模拟器测量，不是真机结束到保存的耗时。
- 6 项预览持久化测试通过；模拟器验证缩略图可见且点开完整长图。预览 UI 验证使用 Build 22 合成图片，不代表 iOS 27 采集通过。
- 11 项通知权限测试通过，覆盖拒绝、后台不弹权限、捕获忙碌不弹权限、异步状态变化、并发 activation、错误诊断。

## 真机验收（均仍待验证）

- 从目标 App 的控制中心开始，长卷不进入前台，Apple 面板正常显示。
- Share Entire Screen 确认后真实收到目标画面，灵动岛有完成按钮。
- 灵动岛完成不跳 App，停止采集并保存；读取实测结束到保存耗时，不能只报告拼接子阶段耗时。
- 系统完成通知含缩略图且可点开；若横幅/通知关闭或 Focus 限制，必须如实告知，不能声称一定弹窗。
- 热启动、系统回收后的冷启动、取消再重试、连续两次捕获分别测试。

## 新诊断文件（仅本机元数据）

- Documents/LongShotCaptureLaunchEvents.json：最近 80 条启动、选择、开始、取消、失败、停止与 App 前后台状态。
- Documents/LongShotCompletionTiming.json：拼接子阶段及显式结束到保存的实际秒数。
- Documents/LongShotNotificationSettings.json：当前授权及横幅配置。
- Documents/LongShotResultNotificationDiagnostics.json：附件创建与通知提交结果；提交成功不等于横幅实际已展示。
- Documents/LongShotCaptureDiagnostics.json：最近五次会话的帧数与结果。

## 上架状态

暂停。没有上传或提交审核，不为尽快上架而恢复旧跳转流程。当前 beta 工具链产物仅用于体验验证；本次未执行 App Store Archive/Export。
