# W01.4 任务书

先读 AGENTS.md、docs/PROCESS.md 第 5、8、14 节、docs/specs/ENGINEERING.md 与 UI.md、本目录 README.md。

## 背景与验收

来源：issue [21](https://github.com/wzgrx/PureLive/issues/21)、[22](https://github.com/wzgrx/PureLive/issues/22)、[23](https://github.com/wzgrx/PureLive/issues/23)、[24](https://github.com/wzgrx/PureLive/issues/24)、[25](https://github.com/wzgrx/PureLive/issues/25)。

已刷新 pure_live upstream/master、pure_live_TV origin/main、media_core origin/main，使用独立参考副本，不修改原始 Claude 工作区。

记录本次参考提交与相关行为；沿用本仓库 Riverpod 和原生通道，不照搬 GetX 架构；Apple 系统 API 以官方文档为准。

## 可改范围

- docs/W-上游借鉴/W01-定期对照/

## 阶段与测试

1. 保存改动前失败的定向回归结果。
2. 复用已有状态和弹层；新增文字进入翻译，设置键只加不改。
3. 定向回归、受影响成员静态检查、推送前完整门禁；同一时间一个本地重任务。
4. 写逐端真机步骤；不能验证的停在待真机，不据模拟器推定真机通过。分支 ai/V02.21，不推 master，不改版本与更新文件。
