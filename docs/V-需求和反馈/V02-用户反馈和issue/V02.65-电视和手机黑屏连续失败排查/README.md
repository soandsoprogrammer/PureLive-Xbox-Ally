# #49：失败后持续黑屏的证据与修复

## 原反馈与判断边界

截至2026-10-30复查22条评论。Sony KD-65X8566E Android 9/v7a与Honor 9X均有正常房间A、失败房间B、返回A后持续失败的描述；荣耀补充同平台也可触发，慢连接后的换线/重试比跨平台更关键。电信Wi-Fi与移动热点均出现成功和失败，软硬解、兼容模式也未稳定排除故障。现有证据不支持归咎用户硬件损坏、单一运营商或用户操作。

Honor日志中的qualities/urls阶段StreamUnavailable发生在取流阶段；Sony的core-idle=yes、pause=no和未知属性发生在原生播放阶段，两者不能合并为一个已证实根因。旧诊断中的问号混合属性不可用、异常和超时，不能解释成“已证实没有轨道”。本次把未知状态细分，并增加idle-active、轨道数、vo/vid/aid和进程内内核/打开次数编号；不记录URL、账号或Cookie。

## 可复现的本地缺陷

| 路径 | 修复前证据 | 本次修改 |
|---|---|---|
| AndroidVideoController初始化 | 实际factory的Create回复前注入Surface回调，最终vo=null而非gpu | 初始选项与Surface写入共用锁，初始化后重放最新绑定；不等待Surface才启动解码 |
| PlaybackSession卡住的open | 未返回的B操作令后续A仍停在opening | source_open_timeout先隔离旧传输和内核，再做刷新/换线；持续无进度仅允许一次重建 |
| 进入房间前的音量命令 | 卡住B后立即返回A，setVolume在打开超时之外排队，19秒仍无恢复 | 音量命令纳入同一个源打开截止时间；迟到的旧命令不再打开旧源 |
| 原生初始化/释放 | 初始化无截止时间；释放等待可阻止替换 | 初始化超时报告明确错误；释放和旧输入并行、有5秒宽限，未释放资源最多占两个槽，完成后才允许再分配 |
| LiveVideoView替换内核 | r3在原生截图已有彩条、进度/轨道正常时，实际屏幕仍黑；VideoState只在initState订阅宽高 | Video以controller身份作为key，内核更换时重新挂载、取消旧订阅 |
| 原生属性读写 | Dart Future包装同步FFI，timeout不能打断被阻塞的UI isolate | 配置使用异步写入；诊断/播放统计使用mpv_get_property_async，超时移除请求，回调内复制事件数据后释放 |

普通HTTP失败保留健康内核并走原线路策略；用户暂停不自动重建。迟到的打开、资源释放、音量回复不得更改当前房间。释放报错仍计入资源上限，不能把超时当作原生资源已经释放。

## 上游和网络核对

- [media-kit #1445](https://github.com/media-kit/media-kit/issues/1445)：直播Surface再附着、seek和解码器重建会互相影响；后续尝试仍有黑屏/死锁。当前fork已有不seek的处理，不能仅照抄移除seek就声称修复。这里只采用事件顺序审查的方法。
- [mpv官方core-idle说明](https://mpv.io/manual/master/#command-interface-core-idle)：core-idle涵盖未播放、重启等多种状态，不是硬件故障结论。
- [libmpv官方client API](https://github.com/mpv-player/mpv/blob/master/include/mpv/client.h)：异步属性读取从GET_PROPERTY_REPLY取得错误码和数据；数据必须在下一事件前复制。实现未复制上游代码，保留fork的MIT声明。
- [mpv-android #1088](https://github.com/mpv-android/mpv-android/issues/1088)：特定Amlogic硬解路径不能证明Sony/Honor问题，原反馈的软件解码也失败。
- [media-kit #1437](https://github.com/media-kit/media-kit/issues/1437)：上游捆绑TLS实现与本项目自建原生库不同，不能据此断言本例是TLS或运营商问题。
- [Android MediaCodec](https://developer.android.com/reference/android/media/MediaCodec)：原生解码器有独立状态和恢复/释放约束，但本次没有原机CodecException证据。
- liuchuancong/media_core已fetch到47d7b48；对照305228eb、9ecefc0的创建/打开失败资源释放和恢复分层，以及645f49e的实际改动。借鉴恢复隔离和验证思路，不迁移架构、不宣称上游提交直接解决本例。

## 验证与限制

使用独立Android 9 x86_64模拟器、生成的60秒H.264/AAC彩条视频和仅环回HTTP服务，测试不连接真实平台。未操作物理手机或正式包。声卡输出禁用，所以48kHz音轨和音频参数是解码证据，不是扬声器听感验证。

未修改运行时代码的基线，普通404/短暂连接停顿后返回正常源本就通过；保留该结果，不冒充稳定复现了Sony原机故障。故障注入确认未完成操作的传播缺陷；随后真实Android测试额外发现重建后的画面挂载缺陷。r3原生彩条与黑屏对照保留，r4是重挂画面组件后的候选。最终视觉验收、门禁、包和哈希单独登记。

Sony v7a、Honor Kirin硬件、真实平台限流/取流波动仍没有同机复验。本次发布可包含已证实的恢复缺陷修复，但#49保持开放，不再要求用户重复清数据、反复切换软硬解或网络。后续只核对新版在同一A→失败B→A序列中的结果和新的分层诊断。
