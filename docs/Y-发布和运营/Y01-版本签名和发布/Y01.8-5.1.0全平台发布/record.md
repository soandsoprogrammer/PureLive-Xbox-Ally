# Y01.8 记录

## 2026-10-15～16

| 阶段 | 结果 |
|---|---|
| 1 版本号和发布说明 | `5.1.0+5101`；`releases/v5.1.0.md`（电视三个模式、壁纸、设置、浏览页，开播提醒，修复列表，已知问题，SHA-256）；README 已在 5.1.0 的第一个提交里改好 |
| 2 各平台构建和检查 | 提交 `007631be8`（门禁 `gate: passed (all, 14 members)` 后推送）。门禁这一轮先抓到两个问题并修了：Kick 的测试还在找旧的“Cloudflare”字样（`588aed6d2`）；弹幕基准测试在机器忙时失败——直播间的礼物合并按墙钟限流，测试按模拟帧走，改成直播间时钟可替换、测试用模拟时间（`007631be8`，32 个满负载进程下复测通过）。Android：`flutter build apk --release --split-per-abi`，包名 `com.mystyle.purelive`、versionCode 7101/6101/9101、versionName 5.1.0、证书 SHA-256 `1e832295…`（和 3.x 同一把）、四个通知图标都在、16 KB 对齐。Linux：`tools/release/package_linux.sh`，解开后有 README.txt、purelive.desktop、purelive.png，WSL 里启动 20 秒不退出。Windows：Windows 电脑上 `pack-win5.ps1 007631be8`（构建目录的远端从旧仓库改成新仓库）；便携版解压后启动，首页正常、热门列表拉到哔哩哔哩直播间；安装版没有在这台电脑上运行（装着用户的 3.x）。安装包和 `SHA256SUMS.txt` 在 `~/ref/release/v5.1.0-5101/` |
| 3 K90 快速测试 | 同一提交的 v4dev 测试包（profile）：哔哩哔哩直播间播放、弹幕，没登录也是完整昵称、没有访客横幅；Kick 热门列表、直播间 1080p60 播放和弹幕。其余各项在当天各任务的验证里做过（A17.x、H01.4、K02.1、O02.1、O04.1、S02.4、R01.2～R05.1） |
| 4 标签、发布页 | 附注标签 `v5.1.0`（`007631be8`）；发布页“纯粹直播 v5.1.0”（正式版、最新），六个包和 `SHA256SUMS.txt`，GitHub 记的 SHA-256 和本机逐个一致 |
| 5 更新文件 | `assets/version.json`：顶层和 android、windows、linux 都是 5.1.0、5101、501005101，下载地址是新仓库 v5.1.0 发布页（macOS、iOS 还是 3.2.10）；`assets/releases.json` 最前面加 5.1.0；新仓库和旧仓库 master 的这两个文件一起改，内容相同 |
