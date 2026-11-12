# 第三方组件

- 直播平台、弹幕、IPTV 和中继适配器来自 [PureLive 5.6.5](https://github.com/wzgrx/PureLive/tree/9b406e8ecc46642233176ece200ec9aef5921cf0)。本仓库保留所用模块的源文件，掌机进程入口位于 `tools/live_cli/bin/handheld_platforms.dart`。第三方 Rust 和 Dart 包的版本及校验信息见 `gpui-prototype/Cargo.lock` 和 `pubspec.lock`，便携包附带构建环境中的许可证文本。
- Windows x64 libmpv 使用 [Predidit 的构建 202609151348](https://github.com/Predidit/libmpv-win32-video-cmake/releases/tag/202609151348)，对应的 [mpv 源码](https://github.com/mpv-player/mpv/tree/0b7ed670f7c353dd3dd4f8ae0fc788a181a15aa6) 和 [构建脚本](https://github.com/Predidit/libmpv-win32-video-cmake/tree/fdf75129fc694b5ca555ce73cffc43bb6943ae13) 均可下载。原生二进制归档为 `mpv-dev-x86_64-20260915-git-0b7ed67.7z`，SHA-256 为 `8adceab30b6bcc5503fa9d3823b68f4acd15ee1c41d6dc2492826f373531c10a`。版权与许可文本见 [licenses/mpv](licenses/mpv)。
- Windows C++ 可再发行运行库和系统安装的 Microsoft Edge WebView2 Runtime 适用各自的 Microsoft 许可。
