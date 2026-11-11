# A03.5 全局阻尼和弹簧转场

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：性能
- 来源：用户 2026-10-16：“增加类似 Liquid Glass，物理动画，滑动，上下，左右流畅度，阻尼感”
- 相关：A03.1（下拉刷新列表的手感，这里推广到所有列表）、A03.2（翻页阈值和弹簧）；[R01.3](../../../R-性能和流畅度/R01-基准和测量/R01.3-真实操作的掉帧/README.md)（转场的 GPU 开销）

## 目标和改动

- 所有上下滑的列表（手机、平板）：和下拉刷新列表一样的 iOS 式减速和橡皮筋，到头后越拉越沉（最多手指的 0.52），松手用刷新弹簧弹回；不再有 Android 的拉伸或光晕。电脑保持到头停住（滚轮习惯）。代码：`packages/live_ui/lib/src/widgets/scrolling.dart` 的 `PureLiveScrollPhysics`、`PureLiveDampedScrollPhysics`。
- 标签条、筛选条、翻页（`TabBarView`）：到第一页、最后一页或条的两端也有同样的阻尼和回弹（以前硬停）；内容变短时停下后放回范围内。`PureLiveBoundedScrollPhysics`、`PureLivePageScrollPhysics`。
- 页面转场：新页从右边带弹簧推入（临界阻尼，0.15 秒走完四分之三、约 0.38 秒停稳，不越过），左边缘有渐隐的阴影；下面的页向左退四分之一并稍微变暗；返回时反过来。直播间仍然不动下面的页（M13.16）。代替 3.x 的渐变转场（它每帧把两个整页画进离屏图层）。`packages/live_ui/lib/src/theme/page_transitions.dart`、`AppMotion.pageTransitionSpring`、`SpringCurve`。

## 测试

- `packages/live_ui/test/page_transitions_test.dart`：弹簧曲线 0 到 1 不越过、前三分之一走完七成以上；推入时新页从右、下面的页向左，没有不透明度图层；返回在 0.4 秒内结束。
- `packages/live_ui/test/scrolling_test.dart`、`refresh_view_test.dart`、`motion_test.dart`：手机上的阻尼边、电脑的硬边、普通列表和刷新列表滑行距离一样、拉过头越拉越沉并弹回。
- `apps/pure_live/test/features/popular/popular_test.dart`（M13.16）：退出直播间的一瞬间点下面的平台标签马上切换（转场的阴影画笔不能挡点击）。
