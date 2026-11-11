# D01.34 记录

## 做了什么

- `packages/live_danmaku/lib/src/sites/douyu.dart`：`_vip` 改为 `_online`，`oni` 的 `vn` 报成 `LiveMessageType.online` + `LiveAudienceUpdate(kind: onlineViewers)`，不再生成“贵宾”聊天行；非数字不报。
- `packages/live_danmaku/test/douyu_test.dart`：协议用例改为断言在线数；S13 录制期望里的 6 条“贵宾”聊天行按新行为变换；S14“其他包”用例的期望同步；`_project` 把 `LiveAudienceUpdate` 展开成 `{kind, value}` 便于对照。
- `apps/pure_live/lib/shared/rooms/room_texts.dart`：`AudienceFigure` 增加可选的 `label`；斗鱼的在线位覆盖为“贵宾”（`audience_nobles`），其他平台仍是“在线”。观众栏、详情页和电视浮层都读这个标签。
- `apps/pure_live/assets/translations/`：15 个文件加 `audience_nobles`（zh“贵宾”，en“VIPs”，其余本地化）。
- `apps/pure_live/test/features/live_play/live_play_controller_test.dart`：用斗鱼房间断言 `audienceFigures` 的标签是“贵宾”，聊天列表保留同名真人聊天。

## 结果

- GitHub Actions（`LuomingXu/PureLive` 的 Test）：
  - 定向步骤通过——`packages/live_danmaku` 的 `dart format`、`dart analyze --fatal-infos`、`dart test test/douyu_test.dart`。
  - squash 后的分支完整门禁 run 40692909762 通过。
  - 同步上游 5.4.19 后的提交完整门禁 run 40696443904 通过（18m27s），含全部成员测试、docs 和 owners。
  - 标签改动后的提交完整门禁 run 40709061182 通过（18m33s），含 `apps/pure_live` 的全部测试。
- 最初的任务代码、测试和文档合成一个提交；CI 工作流和 CI 定向测试是两个单独的提交，之后同步上游和“贵宾”标签的改动是追加提交。
- 真机未看：要在 K90 上进一个斗鱼直播间，确认聊天列表没有“贵宾”行、观众栏出现“贵宾 N”。

## 同步上游 5.4.19（2026-10-28）

上游 5.4.19（V02.60）为 issue #79 加了“显示斗鱼贵宾人数通知”开关
`danmakuShowVipCount`（默认关）：`oni` 仍报“贵宾”聊天行，带
`data: 'douyu-vip-count'` 标记，直播间和多画面按开关过滤；设置页、
设置目录、15 个翻译文件和 OWNERS 都加了条目。

同步后保留本任务的做法，并移除已被取代的部分：

- 不再保留 `douyu-vip-count` 标记和两个控制器的过滤行（`oni` 已不产生聊天行）；
- 删除 `danmakuShowVipCount` 设置、设置页开关、搜索目录条目、
  `settings_defaults_test` 的默认值和 15 个翻译文件里的 `danmaku_show_vip_count`；
- 重写上游的 #79 App 测试：贵宾数出现在 `audienceFigures`，聊天列表仍保留同名真人聊天；
- `docs/inventory/OWNERS.md` 重新生成（设置 290 → 289）；
- 上游已占 D-068（自动换台）、D-069（5.4.19 发布），本任务的决策改为 D-070。

## 停在哪

代码、测试和文档已完成，CI 的代码检查全过；尚未合并到 master（分支 `ci/D01.34-test`），也未真机。下一步：维护者合并分支后在 K90 验证。


## 2026-10-29整合审查

保留贡献者9deb479原提交，整合最新主分支。原做法把VIP当真实在线数，即使房间内覆盖标签，卡片和排行仍会误读；三种热度条件反证失败。改为独立LiveVipCount和控制器会话字段，统一三处显示，零值及换房/关播清理回归通过。此前CI描述属于贡献者记录，最终门禁和原生证据以Y01.32本次记录为准。


发布前补充迟到事件反证：关播清空人数后，尚在队列中的oni会把旧人数重新填回；三种热度条件均复现222。接收VIP前复用弹幕阶段条件并检查仍在直播，修正后三项通过。原候选完整门禁在构建前停止并保留，更新源码后重新完整验证，未构建或发布旧候选。


2026-10-29已随5.4.21发布，最终包证据及原设备验收边界见Y01.32/verify.md。
