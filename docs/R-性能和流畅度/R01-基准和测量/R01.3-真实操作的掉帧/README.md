# R01.3 真实操作的掉帧：在 K90 上找根因并修

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：性能
- 来源：用户 2026-10-16：“优化性能，卡顿流畅度……这次主要优化性能流畅度”
- 相关：[R01.2](../R01.2-在K90上跑基准/README.md)（假数据基准：进出直播间每次约 3 帧超时）；[A03.5](../../../A-界面设计/A03-动效和手感/A03.5-全局阻尼和弹簧转场/README.md)（弹簧转场同时解决了转场的 GPU 开销）；记录 [record.md](record.md)

## 目标

- 在 K90 上用真实平台数据量常用操作的掉帧（翻平台标签、底部导航切换、进出直播间、滑动列表），每个卡顿先找到根因再改，改完再量，没变好就撤。
- 用户看到的变化：第一次翻到某个平台、进出直播间更顺；第一次进直播间不再顿一下。

## 方法

- Perfetto（`linux.ftrace` 的调度、`gfx`/`view` atrace、SurfaceView 的出帧时间）看主线程、raster 线程和其他线程在卡顿时做什么。
- VM Service 的 CPU 采样（profile 包，`flutter attach`）看 Dart 里是哪些函数和调用链。
- 应用内按帧记录：`apps/pure_live/lib/app/frame_log.dart`，只有带 `--dart-define=PL_FRAME_LOG=true` 的测量包才有，每帧的 build、raster、从垂直同步到出帧的总时长，超过 8.33 毫秒（120 Hz）记为超时。
- 前后对比用同一台手机、同样的操作、交替各跑三次；原版对照包是 `fefb26091` 只加帧日志。

## 改了什么

| 现象 | 根因 | 修法 |
|---|---|---|
| 翻页时顶栏每帧重排 | TabBar 每帧插值选中标签的字重，`TabLabel` 外面的 FittedBox 一直到 Scaffold 都不是重排边界 | `snapTabWeight`：字重过半时才切换，颜色照常渐变（只重画） |
| 第一次翻到平台标签卡 | 封面下载的 TLS 握手、读数据在 UI 线程；接口响应体逐字节 `addAll` 进 `List<int>` | `IsolateImageFileService` 在后台 isolate 下载；`BytesBuilder` 一次缓冲 |
| 进出直播间十几帧超时 | 3.x 的 fade-forwards 转场每帧把两个整页画进离屏图层，叠在视频上 GPU 超时 | 弹簧推入（A03.5），只移动和画阴影 |
| 第一次进直播间顿约 0.3 秒 | media_kit 安卓视频输出换 Surface（1×1 占位 → 视频尺寸）时在 UI 线程同步调 mpv（`vo=null`、wid、`vo=gpu`），mpv 重建解码器时 UI 一直等 | media_kit 分支加 `setPropertyAsync`（`mpv_set_property_async`），顺序不变、UI 不等 |

## 试过但撤掉的

- 没开读屏时不给系统语义树（`SemanticsGate`）：Dart 的 CPU 少了一半，但小米澎湃AI引擎改为更频繁地通过主线程查询界面，热页面翻页的超时帧从 8～9 变成 16～19，撤掉。
