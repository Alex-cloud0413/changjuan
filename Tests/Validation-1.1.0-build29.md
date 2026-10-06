# 长卷 1.1.0（Build 29）发布验证

日期：2026-10-06。

## 范围与授权

- 用户要求推送本次控制中心图标修改，并替换 App Store 审核提交。
- 仅使用独立私有仓库 `Alex-cloud0413/changjuan`，不推送 `life-os-workspace`。
- 主 App 与 Widgets 的 Debug / Release 构建号统一为 29，版本号保持 1.1.0。
- 保留原三笔中心线，放大、加粗控制中心符号；不改变桌面 App 图标或截图行为。
- 继续手动发布，不替用户提前公开发布新版本。

## 已验证

- Xcode 27 RC（27A266a）正式 Release 归档成功。
- Apple Distribution 签名的主 App、Widgets 均为 1.1.0（29）；两者
  `get-task-allow=false`，正式 IPA 深度、严格签名检查通过。
- 正式 IPA 的 Widgets `Assets.car` 包含 `LongJuanCaptureV3` Vector Glyph，
  资源可插值，并包含 Small、Medium、Large 的符号形态。
- 图标修改时已验证 9 种字重/尺度配置可见、无裁切；现有采集拼接回归
  检查通过。真机已原位安装 Build 29 并回读正确，普通启动成功。
- `xcodebuild` 上传成功，Apple 已开始处理上传包。
- 导出 IPA SHA-256：
  `58e0eaa11367b1444b1774c028a732d3485a7d363ff89bafd6bef5f29803e22e`。

## 当前提交状态

Build 29 已上传，等待 Apple 处理并替换原 Build 28 审核提交。原 1.1.0
Build 28 提交在操作前为「正在等待审核」，提交 ID 为
`675dbb98-62e6-4f83-8406-61a577c56327`。公开分发的 1.0 不受影响。

## 本机证据

相对工作区根目录：

- `tmp/longshot-release-build29-20261006/`：正式归档、IPA、签名摘要、上传日志。
- `tmp/longshot-control-icon-20261006/`：原生资源渲染、像素测量、回归日志、
  真机安装及版本回读 JSON。

安装包、签名材料、真机输出及临时目录均不纳入源码仓库。
