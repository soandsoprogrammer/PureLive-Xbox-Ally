# A11.7 宽屏设置独立页嵌入

## 范围与基线

沿用840断点及已有双栏容器，将IPTV、录制、本地互动、备份和日志放入右侧内容导航；窄屏根路由保留，切换窗口与返回链保持可用。

来源：https://github.com/wzgrx/PureLive/issues/56。按D-003沿用已确认的界面组件和操作，修复已有契约差异。先读AGENTS.md、docs/PROCESS.md、docs/specs/ENGINEERING.md、docs/specs/UI.md和相关既有任务；生产播放、平台请求、账号和迁移语义不改。

## 源码与允许修改

apps/pure_live/lib/features/settings；routes/app_router.dart；features/iptv/iptv_page.dart；features/record_settings；features/backup；features/live_play/local_interaction；packages/live_ui/lib/src/widgets/settings_page_frame.dart；test/features/settings。跨模块只改必要的页面构造、导航和应用内导出入口；共用组件保持默认行为兼容，测试只用生成数据。

## 验收

新增有意义的旧代码失败回归，保留首次失败与根因；定向测试、fatal-infos和完整all/14通过。测试定时器至少1秒，不访问真实平台。窗口大字、返回和旧入口回归按各任务具体场景覆盖。K90仅操作v4dev；原机和真实分享目标另留范围边界，真实日志、二维码与账号不得入仓库或发往外部应用。

## 初始登记快照

已登记，尚未修改本任务运行时代码；PR #55的原始提交保留在本地非快进合并中，另行审查和验证，当前不视作完成。


## 5.4.16 最终交付

宽屏五页嵌入内容导航；正式Windows隔离副本逐项验证及WebDAV返回、日志筛选宽窄变化和窄屏返回；完整all/14通过。

[发布与分层验证记录](../../../Y-发布和运营/Y03-发布说明和README/releases/v5.4.16.md)。此前候选阶段的待验状态由本节及最终回执更新。
