# PureLive Xbox Ally 掌机版

基于 [纯粹直播 PureLive](https://github.com/wzgrx/PureLive) 的非官方 Windows 掌机版，面向 ROG Xbox Ally X 和使用 Xbox 手柄布局的 Windows 掌机。

- 适配 7 英寸横屏的三列布局、焦点描边和手柄按键提示。
- 首页用 LB / RB 切换栏目，X 搜索。直播间用 LB / RB 换台，X 打开房间列表，Y 切换弹幕，LT / RT 调节音量。
- 从 [Releases](https://github.com/soandsoprogrammer/PureLive-Xbox-Ally/releases) 下载 Windows x64 便携 ZIP，解压后运行 pure_live.exe。

掌机版修改日期为 2026-11-11。上游基线为 [PureLive 5.6.5 的 9b406e8 提交](https://github.com/wzgrx/PureLive/tree/9b406e8ecc46642233176ece200ec9aef5921cf0)。本项目依照 [AGPL-3.0](LICENSE) 分发，原作者和贡献者的版权声明随源码保留。

## 构建 Windows 掌机版

按 [toolchain.env](toolchain.env) 安装 Flutter 3.47.8、Visual Studio C++ 桌面开发工具与 NuGet。按 [Flutter SDK 说明](tools/flutter_sdk/README.md) 在独立 SDK 中应用仓库附带的补丁，并将该 SDK 的 bin 目录加入 PATH。

从仓库根目录执行：

```powershell
pwsh -NoProfile -File tools/ffmpeg_kit/fetch.ps1 windows
Set-Location apps/pure_live
flutter pub get
flutter build windows --release --dart-define=PURE_LIVE_HANDHELD=true
```

输出目录为 apps/pure_live/build/windows/x64/runner/Release。原项目说明见 [README.upstream.md](README.upstream.md)。原生依赖及源码入口见 [第三方组件说明](THIRD_PARTY_HANDHELD.md)。
