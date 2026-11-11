# A07.26 记录

2026-10-23，分支 ai/V02.21，基于 da1e678d7072807aa59a9de4f5e9f91f106cd7c3。

## 实现

全屏和电视增加活动 SC 入口与默认开启的 showFullscreenSuperChat 设置。复用 RoomSuperChatPanel/SuperChatList 和现有最多 500 条会话历史；过期隐藏入口，已打开的历史仍可查看。电视面板由页面管理返回与焦点，上下滚动不换台。

## 回归

新增 3 条本任务回归，见 live_play_room_test.dart、tv_test.dart。改前失败日志：sc-ipad-before.log、tv-sc-before.log；改后定向测试通过。日志保存在本机 outputs/purelive-issues-20261023-batch2；没有把编译失败或测试夹具错误算作缺陷证据。

合计新增 13 条：静音 2、电视首选平台 1、SC 3、iPad 手势 1、常亮恢复 3、取流诊断 3。选定回归含旧 #12/#14，结果与全量门禁分别保留。可选 Widget 截图使用合成数据，不是真机视频或验收。

## 停在哪

实现与定向回归完成，未发布；真机步骤见 verify.md。推送前必须运行完整门禁，提交后 Apple 原生编译和模拟器启动结果附在 PR 与本机回执；此记录不预先声称通过。未操作正式安装、原始 Claude 目录或用户账号。


2026-10-23 补充自查：扩展同一电视回归用例，原候选版无法用方向键聚焦历史开关（tv-history-before.log 失败）。改用已有 TvButton 作为同一 SuperChatList 的开关，仅定制输入组件；列表顶部按上或左右键到历史开关，OK 切换，按下回到滚动，Back 仍先关面板；tv-history-after.log 通过。未扩大历史保留范围。首轮完整门禁主动停止以纳入此修正，最终同提交门禁另跑，不能引用首轮为通过。


电视列表文字按 TvScale 的 960×540 画布缩放，历史按钮保留 TV 自身缩放，避免小屏叠乘；Widget 复核见 verify/tv-super-chat-panel.png。完整门禁第二轮发现两个位置布尔参数 lint，改为命名参数；受影响三成员静态检查已通过，最终门禁另跑。


完整门禁第三轮仅 packages/live_store test 失败：新增 showFullscreenSuperChat 未登记到 newInV4 默认值表。按既有基线规则登记默认 true，保留完整键集校验，不删除或放宽断言。设置默认值和备份测试已通过；最终完整门禁另跑。


4K 扩展回归：只缩放文字会使标题固有高度 102 超过固定 52 的标题栏（tv-4k-before.log 失败）。改为将同一 RoomSuperChatPanel 的完整画布连同标题、按钮和点击区域统一缩放，复用列表与历史状态；4K、720p 的标题尺寸及遥控历史/返回回归通过（tv-scale-visual-final.log）。补充检查期间未推送，最终完整门禁按合并后的修正另跑。


## 5.4.9 发布

PR #27 合并 37a5f703901022cd7fcb88c0907cd3c84cd4ea68，实际构建与标签提交 a0fad683c0562e5856f0eddeec7f2df2efd030b9，随 [5.4.9](https://github.com/wzgrx/PureLive/releases/tag/v5.4.9) 发布。完整门禁、十包哈希及各端启动核验通过，详见 Y01.20；反馈者 iPad、Sony 电视、真实付费 SC 和各端完整交互未全部覆盖，保留待真机，不据此宣称所有硬件验收。
