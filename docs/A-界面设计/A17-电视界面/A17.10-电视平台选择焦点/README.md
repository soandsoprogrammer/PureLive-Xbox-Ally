# A17.10 电视平台选择焦点

来源：issue [22](https://github.com/wzgrx/PureLive/issues/22)。选择依据：维护者本次“全面分析评估解决”与 D-003；沿用现有组件、图标和状态，小范围补齐，不扩大重构。

## 现状与根因

settings_editors.dart:183 的 PreferPlatformTile 绕过 AppOptionPresenter，直接打开手机 _PlatformPicker；其 TextField 和 SettingsChoiceRow 不组成电视选项导航。

## 预期行为

电视路径通过已有 AppOptionPresenter/showTvChoice 选择可见平台；当前项获焦，方向键到选项、确认保存，返回不改值；手机筛选和图标不变。

## 范围

- apps/pure_live/lib/features/settings/settings_editors.dart
- apps/pure_live/test/tv/

不改版本号、发布资产、两个更新 JSON、签名与正式安装数据。功能验证与物理设备验收分开记录。
