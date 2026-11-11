# V02.14 桌面验收（2026-10-22）

构建提交：`dbd1f71fcdd4bfe00095f955241fd4b9cfa5c5d2`。Windows 便携包在独立工作目录运行；没有安装 setup.exe、没有操作用户原安装。以下区分真实应用和 widget 回归。

| 项目 | 实际结果 |
|---|---|
| Windows 实际直播的滚轮、方向下键、底栏百分比 | 100% → 95% → 90%，底栏显示，没有画面中间的音量条 |
| Windows 滑块、静音、取消静音 | 拖到 43%，静音为 0%；暂停直播使控制栏保持显示，取消静音恢复 43% |
| 快速滚轮后改滑块再滚轮 | Widget 回归 95% → 40% → 35% 通过；真实快速组合尚未复查 |
| 持续按住 6 秒后释放 | Widget 验证持有期间底栏和百分比常显、释放后恢复隐藏；真实连续按住尚未复查 |
| 持有期间切换全屏、退出页面 | Widget 回归通过，没有遗留持有状态或异常；真实交互尚未复查 |
| Linux、macOS 首页启动 | 实际启动截图通过；Linux 为私有 Xvfb 会话，macOS 为 Apple 构建机 |
| Linux、macOS 音量操作 | 未进行；不能以 Windows 或 widget 结果代替 |
| 手机系统音量手势 | 本次没有改相应路径；没有实机复测 |

截图留在本地交付目录：`windows-home.png`、`windows-wheel.png`、`windows-keyboard.png`、`windows-slider.png`、`windows-muted.png`、`windows-unmuted.png`、`linux-home.png`、`apple-shots/macos.png`。没有上传测试数据截图到公共仓库。
