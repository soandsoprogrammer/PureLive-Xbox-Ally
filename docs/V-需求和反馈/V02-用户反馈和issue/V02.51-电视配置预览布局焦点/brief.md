# V02.51 任务书

## 背景与目标

截图已查看：配置预览在右栏、左侧仍为设置总览。代码确认电视入口将configPreview转到通用SettingsPage，该页按840断点走双栏；需要改为电视全页并覆盖长JSON树遥控滚动、返回及焦点。当前是代码路径与截图吻合的线索，未在Sony原机验证。

## 开始前

读本目录README、record与仓库PROCESS及UI规范；以issue原始截图和描述为依据。

## 范围

- [tv_settings_catalog.dart](../../../../apps/pure_live/lib/tv/settings/tv_settings_catalog.dart)
- [settings_page.dart](../../../../apps/pure_live/lib/features/settings/settings_page.dart)
- [data_tools.dart](../../../../apps/pure_live/lib/features/settings/data_tools.dart)

## 验收

先复现再增加有效回归，复用既有组件；不改账号、用户数据、平台协议或其他操作。新提交独立门禁与对应端实机验证后才发布回复关闭。当前没有实现，不得据此关闭issue。
