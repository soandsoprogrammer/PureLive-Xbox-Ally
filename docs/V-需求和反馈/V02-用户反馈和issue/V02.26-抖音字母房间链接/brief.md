# V02.26 任务书

先读 AGENTS.md、docs/PROCESS.md、docs/specs/ENGINEERING.md；界面还读 docs/specs/UI.md。

## 要做

DouyinSite.roomIdFromUrl 对 live.douyin.com 只接受数字，与反馈中的自定义字母房间地址不符。

仅为直播子域接受有限长度的字母、数字、下划线、点和短横线；保留系统路径、路径穿越、错误主机和非直播抖音 URL 的拒绝规则。数字链接、短链和无协议粘贴一起回归。

## 范围

packages/live_core/lib/src/sites/douyin/、packages/live_core/test/sites/douyin_site_test.dart，以及本任务文档和 docs/tasks.toml。

## 禁止

不修改发布版本或两个更新 JSON；不修改 PR #28 的弹幕功能；不碰原 Claude 数据、手机正式包、Windows 正式安装。不得提交真实凭据、账号、IP、原始鉴权响应或签名材料。

## 验收

反馈中的真实地址做只读检查；解析成功与房间当前是否在播分开记录。

缺陷先记录旧代码失败回归，再通过相关测试；推送前完整门禁通过；只在独立任务分支提交。
