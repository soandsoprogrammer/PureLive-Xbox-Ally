# Y01.12 5.4.1 全平台发布（Android、电视、Windows、Linux、macOS、iOS，构建号 5105）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：用户 2026-10-17：“发布5.4.1，没有苹果设备，继续做macOS和iPad”
- 相关：Y01.11（5.4.0）；X02.2（Linux 启动修复）；X04.1、X05.1（苹果工程和云构建，D-041）；发布说明 [releases/v5.4.1.md](../../Y03-发布说明和README/releases/v5.4.1.md)

## 目标

- 新仓库 `wzgrx/PureLive` 打标签 `v5.4.1`，发布页上传十个包和 `SHA256SUMS.txt`：Android 三个 APK、Windows 两个、Linux 一个在本机构建；macOS 的 DMG、ZIP 和 iOS 的两个 IPA 由 `.github/workflows/apple.yml` 在同一提交上构建（D-041）。
- 最后改两个仓库 master 的 `assets/version.json`、`assets/releases.json`；`platforms.macos`、`platforms.ios` 第一次指向 5.x。

## 版本

| 方面 | 5.4.0（Y01.11） | 5.4.1（本任务） |
|---|---|---|
| 版本 | `5.4.0+5104` | `5.4.1+5105` |
| Android versionCode | 7104、6104、9104 | 7105、6105、9105 |
| macOS | 3.2.10 | 通用二进制 DMG、ZIP，ad-hoc 签名，macOS 12 起 |
| iOS、iPadOS | 3.2.10 | 未签名 IPA、TrollStore IPA，iOS 15 起 |
| 签名 | 维护者调试密钥 | Android 同一把（D-006）；苹果没有苹果签名 |

## 验证

- Android：包名、versionCode、证书、通知资源、16 KB 对齐；K90 冒烟。
- Windows、Linux：启动后截图确认进了首页（PROCESS 第 11 节第 4 条）。
- macOS、iOS：构建机上启动 macOS 版、iPhone 模拟器里启动 iOS 版，截图确认进了首页；没有苹果真机。
