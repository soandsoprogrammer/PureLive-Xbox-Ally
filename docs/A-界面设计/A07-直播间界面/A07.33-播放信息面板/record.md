# A07.33 记录

- 2026-10-29：按用户反馈把第一版（15 项核心 + 14 项高级）收窄为 9 行，不做高级折叠；显示位置定为右侧面板，和“切换直播间”一致，不做画面浮层。编码器改从流元数据读取。
- 2026-10-29：实现面板、菜单入口、格式化逻辑和翻译；本环境没有 Flutter/Dart SDK，测试与门禁结果待补。

## 决定

- 不显示请求/实际档位、线路/CDN、租期、恢复、HDR、色彩、输出后端等；画质和线路按钮已有。
- 面板放在菜单面板的位置（`roomMenuOpensPanel`），不新增浮层、拖动或收起逻辑。
- 下载码率用 `cache-speed` 最近 3 次采样的平均；标签标明估算。
- 丢帧/已解码缺失时显示“—”，不推测。
- 流主机只取 `state.line.url.host`；中继/自有源写“本机中继”，不显示 query。
- 复制内容只含面板字段、完整 codec/encoder 和 mpv/FFmpeg 版本。

## 代码

- `features/live_play/buttons/room_menu_button.dart`
- `shared/panels/room_panel.dart`
- `features/live_play/logic/playback_info.dart`
- `features/live_play/dialogs/playback_info_panel.dart`
- `features/live_play/live_play_page.dart`
- `assets/translations/zh.json`、`en.json`
- 测试：`apps/pure_live/test/features/live_play/playback_info_test.dart`、`playback_info_panel_test.dart`，更新菜单布局测试

## 未做/待验证

- 真机三档布局、复制、1 秒刷新和后台停止未验证。
- `estimated-frame-number`/`frame-drop-count`/`metadata/by-key/encoder` 在 Android/Windows 的实际返回未验证，缺失时界面显示“—”。

## 本次实现

- 菜单第二组“获取直链”后面新增“播放信息”；点击后和“切换直播间”一样替换菜单面板。
- `PlaybackInfoPanel` 显示 9 行：分辨率、帧率、编码、编码器、音频、丢帧/已解码、缓冲、下载码率、流主机；底部一行 mpv/FFmpeg 版本；标题栏复制。
- 打开立即读一次 mpv 快照，之后每 1 秒刷新；会话状态变化立即重建；关闭或进后台停止定时器。
- 下载码率取 `cache-speed` 最近 3 次非零采样平均；编码器、音频、主机可换行；缺项显示“—”。
- 复制只包含这 9 行、版本和完整 video/audio codec；不含 URL query、Cookie、请求头。
- 菜单从 6 行变成 7 行，横屏 400 高面板改为可滚动；相关布局测试已更新。
- 2026-10-29 按反馈调整排版：固定 104px 标签列、值左对齐、行间细分隔线，播放器内核并入卡片底部；2× 字号或窄面板改为标签在上、值在下。同时删除“视口”行和 PlaybackStats 的 osd/window 读取。

## 检查结果

- `dart format --page-width 120 --set-exit-if-changed`（临时 Dart 3.13.5）：通过。
- WSL Python：`tools/docs/docs.py --check`、`tools/gate/check_deps.py`、`check_fixtures.py`、`check_ui_structure.py`、`tools/docs/owners.py --check`：通过。
- `flutter test` 和完整 `tools/gate/gate.sh --all`：本环境没有 Flutter SDK，未运行；需要维护者在有工具链的机器上跑。
- 真机：未验证。


2026-10-30已随5.4.22发布。当前执行者独立运行完整门禁和最终包验证；具体证据与原设备边界见Y01.33/verify.md。
