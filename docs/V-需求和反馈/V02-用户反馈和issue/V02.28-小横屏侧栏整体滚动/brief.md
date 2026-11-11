# V02.28 任务书

先读 AGENTS.md、docs/PROCESS.md、docs/specs/ENGINEERING.md；界面还读 docs/specs/UI.md。

## 要做

侧栏在部分高度把目的地固定在下方，只让上方很小的工具区滚动；下方导航项没有滚动祖先。旧测试用 ensureVisible 编程滚动上方工具，没有覆盖用户在下方拖动。

恢复 3.x 单一侧栏滚动容器，保留全部入口、顺序、选中态和点击行为；手势从整个侧栏发起都能滚动。用实际拖动、点击和缩放测试可达性。

## 范围

apps/pure_live/lib/features/home/home_views.dart、apps/pure_live/test/features/home/home_test.dart，以及本任务文档和 docs/tasks.toml。

## 禁止

不修改发布版本或两个更新 JSON；不修改 PR #28 的弹幕功能；不碰原 Claude 数据、手机正式包、Windows 正式安装。不得提交真实凭据、账号、IP、原始鉴权响应或签名材料。

## 验收

小横屏、安全区和大字体下逐个访问菜单、搜索、记录、链接、多画面和四个目的地；不把 TV 触屏补充当作本项证据。

缺陷先记录旧代码失败回归，再通过相关测试；推送前完整门禁通过；只在独立任务分支提交。
