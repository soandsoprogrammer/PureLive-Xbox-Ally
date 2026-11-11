# V02.53 任务书

## 背景与目标

两张截图已逐张查看：普通分类有自定义背景与白框，IPTV为通用AppBar且背景覆盖。tv_router对独立页只包TvSettingsStyle，未统一使用TvSettingsScaffold；须逐页核对七页的首焦点、首项Up边界/滚动、标题返回和壁纸透明策略，不能将单一页面样式修补当七页验收。

## 开始前

读本目录README、record与仓库PROCESS及UI规范；以issue原始截图和描述为依据。

## 范围

- [tv_router.dart](../../../../apps/pure_live/lib/routes/tv_router.dart)
- [tv_settings_section_page.dart](../../../../apps/pure_live/lib/tv/settings/tv_settings_section_page.dart)
- [tv_settings_style.dart](../../../../apps/pure_live/lib/tv/settings/tv_settings_style.dart)

## 验收

先复现再增加有效回归，复用既有组件；不改账号、用户数据、平台协议或其他操作。新提交独立门禁与对应端实机验证后才发布回复关闭。当前没有实现，不得据此关闭issue。
