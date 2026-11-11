# A12.8 电视备份文件操作：任务书

## 目标

修复 [issue #71](https://github.com/wzgrx/PureLive/issues/71)：电视备份文件只能恢复，遥控器无法到达更多按钮，也不能以菜单键或长按确认打开删除等操作。

1. 方向键到达文件主体和更多按钮；短确认仍预览，菜单键和长确认进入原菜单。
2. 长确认重复和释放不能误触恢复；取消及操作结束后恢复可用焦点。
3. 删除最后一行、文件读取/删除失败、禁用及繁忙状态可继续用遥控器操作。
4. 保留手机与鼠标操作，不扩大到 WebDAV、通用设置行或全局导航。

## 先读及范围

读 `AGENTS.md`、`docs/PROCESS.md`、`docs/specs/ENGINEERING.md`、`docs/specs/UI.md`，以及 A12.4 的说明和记录。根因与交互约定见 [README.md](README.md)。

代码范围：`apps/pure_live/lib/features/backup/backup_page.dart`，相应的 `apps/pure_live/test/features/backup/backup_page_test.dart`。文档范围：本任务和登记表及生成索引。不得修改版本号、发布通道、备份格式、用户设置键及签名。

## 验收

`backup_page_test.dart` 增加以方向键、确认键、菜单键、按下/重复/释放序列和系统返回驱动的回归，不能仅靠点击或指针长按模拟遥控器。用例在修复前应在遥控可达性或菜单断言失败，且能使用基线已有接口编译。

保留原来的手机纵横屏、宽屏和文件菜单回归。执行格式检查、应用静态分析、相关测试、文档检查及完整门禁。未运行的项目明确列为未验证，不标记完成。设备验证按 [verify.md](verify.md)。
