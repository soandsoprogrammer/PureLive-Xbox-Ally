# PureLive Rust 掌机版

Windows x64 掌机版使用 GPUI Kit、XInput、libmpv 和 WebView2。平台目录包括旧版的 34 个直播站点和 IPTV。Rust 程序在需要时调用便携包中的 `purelive-platforms.exe`，复用旧版 Dart 游客适配器和需要持续保持连接的播放中继。首页和播放界面由 Rust 提供。

## 试用

解压便携包后运行 `purelive-gpui.exe`。平台横排在「热门」右边，按左右键移动，平台栏会跟随焦点滚动。选站后按下浏览该站直播。「搜索」支持直播间链接、关键词和数字房间号。频道 ID 前加 `@`，例如选 Twitch 后输入 `@频道名`。选 IPTV 后可输入 M3U / TXT 播放列表文件路径或网址。

LB / RB 切换工具，方向键选房间或平台，Enter 或 A 打开，Y 切换选中房间的关注状态，Esc 或 B 返回。关注保存在 `%LOCALAPPDATA%\PureLiveRust\follows.json`。各站的游客搜索与播放能力依平台而异。兼容组件可读取 `HTTPS_PROXY` / `HTTP_PROXY` 环境变量。

播放时轻点画面或按 A 唤出控制栏，方向键选按钮，A 确认，LB / RB 翻线路或画质选项。X 刷新直播，Y 切换关注，B 依次关闭选项、收起控制栏、返回列表。键盘也可用空格暂停或播放、R 刷新、D 开关弹幕。线路和画质选项由当前平台提供。支持弹幕的直播间默认开启弹幕，开关选择会保存在本机。

「音量」面板用方向键按 5% 调整，A 切换静音。播放器音量和静音会保存在本机。键盘可用 + / − 调整、M 静音。支持醒目留言的平台会显示「SC 历史」。记录按最新到最早排列，包括平台提供的近期留言和本次连接收到的醒目留言。方向键翻阅，X 刷新，退出直播间后清除本次历史。

在「设置 → 账号」选择平台，再点「登录账号」。在平台官方网页完成登录后，点击「完成登录」。当前支持哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、Twitch 和 SOOP。应用用 Windows 用户级加密分别保存各站登录状态，并将其用于对应平台的直播请求。可在设置中单独清除某站的本地登录状态。

可通过 PowerShell 直接打开直播流 URL 或本地视频文件。

```powershell
.\purelive-gpui.exe --stream 'C:\Videos\sample.mp4'
```

账号登录按需创建 WebView2，需要系统安装 Microsoft Edge WebView2 Runtime。返回后释放登录页面或播放器。最小化时释放播放器，恢复时重新打开播放源。

测试版默认把 mpv 的 D3D11 呈现间隔设为 0。在同一块屏幕上加 `--vsync` 可以对比间隔为 1 时的掉帧与画面表现。

## 构建

使用 Windows x64 MSVC Rust 工具链、Visual Studio C++ 构建工具、Dart 3.13.7 和 Python 3.11 或以上版本。

从发布源码的仓库根目录执行以下命令。

```powershell
cargo build --manifest-path gpui-prototype/Cargo.toml --release --locked
New-Item -ItemType Directory -Force dist
dart pub get --enforce-lockfile
dart compile exe tools/live_cli/bin/handheld_platforms.dart -o dist/purelive-platforms.exe
```

按第三方组件说明下载并校验 Windows x64 libmpv 归档。将其中的 `libmpv-2.dll` 和 Windows x64 MSVC 可再发行运行库放入一个目录，再打包。[第三方组件](https://github.com/soandsoprogrammer/PureLive-Xbox-Ally/blob/rust-handheld/THIRD_PARTY.md)

```powershell
python gpui-prototype/package.py --native-dir 'C:\path\to\native'
```

开发时可用 `--probe home`、`--probe play --stream <视频路径>` 或 `--probe login --platform <平台 ID>` 记录首帧、播放或登录页面加载事件。记录写入 EXE 旁的 `probe.log`。
