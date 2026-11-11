# Y01.9 记录

## 2026-10-16

| 阶段 | 结果 |
|---|---|
| 1 版本号和发布说明 | `5.2.0+5102`；`releases/v5.2.0.md`（流畅度的前后数字、阻尼回弹、弹簧转场、液态玻璃）；README 加了 5.2 一句和外观一节；版本测试改成允许发布期间更新文件还是上一版（它们最后才改） |
| 2 各平台构建和检查 | 提交 `2dd8c3b81`（门禁 `gate: passed (all, 14 members)` 后推送）。Android：`flutter build apk --release --split-per-abi`，包名 `com.mystyle.purelive`、versionCode 7102/6102/9102、versionName 5.2.0、证书 SHA-256 `1e832295…`（和 3.x 同一把）、四个通知图标都在、16 KB 对齐、液态玻璃着色器在包里。Linux：`tools/release/package_linux.sh`，WSL 里启动 20 秒不退出。Windows：`pack-win5.ps1 2dd8c3b81`；便携版启动、进哔哩哔哩直播间播放和弹幕正常；安装版没有在这台电脑上运行（装着用户的 3.x）。安装包和 `SHA256SUMS.txt` 在 `~/ref/release/v5.2.0-5102/` |
| 3 K90 快速测试 | 同一提交的 v4dev 测试包（profile）：热门列表上的液态玻璃底栏、进直播间播放和弹幕、返回、按住底栏拖到“分区”切换。流畅度的数字见 R01.3、A01.6 |
| 4 标签、发布页 | 附注标签 `v5.2.0`（`2dd8c3b81`）；发布页“纯粹直播 v5.2.0”（正式版、最新），六个包和 `SHA256SUMS.txt`，GitHub 记的 SHA-256 和本机逐个一致 |
| 5 更新文件 | `assets/version.json`：顶层和 android、windows、linux 都是 5.2.0、5102、502005102，下载地址是新仓库 v5.2.0 发布页（macOS、iOS 还是 3.2.10）；`assets/releases.json` 最前面加 5.2.0；新仓库和旧仓库 master 的这两个文件一起改，内容相同 |
