# G02.6 RTP MPEG-TS 原生兼容修正

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
