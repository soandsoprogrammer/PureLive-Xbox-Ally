# V02.52 任务书

## 背景与目标

窄屏五个独立路由通过AppNavigator打开，普通设置分类则在SettingsPage内部换content；两条导航路径确有不同。需要按手机既有分类体验统一切换，同时保留系统返回、深链和宽屏双栏，不能只关闭全应用动画。未计入5.4.17修复。

## 开始前

读本目录README、record与仓库PROCESS及UI规范；以issue原始截图和描述为依据。

## 范围

- [settings_page.dart](../../../../apps/pure_live/lib/features/settings/settings_page.dart)
- [app_router.dart](../../../../apps/pure_live/lib/routes/app_router.dart)
- [settings_route_pages.dart](../../../../apps/pure_live/lib/routes/settings_route_pages.dart)

## 验收

先复现再增加有效回归，复用既有组件；不改账号、用户数据、平台协议或其他操作。新提交独立门禁与对应端实机验证后才发布回复关闭。当前没有实现，不得据此关闭issue。
