# V02.54 电视启动初始焦点框

来源：[#62](https://github.com/wzgrx/PureLive/issues/62)。

## 评估

两张对照图已查看，蓝色选中态和白色焦点框须区分。TvHomePage已有启动及提示后requestFocus，因此不能仅凭截图认定未请求焦点；需复现首次/再次启动、无按键状态和弹窗关闭后的节点状态及框绘制。未在Sony原机定位。

## 代码入口

- [tv_home_page.dart](../../../../apps/pure_live/lib/tv/home/tv_home_page.dart)
- [tv_nav_item.dart](../../../../apps/pure_live/lib/tv/widgets/tv_nav_item.dart)
- [tv_focusable.dart](../../../../apps/pure_live/lib/tv/widgets/tv_focusable.dart)

## 当前进度

5.4.17冻结范围后到达，仅评估登记并回复，保持issue开放；没有计入本版已修复，也尚未完成原机验收。


## 5.4.18 最终交付

5.4.18实现、分层验证及发布收尾见交付记录；未覆盖的原设备场景不外推。

[交付与验证范围](../../../Y-发布和运营/Y03-发布说明和README/releases/v5.4.18.md)。此前候选待验状态由本节更新；原始失败证据保留。
