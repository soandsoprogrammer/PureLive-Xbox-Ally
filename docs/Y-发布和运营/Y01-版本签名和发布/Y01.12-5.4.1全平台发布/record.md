# Y01.12 记录

## 2026-10-17

| 阶段 | 结果 |
|---|---|
| 1 版本号和发布说明 | `5.4.1+5105`；`releases/v5.4.1.md`（Linux 启动修复、第一批 5.x 苹果包、iOS/macOS/Linux 导入 3.x 数据）；README 中英文两版改成 5.4.1，下载表加 macOS、iPhone 和 iPad 两行，路线图分成 macOS、iOS 两行；头图的平台标签加“苹果”，重新渲染。同一批提交：3.x 数据在 iOS、macOS、Linux 上也导入（`LegacyLocations.documents`，3.x 除 Windows 外都放在 `<documents>/PURE_LIVE/HIVE_DB`）。门禁 `gate: passed (all, 14 members)` 后推送 `dceb44e8c` |
| 2 各平台构建和检查 | Android：`flutter build apk --release --split-per-abi`，包名 `com.mystyle.purelive`、versionCode 7105/6105/9105、versionName 5.4.1、证书 SHA-256 `1e832295…`、四个通知资源、16 KB 对齐。Linux：`tools/release/package_linux.sh`，解压后用全新的数据目录启动，截图到首页（中文，关注页空状态）。Windows：`pack-win5.ps1 dceb44e8c`；便携版启动截图到首页；安装版没有在这台电脑上运行。苹果：`apple.yml` 运行 39017756045（同一提交），macOS 通用二进制（x86_64 arm64）、iOS arm64，构建机上 macOS 版和 iPhone 模拟器里 iOS 版都启动到首页 |
| 3 K90 快速测试 | 同一提交的 v4dev 测试包（profile，5.4.1/7105）：首页关注列表正常；进虎牙“BFX vs WE”直播间播放、弹幕连接正常。手机只剩 1% 电量，没有做更多 |
| 4 标签、发布页 | 附注标签 `v5.4.1`（`dceb44e8c`）；先建草稿，上传本机六个包和 `SHA256SUMS.txt`（十个包）。Actions 构建产物从这里下载只有约 40 KB/s，所以新加 `apple-publish.yml`（`9e4cb1972`）：在 GitHub 上下载运行 39017756045 的产物、按它的 SHA256SUMS 核对后挂到发布页（运行 39021359132）。十一个文件 GitHub 记的 SHA-256 和 `SHA256SUMS.txt` 逐个一致；发布“纯粹直播 v5.4.1”，正式版、最新 |
| 5 更新文件 | `assets/version.json`：顶层和 android、windows、linux、macos、ios 都是 5.4.1、5105、504015105（macOS、iOS 第一次从 3.2.10 指到 5.x），下载地址是新仓库 v5.4.1 发布页；`assets/releases.json` 最前面加 5.4.1（`changelog` 是发布说明加 SHA-256）；新仓库和旧仓库 master 的这两个文件一起改，内容相同 |
