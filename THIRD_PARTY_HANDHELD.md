# Windows 掌机版第三方组件

- Flutter Windows 引擎和 Dart SDK 版本见 [toolchain.env](toolchain.env)。Flutter 源码见 [固定版本](https://github.com/flutter/flutter/tree/737ba8f885dc774b53b442759999a312c9461e4e)，本仓库的 [SDK 补丁](tools/flutter_sdk) 用于构建。
- FFmpeg 和 FFmpegKit 的原生包版本、校验值和下载链接见 [bundles.txt](tools/ffmpeg_kit/bundles.txt)，对应构建脚本和源码引用见 [rebuild](tools/ffmpeg_kit/rebuild)。原生包附带的许可证随便携 ZIP 提供。
- libmpv 的 Windows x64 预编译包和校验值见 [native_bundles.json](third_party/media_kit/hook/native_bundles.json)。构建仓库见 [Predidit/libmpv-win32-video-cmake](https://github.com/Predidit/libmpv-win32-video-cmake/tree/202609151348)，mpv 源码基线见 [0b7ed67](https://github.com/mpv-player/mpv/commit/0b7ed670f7c353dd3dd4f8ae0fc788a181a15aa6)，接口说明见 [mpv headers README](third_party/media_kit_video/common/mpv/README.md)。
- libwebrtc 的版本见 [libwebrtc_version.ini](third_party/flutter_webrtc/third_party/libwebrtc_version.ini)，源码和构建入口见 [webrtc-sdk/libwebrtc](https://github.com/webrtc-sdk/libwebrtc/tree/libwebrtc.m150.7871.07)，包内许可证随便携 ZIP 提供。
- Dart 与 Flutter 插件版本、源包地址和校验值见 [pubspec.lock](pubspec.lock)。其中本仓库维护的插件源码位于 [third_party](third_party)。Microsoft Windows 运行库由相应供应商许可。
