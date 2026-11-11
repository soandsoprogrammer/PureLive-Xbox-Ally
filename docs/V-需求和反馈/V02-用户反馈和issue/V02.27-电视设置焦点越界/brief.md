# V02.27 任务书

先读 AGENTS.md、docs/PROCESS.md、docs/specs/ENGINEERING.md；界面还读 docs/specs/UI.md。

## 要做

二级页共享 SettingsRow 仍在焦点时放大整行 2%，InkWell 底色无对应圆角；TvOptionRow 则使用边界外描边，被无侧向留白的滚动视口裁掉。一级 TvSettingsRow 已经不缩放。

二级设置沿用一级页整行不放大的行为；交互底色与焦点框共用圆角。整行 TvFocusable 的描边在自身边界内；卡片等可放大的目标保持既有规则。

## 范围

packages/live_ui/lib/src/widgets/settings_row.dart、packages/live_ui/test/settings_row_test.dart、apps/pure_live/lib/tv/widgets/、apps/pure_live/test/tv/，以及本任务文档和 docs/tasks.toml。

## 禁止

不修改发布版本或两个更新 JSON；不修改 PR #28 的弹幕功能；不碰原 Claude 数据、手机正式包、Windows 正式安装。不得提交真实凭据、账号、IP、原始鉴权响应或签名材料。

## 验收

960 逻辑画布和 720p/1080p/4K 下检查完整边框，方向键、确认和返回；Sony Android 9 实机仍需反馈者验收。

缺陷先记录旧代码失败回归，再通过相关测试；推送前完整门禁通过；只在独立任务分支提交。
