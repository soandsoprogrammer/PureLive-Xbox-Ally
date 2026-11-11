# 本轮网络与GitHub调研

- [mpv音频选项](https://mpv.io/manual/stable/)：多实例共享输出与独立音量；未启用独占音频。
- [微软按进程采集示例](https://github.com/microsoft/Windows-classic-samples/tree/main/Samples/ApplicationLoopback)：本地编译，仅验证进程includetree。
- [微博官方页面脚本](https://js.t.sinajs.cn/t6/apps/live/livepc/js/live.2c216a65.js)：网页仍只使用默认地址；可选档位以真实媒体探测为依据。
- [上游微博接口参考](https://github.com/ihmily/DouyinLiveRecorder/blob/add187f8d8c7ff7d231fcbee45cbb4f1ed247d3a/src/spider.py)：只参考公开接口与源流地址思路，匿名独立验证，未采用其登录数据。
- [斗鱼官方搜索页代码](https://shark2.douyucdn.cn/front-publish/douyu-web-master/_next/static/chunks/app/search/page-0126582f4da4fa22.js)：确认现有搜索接口与参数。
- [media-kit #1445](https://github.com/media-kit/media-kit/issues/1445)：直播Surface重挂后的seek失败；本仓库已移除该seek，且其音频正常，不可当作#49黑屏无声的结论。
- [mpv-android #613](https://github.com/mpv-android/mpv-android/issues/613)：旧MediaCodec切源Surface连接失败的参考；本次设备日志未出现同样原生错误，仍是待验证假设。
