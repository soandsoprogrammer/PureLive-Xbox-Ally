# Windows 插件管理

纯粹直播的主体包包含播放器、平台组件和插件管理。它可以直接运行，不依赖录制插件、翻译插件、FFmpeg 或 Ollama。

在「设置 → 插件管理」打开插件目录弹窗，选择「安装」或「卸载」。安装源来自程序目录内或同级的 plugin-catalog 文件夹。单独下载插件目录包时，把其中的 plugin-catalog 和解压后的主体文件夹放在同一层。也可以把单个插件包的可执行文件解压到 plugin-catalog，再从弹窗安装。请使用可信的插件包。

已安装的插件会显示「设置」，可以修改该插件的选项。保存后即时刷新插件设置，卸载时会保留配置。

安装会复制插件可执行文件到 %LOCALAPPDATA%\PureLiveRust\plugins；卸载会移除可执行文件并保留插件配置和录制文件。

## 直播录制

录制包提供 `purelive-recording.exe`。安装后，播放控制栏会出现「录制」。录制只保存直播源的音视频，建议点「停止录制」并等保存提示后再退出。

录制插件复用播放器的直播源读取能力，不需要 FFmpeg。HTTP FLV 输出为 `.flv`，未加密的 HLS 按源格式输出为 `.ts` 或分段 `.mp4`。录制不重新编码，也不会把不同格式统一转换成 MKV。当前不支持加密 HLS 或音视频分开的 HLS 线路。

在「直播录制 → 设置」可以选择保存文件夹，改动从下一次录制生效。录制跟随当前播放的房间。录制默认保存到 `%LOCALAPPDATA%\PureLiveRust\recordings`，也可用 `PURELIVE_RECORDINGS_DIR` 指定目录。直播源中断时，插件会尽可能保留已接收的完整数据。

## 本地翻译

翻译包提供 `purelive-translation.exe`。启动 Ollama 并准备模型后，插件会尝试翻译房间标题和弹幕。服务不可用时保留原文。插件只请求本机的 `127.0.0.1:11434`。

默认使用 `qwen2.5:1.5b`。在「本地翻译 → 设置」可以修改模型、目标语言和翻译范围。配置也可通过插件目录内的 `translation.json` 编辑：

```json
{
  "enabled": true,
  "model": "qwen2.5:1.5b",
  "target_language": "Simplified Chinese",
  "room_titles": true,
  "danmaku": true
}
```

## 多直播同屏

在插件管理安装「多直播同屏」。在关注页的房间卡片上点「+ 同屏」，选 2–4 个房间后点列表左上角的「同屏」。每个房间独立连接，顶部房间按钮可切到单路声音，「全部声音」可同时播放所有房间的声音；返回会停止同屏播放并保留选中的房间。

键盘 F3 选择当前房间，F4 打开同屏。手柄按右摇杆选择，按住 RB 再按右摇杆打开。进入同屏后左右切换单路声音，键盘 A 或手柄 A 切换全部声音，按 Esc 或 B 返回。

## 文本规则

主体也能读取插件目录里的文本替换规则 JSON。规则只修改显示文本，不运行脚本。以下示例会在 Twitch 标题和弹幕里展开缩写：

```json
{
  "version": 1,
  "kind": "text_rules",
  "platform": "twitch",
  "surfaces": ["room_title", "danmaku"],
  "rules": [{"from": "GGWP", "to": "Good game, well played"}]
}
```

## 打包

应用源码在 `src`，录制和翻译实现分别位于 `plugin-tools/recording.rs` 和 `plugin-tools/translation.rs`。常规构建只生成主体，启用 Cargo 的 `plugin-tools` 功能并指定相应的二进制目标可以单独构建插件。Windows 工作流单独上传主体产物和可选插件压缩包。
