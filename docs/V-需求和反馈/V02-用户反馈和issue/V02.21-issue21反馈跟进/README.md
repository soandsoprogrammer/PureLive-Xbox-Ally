# V02.21 issue21反馈跟进

来源：issue [21](https://github.com/wzgrx/PureLive/issues/21)。选择依据：维护者本次“全面分析评估解决”与 D-003；沿用现有组件、图标和状态，小范围补齐，不扩大重构。

## 现状与根因

现有 MultiviewController.toggleMuteAll 已保留声音焦点与各格音量；multiview_page.dart:382 只处理 Esc，:788 的无工具栏布局只保留退出键。

## 预期行为

沿用现有全局静音状态；两个无工具栏模式增加 48×48 静音按钮，按 M 切换，输入框、弹层和系统组合键不拦截；恢复声音不重建会话。

## 范围

- apps/pure_live/lib/features/multiview/
- apps/pure_live/test/features/multiview/

不改版本号、发布资产、两个更新 JSON、签名与正式安装数据。功能验证与物理设备验收分开记录。
