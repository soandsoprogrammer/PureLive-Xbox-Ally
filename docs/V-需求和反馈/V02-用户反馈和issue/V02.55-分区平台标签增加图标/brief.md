# V02.55 任务书

## 背景与目标

手机和Windows共用AreasView，当前TabLabel只传平台名，电视另有平台标签。后续应复用既有平台图标资源，保持中文名、平台顺序、选中态及无障碍语义，并检查窄屏、大字体和横向滚动；无需新下载图标。

## 开始前

读本目录README、record与仓库PROCESS及UI规范；以issue原始截图和描述为依据。

## 范围

- [areas_page.dart](../../../../apps/pure_live/lib/features/areas/areas_page.dart)
- [tv_areas_pane.dart](../../../../apps/pure_live/lib/tv/pages/tv_areas_pane.dart)

## 验收

先复现再增加有效回归，复用既有组件；不改账号、用户数据、平台协议或其他操作。新提交独立门禁与对应端实机验证后才发布回复关闭。当前没有实现，不得据此关闭issue。
