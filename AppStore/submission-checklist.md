# 长卷 1.0.0 提交清单

当前候选为 1.0.0（Build 26），最低系统 iOS 27。核心长截图体验已在真机完成验证；本轮迁移到 Xcode 27 RC，并完成 App Store 提交材料收尾。最终「提交审核」仍需开发者本人确认。

## 已完成

- [x] 最低系统统一为 iOS 27.0，捕获路径使用 ScreenCaptureKit
- [x] 已从工程和安装包中移除不用的 ReplayKit Broadcast Upload / Setup UI 扩展
- [x] 主 App 与控制中心 / 灵动岛扩展可编译
- [x] 版本号 1.0.0，当前构建号 26
- [x] 两个可执行组件均包含隐私清单
- [x] Xcode 27 RC（27A266a）已安装并完成首次配置
- [x] Build 26 已完成 RC 编译、Archive 与 App Store Connect Export
- [x] 迁移后的当前源码已再次通过 Xcode 27 RC 通用 iOS 设备 Release 构建校验
- [x] 导出摘要确认主 App 与控制扩展均为 Apple Distribution、arm64、`get-task-allow = false`
- [x] 隐私清单声明不跟踪、不向开发者收集数据
- [x] 1024 × 1024 App 图标为 PNG 且不含透明通道
- [x] 已生成五张 1320 × 2868、无透明通道的 6.9 英寸 PNG/JPEG 截图
- [x] 已准备简体中文商店文案、审核说明、隐私政策与支持页草稿

## 真机放行条件

- [x] 系统面板显示「Share Entire Screen」；引导文案已兼容此选项
- [x] 完整验证：控制中心开始 → 当前 App 连续滚动 → 灵动岛完成 → 拼接 → 保存照片 → 通知预览
- [x] 验证从控制中心开始与完成，无明显 App 跳转
- [x] 验证完成通知在关闭睡眠专注模式后显示
- [ ] 复核 Build 26 首次安装引导
- [ ] 验证拒绝录屏、拒绝照片权限、取消系统面板三条异常路径

## App Store Connect 放行条件

- [x] 「长卷」App 记录已创建（Apple ID `6811377178`）
- [x] 开发者本人接受更新的 Apple Developer Program License Agreement（2026-09-06 用户报告「已点击同意」；上传前仍检查账户放行状态）
- [ ] 确认公开的开发者显示名称
- [x] 支持页和隐私政策页已完成，公开 URL 已确定
- [x] 可公开的支持邮箱已确认；仅供审核联系的姓名、电话、邮箱待填入 App Store Connect
- [x] 定价确认为永久免费，面向全部 175 个国家或地区公开提供；版权行确认为 `2026 Yiming Gao`
- [x] 年龄分级已保存为 4+；第三方内容权利已确认；Build 26 已声明不包含自定义加密
- [x] 已上传五张更新后的 6.9 英寸 App Store 截图，并按 01–05 顺序排列
- [x] App 隐私已发布为“不收集数据、不跟踪”
- [x] Build 26 已完成 Apple 处理并绑定到 iOS App 1.0
- [x] 已填写并保存仅供 App Review 使用的联系人名字、姓氏、电话号码和电子邮件
- [x] 已经开发者本人确认并于 2026-09-13 正式提交审核；App Store Connect 状态为「正在等待审核」

## 失效产物

Build 20–25 均为历史测试包，不得作为本轮 App Store 上传版本。只接受使用 Xcode 27 RC 新生成并通过验证的 Build 26。
