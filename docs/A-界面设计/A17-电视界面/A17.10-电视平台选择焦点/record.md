# A17.10 记录

2026-10-23，分支 ai/V02.21，基于 da1e678d7072807aa59a9de4f5e9f91f106cd7c3。

## 实现

PreferPlatformTile 发现 AppOptionPresenter 后改走已有电视选项框，当前项获焦；只显示未隐藏的平台，确认保存，Back 保留原值。手机继续使用原搜索列表。

## 回归

新增 1 条本任务回归，见 tv_preferred_platform_test.dart。改前失败日志：mute-tv-before.log；改后定向测试通过。日志保存在本机 outputs/purelive-issues-20261023-batch2；没有把编译失败或测试夹具错误算作缺陷证据。

合计新增 13 条：静音 2、电视首选平台 1、SC 3、iPad 手势 1、常亮恢复 3、取流诊断 3。选定回归含旧 #12/#14，结果与全量门禁分别保留。可选 Widget 截图使用合成数据，不是真机视频或验收。

## 停在哪

实现与定向回归完成，未发布；真机步骤见 verify.md。推送前必须运行完整门禁，提交后 Apple 原生编译和模拟器启动结果附在 PR 与本机回执；此记录不预先声称通过。未操作正式安装、原始 Claude 目录或用户账号。


## 5.4.9 发布

PR #27 合并 37a5f703901022cd7fcb88c0907cd3c84cd4ea68，实际构建与标签提交 a0fad683c0562e5856f0eddeec7f2df2efd030b9，随 [5.4.9](https://github.com/wzgrx/PureLive/releases/tag/v5.4.9) 发布。完整门禁、十包哈希及各端启动核验通过，详见 Y01.20；反馈者 iPad、Sony 电视、真实付费 SC 和各端完整交互未全部覆盖，保留待真机，不据此宣称所有硬件验收。
