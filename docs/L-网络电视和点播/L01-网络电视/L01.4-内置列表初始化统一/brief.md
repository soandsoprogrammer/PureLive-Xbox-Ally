# L01.4 任务书

## 先读与范围

先读 `AGENTS.md`、`docs/PROCESS.md` 第 5、8、14 节、`docs/specs/ENGINEERING.md`、`docs/specs/UI.md`、本目录 README，以及 `packages/live_iptv/lib/src/importer.dart`、`iptv_site.dart`、`apps/pure_live/lib/features/iptv/iptv_page.dart`、`iptv_data.dart`、对应导入和管理页测试。

可修改上述内置导入入口、管理页小范围初始化状态、必要翻译与测试；不得修改版本、更新通道、签名、3.x 设置键、自定义列表、默认节目单流程或恢复预算。

## 验收

1. 新装直接进入设置能加载内置列表，无需先访问热门；原热门路径仍正常。
2. 设置与热门并发初始化只发出一次下载，不重复保存。
3. 离线失败有明确状态和可重试入口；失败不写成永久完成。
4. 用户删除后重进、刷新、重启不自动复活；显式恢复正常。
5. 下载期间删除或恢复新快照，旧结果不得重新插入或覆盖新数据。
6. 已有自定义列表、已有/恢复的内置列表以及默认节目单行为保留。
7. 页面离开后不访问失效的 ref、不 setState；用户看到的新增文字在各语言中保持键名一致、按键名排序。

## 验证与提交

先写修改前失败的回归，使用假 HTTP、可控 Future、隔离数据库；新增计时不小于一秒。先跑 live_iptv 及管理页相关测试，再跑 app 全量与 `bash tools/gate/gate.sh --all`。不把widget 测试当作手机/电视/Windows 原机验收。

分支 `ai/L01.4`，提交信息以 `[L01.4]` 开头；不推 master、不强推。完整门禁、独立审查和最终候选验证通过前不合并或发布。停下时更新记录与登记表并运行 docs.py。
