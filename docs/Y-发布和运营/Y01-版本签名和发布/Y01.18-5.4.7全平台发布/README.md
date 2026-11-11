# Y01.18 5.4.7 全平台发布（Android、电视、Windows、Linux、macOS、iOS，构建号 5111）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：用户 2026-10-22：issue #7–#10 的处理顺序（修 #8、写明 #7 → 回复 → #9、#10 出设计图确认后实现 → 一起发 5.4.7），回答“可以，按这个顺序开始”
- 相关：Y01.17（5.4.6）；V02.10（电视对话框遥控器，issue #8；iOS 14 不支持，issue #7）、V02.11（底栏位置和紧凑底栏，issue #9）、V02.12（浏览列表的已关注标记，issue #10）；发布说明 [releases/v5.4.7.md](../../Y03-发布说明和README/releases/v5.4.7.md)

## 目标

- 新仓库 `wzgrx/PureLive` 打标签 `v5.4.7`，发布页上传十个包和 `SHA256SUMS.txt`：Android 三个 APK、Windows 两个、Linux 一个在本机构建；macOS 的 DMG、ZIP 和 iOS 的两个 IPA 由 `.github/workflows/apple.yml` 在同一提交上构建，`apple-publish.yml` 挂到发布页（D-041）。
- 发布说明的“下载哪个”从这一版起写每个包的最低系统（iOS、iPadOS 15，macOS 12，issue #7）。
- 最后改两个仓库 master 的 `assets/version.json`、`assets/releases.json`；issue #8–#12 在实际发布后回复版本号并关闭。

## 最后确认的范围

2026-10-22 用户在原 Claude 对话中最后确认“可以，按这个范围发”：本版包含 issue #8–#12、A01.8 玻璃质感和滑块；A01.9 随滚动收起底栏先做原型确认，进入后续版本。此前把 A01.9 写成发布前置条件的登记已更正。

代码从 `3fec57539` 接手，恢复 V02.14 未提交补丁后在独立工作区 `/home/wzgrx/projects/purelive-codex`、分支 `ai/V02.14` 继续。旧工作区和旧包保留；旧包不作为本版候选。

## 版本

| 方面 | 5.4.6（Y01.17） | 5.4.7（本任务） |
|---|---|---|
| 版本 | `5.4.6+5110` | `5.4.7+5111` |
| Android versionCode | 7110、6110、9110 | 7111、6111、9111 |
| 签名 | 维护者调试密钥；苹果没有苹果签名 | 同左 |

## 验证

- Android：包名、versionCode、证书、通知资源、16 KB 对齐、`libffmpegkit.so` 是 b2 的；同一提交的 v4dev 测试包在 K90 上冒烟（底栏位置、紧凑底栏、已关注红心、电视界面的对话框，以及 A01.8 浅深色效果、玻璃质感滑块和拖动帧时间）。
- Windows、Linux：启动后截图确认进了首页（PROCESS 第 11 节第 4 条）；复查滚轮、方向键、静音与滑块交替调音量，持续按住滑块超过 4 秒，确认没有画面中间的音量条、控制栏不会提前隐藏。
- macOS、iOS：构建机上启动 macOS 版、iPhone 模拟器里启动 iOS 版，截图确认进了首页。

## 发布结果（2026-10-22）

[5.4.7 正式发布](https://github.com/wzgrx/PureLive/releases/tag/v5.4.7)。PR #13 合并 `aefa7d7f7ce610b0bb938400984f3d1dc9ec2a84`，标签固定到实际构建提交 `dbd1f71fcdd4bfe00095f955241fd4b9cfa5c5d2`。十个安装包与 SHA256SUMS 的远端 SHA-256 全部核对一致；不是重新混合构建。

用户在本轮明确授权“允许，核对通过后合并并发布”，范围包括新旧仓库两个更新文件同步。验收空白保留在 verify 和发布说明中，A01.8、V02.14 不因此被标成完整真机验收完成。本轮未发 issue 回复。
