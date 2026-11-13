# 第三方组件

- 直播平台、弹幕、IPTV 和中继适配器来自 [PureLive 5.6.5](https://github.com/wzgrx/PureLive/tree/9b406e8ecc46642233176ece200ec9aef5921cf0)。本仓库保留所用模块的源文件，掌机进程入口位于 `tools/live_cli/bin/handheld_platforms.dart`。第三方 Rust 和 Dart 包的版本及校验信息见 `gpui-prototype/Cargo.lock` 和 `pubspec.lock`，便携包附带构建环境中的许可证文本。
- Windows C++ 可再发行运行库和系统安装的 Microsoft Edge WebView2 Runtime 适用各自的 Microsoft 许可。
- 播放器使用 OxideAV、Symphonia、m3u8-rs 和 Windows Media Foundation、D3D11、WASAPI。
- 本地语音搜索使用 [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 和 [ONNX Runtime](https://github.com/microsoft/onnxruntime)。模型由用户按需准备。
