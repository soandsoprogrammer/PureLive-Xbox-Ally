# V02.51 电视配置预览布局焦点

来源：[#59](https://github.com/wzgrx/PureLive/issues/59)。

## 评估

截图已查看：配置预览在右栏、左侧仍为设置总览。代码确认电视入口将configPreview转到通用SettingsPage，该页按840断点走双栏；需要改为电视全页并覆盖长JSON树遥控滚动、返回及焦点。当前是代码路径与截图吻合的线索，未在Sony原机验证。

## 代码入口

- [tv_settings_catalog.dart](../../../../apps/pure_live/lib/tv/settings/tv_settings_catalog.dart)
- [settings_page.dart](../../../../apps/pure_live/lib/features/settings/settings_page.dart)
- [data_tools.dart](../../../../apps/pure_live/lib/features/settings/data_tools.dart)

## 当前进度

5.4.17冻结范围后到达，仅评估登记并回复，保持issue开放；没有计入本版已修复，也尚未完成原机验收。


## 5.4.18 最终交付

5.4.18实现、分层验证及发布收尾见交付记录；未覆盖的原设备场景不外推。

[交付与验证范围](../../../Y-发布和运营/Y03-发布说明和README/releases/v5.4.18.md)。此前候选待验状态由本节更新；原始失败证据保留。
