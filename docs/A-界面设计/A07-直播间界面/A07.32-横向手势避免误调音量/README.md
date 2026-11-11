# 横向手势避免误调音量

来源：[#93](https://github.com/wzgrx/PureLive/issues/93)。反馈者关闭了最初的方向错位报告，但确认竖屏沉浸模式横向滑动时，少量纵向偏移会误调音量或亮度。

旧手势层只有纵向识别器，横向移动累计的纵向偏移也会被接受。增加横向识别并在纵向开始时检查完整位移方向，覆盖一次事件跨过两个方向阈值的情况。使用down起点保留正常竖滑的全部位移，原生音量/亮度读取延迟时的移动累计、系统边缘和底部返回面板继续保留。

依据：Flutter官方[手势竞争](https://docs.flutter.dev/ui/interactivity/gestures)、[纵向识别器](https://api.flutter.dev/flutter/gestures/VerticalDragGestureRecognizer-class.html)，及当前固定SDK的gesture_detector.dart/monodrag.dart；GitHub上游搜索对照[识别器装配](https://github.com/flutter/flutter/blob/bbf18c1045fd540bf7148e4e0c36c1228de51ab1/packages/flutter/lib/src/widgets/gesture_detector.dart)。不将未复现的90度坐标错位称为已修复。
