# A15.3 任务书

## 背景

[issue #70](https://github.com/wzgrx/PureLive/issues/70) 报告电视在线更新背景与设置页不同，存在手机返回按钮。当前更新信息一致性已经由 Y02.2 合并，本任务只修复电视外壳与相应交互。

## 先读

`AGENTS.md`、`docs/PROCESS.md`、`docs/specs/ENGINEERING.md`、`docs/specs/UI.md`，本任务 README，以及 A15.2 的设计与记录。

代码：`apps/pure_live/lib/routes/tv_router.dart`、`apps/pure_live/lib/features/version/version_page.dart`、`apps/pure_live/lib/features/version/release_history_view.dart`、`apps/pure_live/lib/tv/settings/tv_settings_section_page.dart`。

## 目标和阶段

1. 复用电视设置外壳与共享页头，保留普通模式外观、文案和行为。
2. 用真实路由与离线服务测试更新成功、加载、错误重试、刷新、历史详情、下载确认与返回。纯方向键到达操作，焦点可见；覆盖对话框不被后台完成抢焦点。
3. 完成相关测试、静态分析和完整门禁；记录原机限制，不提前标为完成。

## 范围

可改电视路由、版本页面及其必要的共享显示组件与定向测试；只有明确复现的布局/焦点问题才扩展组件改动。不修改更新比较、下载协议、版本号、更新 feed、签名、设置键、其他页面或共享电视焦点算法。

## 验证

先在原代码运行失败的定向回归，再验证候选。至少覆盖 960×540、较窄视口和放大字体；普通手机与宽屏回归保留。测试只用离线替身，定时器不少于 1 秒。推送前执行 `bash tools/gate/gate.sh --all`，必须有完整终态。

## 提交

分支 `ai/A15.3`，提交信息以 `[A15.3]` 开头；不推 master。新包和原 Sony 设备验收见 verify.md。
