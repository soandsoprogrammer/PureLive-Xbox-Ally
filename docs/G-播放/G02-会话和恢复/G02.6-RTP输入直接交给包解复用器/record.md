# G02.6 RTP输入直接交给包解复用器

首轮5.4.15候选 `2abd6610c53ffd7582e75f0412aee4a189ae6b0f` 完整all/14及六个本地正式包通过，但Linux真实RTP测试停在缓冲，不能据协议白名单宣称已支持播放。所有首轮包、回执及失败图片已保留在本地独立 candidate-1 目录，未公开发布。

本地发送包为RTP v2、静态payload33，头后为MPEG-TS；独立FFprobe对原URL及显式本地端口URL均识别H.264/AAC，因此“必须显式本地端口”假设已被排除。精确候选libmpv默认路径将原始数据报交给字节探测，未识别有效视频；强制rtp格式在单播样本中遇重复绑定。mpv的opaque `av://rtp:<原rtp地址>` 直接使用FFmpeg RTP解复用器，受控对照已识别320像素视频及时间位置。原生应用持续变化画面仍需随后预检，不把这一步识别写成完整播放器验收。

官方对应修复：[mpv 4fdd1d4662](https://github.com/mpv-player/mpv/commit/4fdd1d4662)、[原报告18115](https://github.com/mpv-player/mpv/issues/18115)。本项目不复制C实现、不替换二进制内核，仅在MpvEngine打开RTP时映射内部输入，保留原媒体地址、端口、查询参数、重连和录制数据；其他协议使用原字符串，不改全局解复用选项，不影响后续HTTP／RTSP打开。

media_kit仅为这个内部RTP语法增加早返回，在Android content URI解析前保留opaque输入，避免把原媒体地址写进格式异常日志。四个组播、单播、参数与IPv6回归在原输入行为下失败，修正后连同六个其他协议对照全部通过；同时覆盖Media的实际标准化边界。测试不访问平台。

允许范围：packages/live_player 的 mpv_input.dart、mpv_engine.dart及对应测试，third_party/media_kit 的 media_native.dart精确内部RTP前置识别，本任务与发布文档。不得把RTP改写成UDP，不丢地址或查询参数，不改其他协议或全局mpv选项，不读用户数据库或正式安装。

步骤：保留原生失败和旧候选；原输入行为先跑失败回归，再启用RTP专用入口；Linux profile预检实际接收变化画面及节目单，之后完整all/14并由新提交重新构建十个包，核对远端哈希、各端启动和K90同源包。旧候选不混入新清单，原运营商网络仍有现场边界。

当前尚未发布，新候选原生结果与完整门禁后续记录。


## 实际profile接入补充

首次profile预检确认独立libmpv直开正常并不够：media_kit默认先写播放列表再loadlist，内部av RTP语法被播放列表协议策略拒绝，画面中断。现在仅fd与精确内部RTP入口走逐文件loadfile；其他av输入不放开，HTTP、RTSP、UDP仍走原路径。四项RTP加载策略回归在旧fd-only策略下失败，连同原归一化、描述符与任意av拒绝对照共12项修正后通过；失败profile与截图保留。允许范围补充native/core/direct_media_load.dart、native/player/real.dart及对应测试。后续仍须原生画面预检和新提交完整门禁、十包。


## Linux profile原生预检结果

接入逐文件路径后，使用原单播RTP地址和同一生成的视频，实际计数345→391、时间23.000→26.067秒，画面持续变化，首屏节目单出现。启动时出现一次video_decoder_runtime自动恢复，随后result=playing，后续画面持续变化且无新增恢复；未将这次容器测试写成零恢复、硬件解码或听感验收。该预检为profile、静音、回环网络，不是正式包或运营商现场验收。完整源指纹与截图哈希在独立回执中保留。

预检后仅补Android专用finalizer的fd前缀判断，避免对内部opaque RTP地址做Uri解析并打印格式异常；Linux的RTP输入、逐文件加载实现未改。此Android分支将在最终同源K90包中检查；最终提交仍需完整all/14及十包、正式Linux原生重验。未把profile源指纹替换成最终源指纹，两者及这一行Android差异分别记录。


## 第二候选否决及第三候选


## 当前方案及根因

首轮候选的普通 RTP 输入自动探测未识别 MPEG-TS。第二候选 opaque av 入口在 Linux 实际播放通过，但同源 K90 测试失败；精确 Android libmpv 的诊断确认 FFmpeg 没有 rtp 和 sdp 解复用器，均返回 Unknown lavf format。强制 mpegts 后识别 H.264 和视频尺寸，说明 Linux 的成功不能替代 Android 验收。两轮全部包、失败及诊断回执独立保留，均未公开发布。

最终方法保持原始 RTP URL、协议、端点及参数，只在每次 open 前按协议设置 demuxer-lavf-format：RTP 为 mpegts，其他来源明确清空。配置完成后才打开媒体，失败不打开；复用播放器切到 MP4/HLS/RTSP 时不遗留容器状态。EngineMedia、录制地址、HTTP headers 与 start 参数不改。范围是 MPEG-TS over RTP，不宣称支持任意动态 RTP 编码或完整 RTP 解复用器能力。

第二候选对 third_party/media_kit 的所有 RTP 专用修改已恢复到首轮版本；不再使用 opaque 语法，不需要放宽播放列表或内容 URI 规则。只改 packages/live_player 的 mpv_input.dart、mpv_engine.dart 和对应测试，以及本任务与发布文档。原生内核不换包，不把 RTP 改成 UDP。

## 验证与发布条件

12 项输入协调回归覆盖单播、组播、IPv6、参数保留、RTP→其他容器清空、异步配置顺序和失败阻断。K90 必须用正常 v4dev profile 应用依次验证 RTP、HTTP MP4、RTP 的变化画面；诊断工具识别到尺寸不算通过。随后冻结源码跑完整 all/14，重新构建全部十包，核对 Android/桌面真实正式候选、Apple 检查和远端 11 项哈希。两轮旧包不混入最终清单。

生成媒体、私网发送和回环接收只证明所测链路；不代表运营商组播网络、音质或 Apple 真机播放。只有最终同源原生证据齐备才公开 5.4.15。


## 第三候选首帧否决与第四候选

第三候选在完整门禁和Linux原生通过后，最终K90包仍出现首帧前 video_decoder_runtime 两次、2.9秒即终止恢复，实际画面后来仍变化的错误遮罩。已否决，相关APK哈希、Info日志及离线复现保留。G02.7只给RTP首次输出前可恢复解码诊断增加有界等待；最终普通包必须多次冷启动、重载与协议切换，并逐对检查画面和本次日志，不能沿用第三候选预检作为最终验收。临时本地日志开关最终恢复原关/Info。


## 5.4.15 发布交付

最终RTP保持原URI并显式选择MPEG-TS，其他协议每次清空覆盖；12项输入协调回归及K90、Linux实际变化画面通过。前三轮否决与第四轮扩充前候选全部保留，由最终提交重建十包；原运营商及Apple真机仍有边界。

已发布 [5.4.15](https://github.com/wzgrx/PureLive/releases/tag/v5.4.15)，PR #50 已合并。详见[完整验证、范围限制和本次旧库例外记录](../../../Y-发布和运营/Y01-版本签名和发布/Y01.26-5.4.15全平台发布/verify.md)。
