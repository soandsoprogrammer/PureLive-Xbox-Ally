# 插件与本地翻译

## 直播录制

播放 HTTP(S) 直播流时，在播放控制栏选择「录制」开始，用「停止录制」保存。只录直播源的音视频，不录弹幕或桌面；暂停观看不暂停录制。退出播放、刷新或切换播放源会停止旧流的录制。建议先手动停止，等界面提示保存完成再关闭应用。

需要 FFmpeg：把 `ffmpeg.exe` 放到应用同目录、加入 `PATH`，或通过 `PURELIVE_FFMPEG` 指定完整路径。默认保存到 `%LOCALAPPDATA%\PureLiveRust\recordings`，可以用 `PURELIVE_RECORDINGS_DIR` 改到其他目录（如 `D:\LiveRecordings`）。录制额外建立一个直播流连接，并直接封装成 MKV，不重新编码。

翻译默认关闭，不需要安装运行时就能正常使用播放器。开启步骤：

1. 安装并启动 Ollama，在 PowerShell 执行 `ollama pull qwen2.5:1.5b`。也可以配置其他已下载的本地模型。
2. 打开「设置 → 插件 → 本地翻译」，用鼠标或手柄切换，无需重启。
3. 如需更换模型、目标语言或翻译范围，编辑 `%LOCALAPPDATA%\PureLiveRust\translation.json`，再点「重新加载插件」。

```json
{
  "enabled": true,
  "model": "qwen2.5:1.5b",
  "target_language": "Simplified Chinese",
  "room_titles": true,
  "danmaku": true
}
```

直播间卡片优先显示译文，弹幕先显示原文，结果及时返回时再追加译文。弹幕高峰时队列满则略过翻译；模型未启动、超时或弹幕已离屏时保留原文。翻译请求只发给 `127.0.0.1:11434`，不经代理，也不会自动下载模型。首次推理可能比后续慢。

## 扩展接口

- `Plugin::register`：Rust 插件注册入口；不加载第三方 DLL 或运行脚本。
- `Registry::text` / `TextHook`：注册有顺序的后台文本处理链，可用于翻译、规范化或注释。返回 `None` 保留上一步结果，不改动平台数据。钩子必须尽快返回，不能暴露 UI 或播放器给工作线程。
- `Surface` / `Text`：区分标题、弹幕并携带平台和原文；后续可新增文本场景。平台来源、播放后端、输入和界面插槽是下一阶段独立的扩展点，目前还未迁移。

## 安装文本规则插件

在 `%LOCALAPPDATA%\PureLiveRust\plugins` 下新建一个 `.json`，再在设置中重新加载。可以用规则展开常见缩写或统一专名；它们先于翻译运行，移除文件后重新加载即可卸载。不需要重新编译，也不执行文件中的代码。无效文件会被跳过。

```json
{
  "version": 1,
  "kind": "text_rules",
  "platform": "twitch",
  "surfaces": ["room_title", "danmaku"],
  "rules": [{ "from": "GGWP", "to": "Good game, well played" }]
}
```

省略 `platform` 可匹配所有平台。文件按文件名排序，单个文件内按 `rules` 顺序执行；替换区分大小写。
