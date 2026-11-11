# Y01.10 记录

## 2026-10-16

| 阶段 | 结果 |
|---|---|
| 1 版本号和发布说明 | `5.3.0+5103`；`releases/v5.3.0.md`（八个平台的官方登录、怎么登录、已知问题；“修复”一节）；README 换成 5.3.0 的真机截图并新增英文版（Y03.2） |
| 2 各平台构建和检查 | 第一次构建 `86455ac33`：Windows 便携版冒烟时发现宽屏直播间看竖屏直播流，背景图（封面放大 1.14 倍）有约 7% 压在右侧聊天栏上，没有裁剪；`e55253f09` 给 `AmbientBackdrop` 加 `ClipRect`（测试在旧代码上失败），门禁 `gate: passed (all, 14 members)` 后推送，全部重新构建。Android：`flutter build apk --release --split-per-abi`，包名 `com.mystyle.purelive`、versionCode 7103/6103/9103、versionName 5.3.0、证书 SHA-256 `1e832295…`（和 3.x 同一把）、三个 `ic_stat_*` 通知图标（和 5.2.0 相同）、16 KB 对齐、液态玻璃着色器在包里。Linux：`tools/release/package_linux.sh`，WSL 里启动 20 秒不退出。Windows：`pack-win5.ps1 e55253f09`；便携版启动、热门、进哔哩哔哩竖屏直播间播放和弹幕正常，聊天栏左边干净；安装版没有在这台电脑上运行（装着用户的 3.x）。安装包和 `SHA256SUMS.txt` 在 `~/ref/release/v5.3.0-5103/` |
| 3 K90 快速测试 | 同一提交的 v4dev 测试包（profile，5.3.0/5103）：关注页的液态玻璃底栏、进虎牙直播间播放和弹幕、返回、按住底栏拖到“分区”切换。官方登录在开发时逐个打开过登录页（K01.3），没有用真实账号登录 |
| 4 标签、发布页 | 附注标签 `v5.3.0`（`e55253f09`）；发布页“纯粹直播 v5.3.0”（正式版、最新），六个包和 `SHA256SUMS.txt`，GitHub 记的 SHA-256 和本机逐个一致 |
| 5 更新文件 | `assets/version.json`：顶层和 android、windows、linux 都是 5.3.0、5103、503005103，下载地址是新仓库 v5.3.0 发布页（macOS、iOS 还是 3.2.10）；`assets/releases.json` 最前面加 5.3.0（`changelog` 就是发布说明全文）；新仓库和旧仓库 master 的这两个文件一起改，内容相同 |

另：斗鱼“DNF官方直播间”（470321）在多画面和直播间里都提示“平台显示在播，但没有给出可播放的地址”：`live_cli probe douyu 470321` 得到 `getH5PlayV1: streamStatus 0 (no stream pushed)`，是 E01.7 记下的平台情况（在播但没有推流），不是应用的问题。
