# Y01.16 记录

## 2026-10-20～21

| 阶段 | 结果 |
|---|---|
| 1 版本号和发布说明 | `5.4.5+5109`；`releases/v5.4.5.md`：玻璃底栏手感（A01.7）、平板也用底栏（V02.6，issue #4）、平板退出全屏的方向（V02.8，issue #5）、部分哔哩哔哩直播间误报“播放器异常”（G02.4）、问题反馈表单（V02.5）和旧仓库搬家说明（issue #3），发布前又加了“底层组件”一段（工具链升级、录制用的 FFmpeg 组件换成 FFmpegKit 0.11.2，Z01.2）。README 中英文两版和头图在 `b9a6f8c35` 已改成 5.4.5。`check_version.py` 通过 |
| 2 各平台构建和检查 | 用户要求先升级再发（“先升级，再发 5.4.5”），所以发布提交是工具链升级之后的 `854ea224b`（门禁 `gate: passed (all, 14 members)`）。升级里 ffmpeg_kit_extended_flutter 1.0.0 配旧的 FFmpeg 包会让录制崩溃，五个平台的 FFmpeg 包全部重编（`native-ffmpeg-9.0.2-b2`，过程在 Z01.2 记录）。Android：包名 `com.mystyle.purelive`、versionCode 6109/7109/9109、versionName 5.4.5、证书 SHA-256 `1e832295…`、通知资源四个都在、`zipalign -c -P 16` 全部 OK、arm64 和 x86_64 的 `.so` 段对齐都 ≥ 0x4000，三个 ABI 的 `libffmpegkit.so` 和 b2 的 AAR 逐个一致。Linux：`package_linux.sh`，包里的 `libffmpegkit.so` 和 b2 一致；Xvfb 里用全新的数据目录启动，截图到首页（无头环境没有托盘宿主，nativeapi 提示托盘可能不显示）。Windows：`pack-win5.ps1 854ea224b`（日志确认是这个提交），便携版里的 `libffmpegkit.dll` 和 b2 一致；按自己的进程号启动、截图到首页、按进程号关掉。苹果：`apple.yml` 运行 39473749203，macOS 截图到首页、菜单栏图标在（tray_manager 0.8），iPhone 模拟器到首页 |
| 3 K90 快速测试 | 等 K90 上别的项目的测试停了 5 分钟后再用。同一提交的 v4dev 测试包（profile，5.4.5/5109）：首页关注列表、底栏切到热门正常；哔哩哔哩直播间播放（首帧 200 ms），没有“播放器异常”；在这个直播间录 21 秒，停止后保存，没有崩溃。之前用同一份 b2 AAR 的测试包在斗鱼录过 36 秒和跨分段的 6 分钟，完整解码无错 |
| 4 标签、发布页 | 附注标签 `v5.4.5`（`854ea224b`）；先建草稿，上传本机六个包和 `SHA256SUMS.txt`（十个包）；`apple-publish.yml` 运行 39477213896 从 39473749203 核对后挂上四个苹果包。十个包 GitHub 记的 SHA-256 和 `SHA256SUMS.txt` 逐个一致；发布“纯粹直播 v5.4.5”，正式版、最新 |
| 5 更新文件 | `assets/version.json`：顶层和 android、windows、linux、macos、ios 都是 5.4.5、5109、504045109，下载地址是 v5.4.5 发布页；`assets/releases.json` 最前面加 5.4.5；新仓库和旧仓库 master 的这两个文件一起改，内容相同 |
