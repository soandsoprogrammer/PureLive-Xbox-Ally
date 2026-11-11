# V02.29 任务书

先读 AGENTS.md、docs/PROCESS.md、docs/specs/ENGINEERING.md；界面还读 docs/specs/UI.md。

## 要做

2026-10-24 03:28 的 5.4.9 现场日志首次明确 phase=qualities kind=ApiChanged；同进程成功一段时间后也会复发。该阶段包含续期、签名描述符和元数据请求，尚不能直接推定具体字段。

对照最新上游与实际匿名响应，审查描述符缓存、账号身份和错误分类；只有证实根因才修改鉴权。必要时补充枚举化子阶段和固定原因码，不导出响应、Cookie、签名材料、账号或原始异常。

## 范围

packages/live_core/lib/src/sites/douyu/、对应离线测试、apps/pure_live/lib/features/live_play/logic/、相关诊断测试，以及本任务文档和 docs/tasks.toml。

## 禁止

不修改发布版本或两个更新 JSON；不修改 PR #28 的弹幕功能；不碰原 Claude 数据、手机正式包、Windows 正式安装。不得提交真实凭据、账号、IP、原始鉴权响应或签名材料。

## 验收

离线可复现的缺陷必须有改前失败回归；单一正常账号与匿名巡检均不能证明现场账号问题解决。

缺陷先记录旧代码失败回归，再通过相关测试；推送前完整门禁通过；只在独立任务分支提交。
