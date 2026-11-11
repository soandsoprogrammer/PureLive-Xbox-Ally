# V02.14 任务书

## 背景与约束

在 `ai/V02.14` 修复 issue #12，保留从 `3fec57539` 恢复的未提交改动。只调整桌面音量提示及必要的控制栏等待行为；不改手机系统音量、键盘步进、视频布局、用户数据、版本号或更新文件。

## 验收

1. 连续滚轮和方向键步进正确，画面中间没有音量提示。
2. 滑块、静音和滚轮交替使用时从当前音量继续，不能跳回旧值。
3. 百分比固定宽度，拖动期间可见；按住超过 4 秒控制栏仍在，释放后恢复自动隐藏。
4. 拖动中切换布局或离开房间不遗留持有状态或定时器。
5. 相关回归、全量门禁通过；桌面启动和实际交互验收另记，不以 widget 测试代替。

## 文件与验证

播放器目录 `apps/pure_live/lib/features/live_play/player/`，测试 `apps/pure_live/test/features/live_play/room_popups_test.dart`，相关控制器和播放会话只读。先运行 `flutter test test/features/live_play/room_popups_test.dart --plain-name 'issue #12'`，推送前运行 `bash tools/gate/gate.sh --all`。
