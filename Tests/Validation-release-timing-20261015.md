# Release 性能复测包 · 2026-10-15

## 本次变更

- 本地真机包为 1.1.1（Build 34），明确使用 Release、Swift `-O` 和 whole-module optimization。工程发布配置仍为 Build 31，构建号通过命令行覆盖。
- 保留 Build 33 的精简首页和中英文切换。未修改图像采样、对齐阈值、拼接结果、输出分辨率或 JPEG 质量。
- 增加本机 `Documents/LongShotProcessingEvents.json`：最多 240 条阶段事件，记录录制结束、队列清空、系统流停止、拼接、照片授权、照片写入、结果通知、前后台切换及后台执行时间到期。
- 事件包含毫秒时间、进程运行标识、App 版本与优化标识；不包含画面、图片路径或用户文本。写入失败不影响正常录制保存。
- `LongShotCompletionTiming.json` 增加停止到保存的总时间、处理总时间、拼接任务调度／返回等待、照片授权／写入／回调恢复及结果持久化耗时。即使系统停止或进程重启后丢失内存中的 finishRequest，也可以用录制完成时间计算停止到保存的墙钟时间。
- 后台任务以独立对象保留 identifier，在完成或到期时只结束一次；到期记录用于判断后台中断，不把到期本身伪装成保存成功。

## 验证

- Xcode 27 RC 的签名 Release 真机构建成功；实际编译命令含 `-O`、`-whole-module-optimization`，无 `-Onone`。
- 主 App 和 Widgets 严格签名验证通过，中英文控件元数据与系统权限用途资源检查通过。构建唯一警告为已签名扩展不执行 stripping。
- 现有优化编译回归通过：生产 JPEG／队列检查、拼接边界、反向／往返、显式分页、启动遮挡恢复以及实时活动语言兼容性。模拟器不具备的 SCK 元数据／系统流不计入验证。
- 已在连接的 iPhone 上原位安装、启动，回读版本为 1.1.1（34）。设备导出的新事件包含 `appLaunched`、`appWillEnterForeground`，且 `optimizedBuild=true`、`appBuild=34`。
- 无卸载或用户数据清理。设备工具不允许读取 App Group 根目录的 latest-status.json；未绕过限制，安装前通过 App Documents 的录制事件确认最后一轮已经停止。
- 本轮未代替用户进行实际跨 App、多页录制，尚无 Build 34 结束到保存的真机耗时结论。等待用户以相同多页流程复测，再读取阶段日志定位此前约三分钟等待中的额外延迟。

## 交付边界

仅本地测试安装；未推送 GitHub，未上传或替换 App Store 提交。

本机构建、签名、回归和设备回读证据在 Git 忽略目录 `tmp/longshot-release-build34-20261015/`。上一轮诊断元数据保留在 `tmp/longshot-multipage-diagnosis-20261015/`。
