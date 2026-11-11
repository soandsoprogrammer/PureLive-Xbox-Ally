# V02.21 任务书

先读 AGENTS.md、docs/PROCESS.md 第 5、8、14 节、docs/specs/ENGINEERING.md 与 UI.md、本目录 README.md。

## 背景与验收

来源：issue [21](https://github.com/wzgrx/PureLive/issues/21)。

现有 MultiviewController.toggleMuteAll 已保留声音焦点与各格音量；multiview_page.dart:382 只处理 Esc，:788 的无工具栏布局只保留退出键。

沿用现有全局静音状态；两个无工具栏模式增加 48×48 静音按钮，按 M 切换，输入框、弹层和系统组合键不拦截；恢复声音不重建会话。

## 可改范围

- apps/pure_live/lib/features/multiview/
- apps/pure_live/test/features/multiview/

## 阶段与测试

1. 保存改动前失败的定向回归结果。
2. 复用已有状态和弹层；新增文字进入翻译，设置键只加不改。
3. 定向回归、受影响成员静态检查、推送前完整门禁；同一时间一个本地重任务。
4. 写逐端真机步骤；不能验证的停在待真机，不据模拟器推定真机通过。分支 ai/V02.21，不推 master，不改版本与更新文件。
