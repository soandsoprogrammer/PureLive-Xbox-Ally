# Y01.14 记录

## 2026-10-18

| 阶段 | 结果 |
|---|---|
| 1 版本号和发布说明 | `5.4.3+5107`；`releases/v5.4.3.md`（iPhone 和 iPad 的分享扩展、后台和锁屏播放、⌘ 快捷键列表；macOS 标题栏保持方案 B）；README 中英文两版改成 5.4.3（简介加一句、路线图的 macOS 和 iOS 两行），头图版本号改成 5.4.3 重新渲染。`check_version.py` 通过；门禁 `gate: passed (all, 14 members)` 后推送 `561261b89` |
| 2 各平台构建和检查 | Android：`flutter build apk --release --split-per-abi`，包名 `com.mystyle.purelive`、versionCode 7107/6107/9107、versionName 5.4.3、minSdk 26、证书 SHA-256 `1e832295…`、通知资源和 5.4.2 相同、`zipalign -c -P 16` 全部 OK、arm64 和 x86_64 的 14 个 `.so` 段对齐都 ≥ 0x4000（armeabi-v7a 有三个 4K 的，32 位不要求）。Linux：`tools/release/package_linux.sh`，解压后用全新的数据目录在 Xvfb 里启动（要清空 `WAYLAND_DISPLAY`，否则窗口开到 WSLg 桌面、截图是黑的），截图到首页。Windows：`pack-win5.ps1 561261b89`；便携版解压到临时目录，按自己的进程号启动、截图到首页、按进程号关掉；安装版没有在这台电脑上运行。苹果：`apple.yml` 运行 39091908828（同一提交），macOS 版在构建机上、iOS 版在 iPhone 模拟器里都启动到首页 |
| 3 K90 快速测试 | 同一提交的 v4dev 测试包（profile，5.4.3/5107）：首页关注列表正常；进虎牙直播间播放、弹幕正常；返回首页正常 |
| 4 标签、发布页 | 附注标签 `v5.4.3`（`561261b89`）；先建草稿，上传本机六个包和 `SHA256SUMS.txt`（十个包）；`apple-publish.yml` 运行 39093641243 在 GitHub 上核对四个苹果包的 SHA-256 后挂上。十个包 GitHub 记的 SHA-256 和 `SHA256SUMS.txt` 逐个一致；发布“纯粹直播 v5.4.3”，正式版、最新 |
| 5 更新文件 | `assets/version.json`：顶层和 android、windows、linux、macos、ios 都是 5.4.3、5107、504035107，下载地址是 v5.4.3 发布页；`assets/releases.json` 最前面加 5.4.3（`changelog` 是发布说明加 SHA-256）；新仓库和旧仓库 master 的这两个文件一起改，内容相同 |

### 发布后的门禁

- 推送更新文件前的门禁失败两项。`version_page_test` 的“宽窗口发布历史”：每发一版列表多一项，最老的 3.2.11 被挤到可见区域外、点不中，改成先滚到可见再点。`live_alert_watch_test` 的“后台检查报过的不再报”：根因是 `live_alert_watch.json` 的写共用一个临时文件，同时写时后一次改名失败（O01.2 的说明里有详细记录），已修，5.4.3 的安装包里还有这个问题。
