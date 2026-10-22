# iPhone Duo 适配候选验证

日期：2026-10-23（Asia/Shanghai）。状态：本节记录首轮本地候选；后续发布授权与补测见 [Build 47 记录](Validation-1.1.4-build47-release.md)。

## 来源与执行环境

- 交接：Life OS 交接目录 `docs/longshot-handoff-2026-10-23/`。
- 独立公开源码仓库：<https://github.com/Alex-cloud0413/changjuan>，基线 `83a83112494811c3e2ee7d03df5d2fb2e5f44fb6`，保留完整历史和固定回归基线 `fe9cf807959bf25dc84025b2b7745554d38335c6`。
- 工作目录：独立 `changjuan` checkout；本地分支 `codex/iphone-duo-adaptation`。应用源码未加入 Life OS 控制仓库。
- Xcode 27.1（27A9275）、iOS 27.1 SDK；最低系统保持 27.0。版本标识仍为原 1.1.3（46），不代表这一候选已进入原发布包。
- 用户明确授权后，通过 `xcodebuild -downloadPlatform iOS -buildVersion 27.1 -architectureVariant arm64` 下载并安装 iOS 27.1 runtime（24A94232）。
- 新建专用模拟器 `LongShot Duo QA`。未在用户真机安装、卸载或清理数据。

## 实现与体验边界

1. 原始 JPEG 提交后记录实际像素宽高和 SCK videoOrientation；变化形成新段。手动接页边界与几何边界合并且去重，不创建空页，保留旧 manifest 解码。
2. 同尺寸段维持原有拼接；尺寸或采集方向变化分别生成原尺寸图片，不拉伸或推断重排后的正文连续性。几何段可以是实际静态页；缺源、坏图、段内无声明尺寸变化和无法匹配的内容继续明确拒绝。全部分组渲染成功前不清理先前结果，失败保留原始帧。
3. 结果 manifest、通知与预览明确标识尺寸/方向变化的内容已分开保存；不把多张原尺寸结果冒充一张跨折叠连续长图。
4. 新录制不再从长卷自己的 safeArea / screen height 推测另一个 App 的状态栏。在缺少可信边界时保留完整画面；设置中明确说明。**自动移除侧边状态栏尚未实现，新录制的未知顶部状态栏也保留。** 旧录制继续使用自身已记录的 topCropRatio，不用新偏好重解释。
5. 首版采集要求目标 App 全屏。自身 scene 的 foregroundActive / foregroundInactive 都属于可见；长卷占显示的一部分且可见时明确报告并排采集不支持，保留原始录制。未删除自身前台过滤。进程级 cold background intent 路径保留原有可见性初始化，避免后台命令依赖已出现的窗口。
6. 首页保持纸白、图标主操作、三笔标志、中文左/英文右和设置齿轮。按当前可用窗口滚动兜底；27.1 使用活动 division / occlusion 的 frame 与 margins 选择可交互区域，27.0 不调用新 API。开放横持方向。
7. 实际 UIScrollView 在 layoutSubviews / safeAreaInsetsDidChange / adjustedContentInset 改变时布局，使用可用视口，保留相对缩放与归一化阅读中心；同一文件 URL 重新解码不重置预览。
8. 实时活动紧凑尾部改用图标；展开操作保留接页、继续与完成，按钮具有标题与符号。预览/设置 toolbar 使用语义 placement 和 Label，使系统可在竖栏与溢出菜单中呈现。

## 检查证据

- `Build/duo-preview.log`：实际生产 preview 源码提取后在 Duo 27.1 执行 native UIKit 测试，展开/收拢、缩放、阅读中心、同 bounds 非对称系统 inset 与同 URL 解码均通过。系统 inset 用可控注入覆盖，不能说成硬件相机启闭实测。
- `Build/duo-focused.log`：首轮采集/拼接/横向/预览/实时活动检查通过；它发生在后续独立审查修复前，以最终统一回归为准。
- 独立代码审查指出的 inactive 可见性和同 bounds safe-area 预览问题已修，并追加测试。
- `Build/duo-ui/`：专用模拟器的实际运行截图；完整姿态范围以末节最终回读为准。
- 两次早期统一回归因继续修复审查问题而主动停止，不作为通过记录。
- 最终统一回归：**28/28 passed**，`automatedStatus=passed`、`releaseReady=false`、`physicalDeviceStatus=not_run`。
- 报告：`Build/regression-FRK7Jl/report.json` / `report.md`；最终运行日志 `Build/duo-regression-final.log`。
- 被测源码 SHA-256：`d44d91ca91d693c5c3247d6c41b4e2768a1ebb34881fd9ee1226b38dd48272ea`。报告和本轮完成后的重新计算一致。
- 版本/最低系统：主 App、Widgets 均 1.1.3（46）/ iOS 27.0；真机目标与模拟器目标均通过标准未签名 Release 构建；普通包未带 snapshot/benchmark/export-frames 调试入口。
- 固定 Build 35 基线与当前候选的纵向 90 帧/3 页输出逐字节一致；性能预算通过。模拟器算法中位耗时 1.6329 → 1.8288 秒，样本 p95 2.3363 → 1.9977 秒；5 次测量不是总体尾延迟或完成至 Photos 指标。
- Native 采集 pipeline 12 组检查包含几何记录、暂停恢复、并排明确失败和初次 foregroundInactive；native preview 同 bounds 非对称 inset 检查通过。
- 独立截图审查通过外屏默认中文和最大辅助字号中文（两行英文品牌 caption 未遮挡关键操作）；内屏全黑检查图不计通过。后续官方交互结果在末节补充。

## 官方技能覆盖与未测项

从 Xcode 成功导出并使用 `app-resizability`；审查覆盖 UIScreen、布局方向、idiom、scene lifecycle、不对称 safe area。发布源码没有 UIScreen.main / 设备方向布局 / idiom / 废弃 layout guide 命中。仅背景使用 ignoresSafeArea，保留。SwiftUI 已使用 App / WindowGroup，AppDelegate 只有启动与通知，不另造 UIKit SceneDelegate。ReplayCaptureCoordinator 内旧裁切逻辑不在发布目标内，保留为历史源码，未启用 ReplayKit。

已有启动屏幕，无 UIRequiresFullScreen opt-out，仍只发布 iPhone。未添加 iPad 设备支持。27.1 API 有系统可用性保护。

真实 SCK 跨 App 采集、系统共享确认、控制中心、灵动岛、通知横幅、物理折叠时帧 metadata / 重排内容、大尺寸峰值内存、完成至 Photos 保存仍未真机验收。模拟器构建/截图/合成像素不能替代这些项目。不得标注“Duo 全面适配已验收”或发布就绪。

截至首轮候选验证结束，未推送 GitHub、未更新飞书、未查询或变更 App Store Connect。凭据、录制、SDK/runtime、模拟器数据、构建与截图均未提交。源码和忽略的本地验证产物保留，未执行旧项目或设备数据清理。

官方来源：
- <https://developer.apple.com/iphone-duo/prepare/>
- <https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo>
- <https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo>

## 最终模拟器交互回读

- 官方 Xcode MCP bridge 建立指定 QA 设备会话后，按 hierarchy hitPoint 完成英文切换、设置进入、右侧竖栏勾号 Done 返回；默认/最大辅助字号英文与中文外屏截图视觉审查未发现遮挡、裁切或不可读控件。
- 最终统一回归构建的 Release 包又原位安装到同一 QA 模拟器并启动；英文偏好保留，`12-final-outer-en-portrait.png` 是最终构建外屏画面。此前设置交互截图来自 UI 源码一致的本轮候选构建。
- 设备 orientation 改为 landscapeLeft/Right 后，hierarchy 仍显示 App UI orientation=Portrait，截图尺寸仍 466×678 pt。虽然最终包 Info.plist 已声明竖屏及左右横屏，**不能把此命令当成横持 UI 验收通过**。
- Device Hub 铰链 slider 的 AX 值变化没有让实际内屏亮起；内屏截图全黑。通过公开 simctl screenConfig 切换显示电源也未取得有效内屏结果。内屏、半折、完整 pose 转换与极窄/极矮实际窗口检查仍未完成；不使用 AX 数值、黑图或 native preview 的尺寸模拟来冒充它们。
- 官方 DeviceInteraction 会话已关闭；仅使用新建 QA 设备，没有触及用户真机或其它模拟器的数据。运行截图/层级/日志留在忽略目录 `Build/duo-ui/`，未进入 Git 提交。

- 验证结束后仅重启专用 QA 模拟器；字号回读为 `large`，最终包正常启动且外屏恢复。`20-final-outer-restored-settled.png` 为恢复后的实际画面；详细 UI 操作记录位于 `Build/duo-ui/validation-notes.md`。
