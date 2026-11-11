# E03.21 任务书

先读 AGENTS.md、docs/PROCESS.md、docs/specs/ENGINEERING.md；界面还读 docs/specs/UI.md。

## 要做

Kick API、播放与弹幕已有实现，但 bootstrap 以 AndroidNativeHttp 的可用性间接控制 HTTP2 客户端的创建，Windows 因此没有平台入口。

核对 HTTP2 客户端及代理在 Windows 的实际能力，先验证列表、搜索、房间、媒体字节、播放、弹幕和恢复，再决定是否开放 Windows；不单靠移除条件声明支持。官方文档 https://docs.kick.com/ 只作公开接口能力参考，不假定其中包含匿名网页取流。

## 范围

apps/pure_live/lib/app/bootstrap.dart、应用初始化测试、packages/live_net/ 和相关测试（如确有传输缺陷）、tools/live_cli 的 Kick 工厂和巡检目标及其回归，以及本任务文档和 docs/tasks.toml。

## 禁止

不修改发布版本或两个更新 JSON；不修改 PR #28 的弹幕功能；不碰原 Claude 数据、手机正式包、Windows 正式安装。不得提交真实凭据、账号、IP、原始鉴权响应或签名材料。

## 验收

实际 Windows 隔离实例验证；不操作 D:\Soft 下正式安装，不使用账号或付费能力。无法验证的保持开放并记录具体限制。

缺陷先记录旧代码失败回归，再通过相关测试；推送前完整门禁通过；只在独立任务分支提交。
