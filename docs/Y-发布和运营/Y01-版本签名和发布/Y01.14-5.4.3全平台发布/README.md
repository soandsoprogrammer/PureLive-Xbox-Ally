# Y01.14 5.4.3 全平台发布（Android、电视、Windows、Linux、macOS、iOS，构建号 5107）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：用户 2026-10-18：“发布5.4.3”
- 相关：Y01.13（5.4.2）；A18.1（iPhone 和 iPad 的分享扩展、后台和锁屏播放、⌘ 快捷键列表）、A18.2（标题栏保持方案 B）；发布说明 [releases/v5.4.3.md](../../Y03-发布说明和README/releases/v5.4.3.md)

## 目标

- 新仓库 `wzgrx/PureLive` 打标签 `v5.4.3`，发布页上传十个包和 `SHA256SUMS.txt`：Android 三个 APK、Windows 两个、Linux 一个在本机构建；macOS 的 DMG、ZIP 和 iOS 的两个 IPA 由 `.github/workflows/apple.yml` 在同一提交上构建，`apple-publish.yml` 挂到发布页（D-041）。
- 最后改两个仓库 master 的 `assets/version.json`、`assets/releases.json`。

## 版本

| 方面 | 5.4.2（Y01.13） | 5.4.3（本任务） |
|---|---|---|
| 版本 | `5.4.2+5106` | `5.4.3+5107` |
| Android versionCode | 7106、6106、9106 | 7107、6107、9107 |
| 签名 | 维护者调试密钥；苹果没有苹果签名 | 同左 |

## 验证

- Android：包名、versionCode、证书、通知资源、16 KB 对齐；同一提交的 v4dev 测试包在 K90 上冒烟。
- Windows、Linux：启动后截图确认进了首页（PROCESS 第 11 节第 4 条）。
- macOS、iOS：构建机上启动 macOS 版、iPhone 模拟器里启动 iOS 版，截图确认进了首页；iOS 包里有分享扩展。
