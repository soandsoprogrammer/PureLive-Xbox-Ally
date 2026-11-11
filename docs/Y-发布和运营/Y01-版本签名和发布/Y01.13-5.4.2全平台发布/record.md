# Y01.13 记录

## 2026-10-18

| 阶段 | 结果 |
|---|---|
| 1 版本号和发布说明 | `5.4.2+5106`；`releases/v5.4.2.md`（小窗重做、macOS 的标题栏和菜单栏、iPhone 和 iPad 的分享、剪贴板、全屏返回、快捷键）；README 中英文两版改成 5.4.2（简介加一句、小窗一节重写、路线图的 macOS 和 iOS 两行），头图版本号改成 5.4.2 重新渲染。`check_version.py` 通过；门禁 `gate: passed (all, 14 members)` 后推送 `605bb8e9c` |
| 2 各平台构建和检查 | Android：`flutter build apk --release --split-per-abi`，包名 `com.mystyle.purelive`、versionCode 7106/6106/9106、versionName 5.4.2、minSdk 26、证书 SHA-256 `1e832295…`、四个通知资源、`zipalign -c -P 16` 全部 OK、14 个 `.so` 的 ELF 段对齐都 ≥ 0x4000。Linux：`tools/release/package_linux.sh`，解压后用全新的数据目录在 Xvfb 里启动，截图到首页（中文，关注页空状态）。Windows：`pack-win5.ps1 605bb8e9c`；便携版解压到临时目录，按自己的进程号启动、截图到首页、按进程号关掉；安装版没有在这台电脑上运行。苹果：`apple.yml` 运行 39081728701（同一提交），macOS 版在构建机上、iOS 版在 iPhone 模拟器里都启动到首页，macOS 有 Mac 的标题行和菜单栏 |
| 3 K90 快速测试 | 同一提交的 v4dev 测试包（profile，5.4.2/5106）：首页关注列表正常；进虎牙赛事直播间播放、弹幕连接正常；点小窗按钮缩成应用内小窗，应用不退到桌面 |
| 4 标签、发布页 | 附注标签 `v5.4.2`（`605bb8e9c`）；先建草稿，上传本机六个包和 `SHA256SUMS.txt`（十个包）；`apple-publish.yml` 运行 39083493103 在 GitHub 上核对四个苹果包的 SHA-256 后挂上。十一个文件 GitHub 记的 SHA-256 和 `SHA256SUMS.txt` 逐个一致；发布“纯粹直播 v5.4.2”，正式版、最新 |
| 5 更新文件 | `assets/version.json`：顶层和 android、windows、linux、macos、ios 都是 5.4.2、5106、504025106，下载地址是 v5.4.2 发布页；`assets/releases.json` 最前面加 5.4.2（`changelog` 是发布说明加 SHA-256）；新仓库和旧仓库 master 的这两个文件一起改，内容相同 |
