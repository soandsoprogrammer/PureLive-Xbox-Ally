# V02.54 任务书

## 背景与目标

两张对照图已查看，蓝色选中态和白色焦点框须区分。TvHomePage已有启动及提示后requestFocus，因此不能仅凭截图认定未请求焦点；需复现首次/再次启动、无按键状态和弹窗关闭后的节点状态及框绘制。未在Sony原机定位。

## 开始前

读本目录README、record与仓库PROCESS及UI规范；以issue原始截图和描述为依据。

## 范围

- [tv_home_page.dart](../../../../apps/pure_live/lib/tv/home/tv_home_page.dart)
- [tv_nav_item.dart](../../../../apps/pure_live/lib/tv/widgets/tv_nav_item.dart)
- [tv_focusable.dart](../../../../apps/pure_live/lib/tv/widgets/tv_focusable.dart)

## 验收

先复现再增加有效回归，复用既有组件；不改账号、用户数据、平台协议或其他操作。新提交独立门禁与对应端实机验证后才发布回复关闭。当前没有实现，不得据此关闭issue。
