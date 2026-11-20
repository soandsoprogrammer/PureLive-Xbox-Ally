# Windows 插件管理

纯粹直播的主体包包含播放器、平台组件和插件管理。它可以直接运行，不依赖录制插件、翻译插件、FFmpeg 或 Ollama。

在「设置 → 插件」可以查看录制与翻译的安装状态。安装时只需把独立插件包里的可执行文件解压到 `%LOCALAPPDATA%\PureLiveRust\plugins`，然后选择「重新加载插件」。卸载时移走对应的可执行文件并重新加载。只安装你信任的插件包。

## 直播录制

录制包提供 `purelive-recording.exe`。安装后，播放控制栏会出现「录制」。录制只保存直播源的音视频，建议点「停止录制」并等保存提示后再退出。

录制插件需要 FFmpeg。把 `ffmpeg.exe` 放在插件同目录、加入 PATH，或用 `PURELIVE_FFMPEG` 指定路径。录制默认保存到 `%LOCALAPPDATA%\PureLiveRust\recordings`，也可用 `PURELIVE_RECORDINGS_DIR` 指定目录。

## 本地翻译

翻译包提供 `purelive-translation.exe`。启动 Ollama 并准备模型后，插件会尝试翻译房间标题和弹幕。服务不可用时保留原文。插件只请求本机的 `127.0.0.1:11434`。

默认使用 `qwen2.5:1.5b`。在插件目录内可以创建 `translation.json` 更改配置：

```json
{
  "enabled": true,
  "model": "qwen2.5:1.5b",
  "target_language": "Simplified Chinese",
  "room_titles": true,
  "danmaku": true
}
```

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
