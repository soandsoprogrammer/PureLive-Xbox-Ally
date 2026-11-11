# V02.22 任务书

先读 AGENTS.md、docs/PROCESS.md 第 5、8、14 节、docs/specs/ENGINEERING.md 与 UI.md、本目录 README.md。

## 背景与验收

来源：issue [22](https://github.com/wzgrx/PureLive/issues/22)。

settings_editors.dart:183 的 PreferPlatformTile 绕过 AppOptionPresenter，直接打开手机 _PlatformPicker；其 TextField 和 SettingsChoiceRow 不组成电视选项导航。

电视路径通过已有 AppOptionPresenter/showTvChoice 选择可见平台；当前项获焦，方向键到选项、确认保存，返回不改值；手机筛选和图标不变。

## 可改范围

- apps/pure_live/lib/features/settings/settings_editors.dart
- apps/pure_live/test/tv/

## 阶段与测试

1. 保存改动前失败的定向回归结果。
2. 复用已有状态和弹层；新增文字进入翻译，设置键只加不改。
3. 定向回归、受影响成员静态检查、推送前完整门禁；同一时间一个本地重任务。
4. 写逐端真机步骤；不能验证的停在待真机，不据模拟器推定真机通过。分支 ai/V02.21，不推 master，不改版本与更新文件。
