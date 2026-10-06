# 长卷 1.1.0（Build 28）发布验证

日期：2026-10-06。用户已确认本机版本可用并授权 GitHub 推送与 App Store 提交。

## 构建和安装

- Xcode 27 RC（27A266a）、iOS 27 SDK、Release；最低 iOS 27.0。
- 主 App 和 Widgets 的版本号均为 1.1.0，构建号均为 28。
- 正常包未开启 `LONGSHOT_BENCHMARK` 或 `LONGSHOT_CAPTURE_CHECKS`。
- 开发签名严格深度验证通过；用户连接设备原位安装、版本回读和普通启动通过。
- Archive 与 App Store Connect Export 成功；主 App 和扩展均为 Apple Distribution、arm64，`get-task-allow = false`。
- 导出 IPA 严格深度签名验证通过；Xcode 返回 Upload succeeded，Apple 处理后的构建为 `95112267-f7ab-4c49-a4e1-1ae1814c7d5f`。

## 回归

- 隔离模拟器中生产串行 JPEG/队列检查通过（6 项）。模拟器不支持实际 ScreenCaptureKit stream，本项不冒充系统授权或采集测试。
- 双向与往返输出与正向夹具逐字节一致；跨页顺序、静态第二页、无效页拒绝和起始遮挡恢复通过。
- 本次元数据修改不改变用户已验收的生产功能。既有真实录制复算和 Build 28 修复证据保留在 `Validation-1.0.0-build28.md`，不回写历史版本。

## App Store

- Apple ID：`6811377178`；商店版本：1.1.0；绑定 Build 28。
- 已保存双向滚动与跨页接续的中文描述、更新说明和英文审核步骤；继承既有已批准截图。
- 沿用免费定价、销售范围、隐私声明、版权和审核联系信息；未重置评分。
- 正式提交返回「已提交 1 个项目」，版本状态「正在等待审核」。提交 ID：`675dbb98-62e6-4f83-8406-61a577c56327`。
- 保留「手动发布此版本」。等待审核不等于已经发布；审核通过后仍需执行发布。

## GitHub 边界

- 独立私有仓库：`Alex-cloud0413/changjuan`。本目录作为独立 Git 工作区。
- 未向 `life-os-workspace` 推送长卷；其远程 `apps/LongShot` 目录不存在。上级工作区已忽略本目录，以避免后续重复同步。
- 只纳入源码、项目配置、必要图标与商店素材、文档和测试；排除安装包、签名密钥、录制帧、构建与临时输出。

本机证据保存在上级工作区 `tmp/longshot-release-1.1.0-20261006/` 和 `tmp/longshot-version-1.1.0-20261006/`，不进入源码仓库。

导出 IPA SHA-256：`caef857b596ea7d541131c1237176efbc7ba35fc470ff8ce9f71a6f87ebcde65`。
