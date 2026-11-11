# Y01.17 记录

## 2026-10-21

| 阶段 | 结果 |
|---|---|
| 1 版本号和发布说明 | `5.4.6+5110`；`releases/v5.4.6.md`（网络电视热门 → 网络切换列表、删掉的内置列表不再回来，V02.9，issue #6）；README 中英文两版改成 5.4.6（简介加一句），头图版本号改成 5.4.6 重新渲染。`check_version.py` 通过；门禁 `gate: passed (all, 14 members)` 后推送 `d5eb04e8b` |
| 2 各平台构建和检查 | Android：`flutter build apk --release --split-per-abi`，包名 `com.mystyle.purelive`、versionCode 6110/7110/9110、versionName 5.4.6、证书 SHA-256 `1e832295…`、通知资源四个都在、`zipalign -c -P 16` 全部 OK、arm64 和 x86_64 的 `.so` 段对齐都 ≥ 0x4000，三个 ABI 的 `libffmpegkit.so` 和缓存里校验过的 b2 AAR 一致。Linux：`package_linux.sh`，Xvfb 里用全新的数据目录启动，截图到首页。Windows：`pack-win5.ps1 d5eb04e8b`（日志确认是这个提交），便携版解压到新目录，`libffmpegkit.dll` 和 b2 一致；按自己的进程号启动、截图到首页、按进程号关掉。苹果：`apple.yml` 运行 39568086995，macOS 和 iPhone 模拟器都到首页 |
| 3 K90 快速测试 | 等 K90 上别的项目的测试停了 5 分钟后再用（只读 logcat 判断，等待本身不发 adb 命令）。同一提交的 v4dev 测试包（profile，5.4.6/5110）：首页正常；热门 → 网络只有内置列表时不出现切换条；打开安徽卫视，23.5 秒后出画（iptv-org 的海外源慢，中途缓冲重连一次），节目单区正常。切换、删除、恢复在 V02.9 已用同样的代码在 K90 上测过 |
| 4 标签、发布页 | 附注标签 `v5.4.6`（`d5eb04e8b`）；先建草稿，上传本机六个包和 `SHA256SUMS.txt`（十个包）；`apple-publish.yml` 运行 39573579511 从 39568086995 核对后挂上四个苹果包。十个包 GitHub 记的 SHA-256 和 `SHA256SUMS.txt` 逐个一致；发布“纯粹直播 v5.4.6”，正式版、最新 |
| 5 更新文件 | `assets/version.json`：顶层和 android、windows、linux、macos、ios 都是 5.4.6、5110、504065110，下载地址是 v5.4.6 发布页；`assets/releases.json` 最前面加 5.4.6；新仓库和旧仓库 master 的这两个文件一起改，内容相同；issue #6 回复版本号并关闭 |
