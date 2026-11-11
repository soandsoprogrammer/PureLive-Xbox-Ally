# V02.49 桌面设置导航一致性

## 范围与基线

现有设置宽屏契约要求内容留在右侧，五项独立路由提前跳出主导航，按A11.7补齐并覆盖窄屏、回退与窗口变化。

来源：https://github.com/wzgrx/PureLive/issues/56。按D-003沿用已确认的界面组件和操作，修复已有契约差异。先读AGENTS.md、docs/PROCESS.md、docs/specs/ENGINEERING.md、docs/specs/UI.md和相关既有任务；生产播放、平台请求、账号和迁移语义不改。

## 源码与允许修改

apps/pure_live/lib/features/settings；routes/app_router.dart；features/iptv/iptv_page.dart；features/record_settings；features/backup；features/live_play/local_interaction；packages/live_ui/lib/src/widgets/settings_page_frame.dart；test/features/settings。跨模块只改必要的页面构造、导航和应用内导出入口；共用组件保持默认行为兼容，测试只用生成数据。

## 验收

新增有意义的旧代码失败回归，保留首次失败与根因；定向测试、fatal-infos和完整all/14通过。测试定时器至少1秒，不访问真实平台。窗口大字、返回和旧入口回归按各任务具体场景覆盖。K90仅操作v4dev；原机和真实分享目标另留范围边界，真实日志、二维码与账号不得入仓库或发往外部应用。

## 初始登记快照

已登记，尚未修改本任务运行时代码；PR #55的原始提交保留在本地非快进合并中，另行审查和验证，当前不视作完成。


## 5.4.16 候选进展

#56按原840双栏契约补齐五个独立设置入口，手机窄屏仍走原根路由；宽窄切换、初始路由参数和备份WebDAV子页回退有回归。

当前定向回归共21项通过；原生截图、安装包哈希和真实服务器/原机验证不由此替代，发布前继续按清单核对。


## 5.4.16 最终交付

#56五个独立设置页已统一宽屏导航，Windows正式包隔离交互及共享回归通过，5.4.16发布并回复关闭。

[发布与分层验证记录](../../../Y-发布和运营/Y03-发布说明和README/releases/v5.4.16.md)。此前候选阶段的待验状态由本节及最终回执更新。
