# L01.4 记录

- 日期：2026-10-27；分支：`ai/L01.4`。
- 工具链：Flutter 3.47.8、Dart 3.13.7（按 `toolchain.env`）；依赖锁文件未变。

## 根因与修复

`IptvSite.hotRooms` 原本是内置列表的唯一首次下载入口，管理页只读数据库，因此新装直接进设置看不到列表。管理页现与热门共用 `loadHotPlaylist`，保留已有单次下载合并，并使用真实导入结果显示加载、失败与重试。

继续使用 `Settings.iptvHotRemoved`，不新增设置键。下载前捕获内置行快照，提交前核对实时删除标记及数据库快照；设置初始化还在捕获快照时确认列表确实缺失，防止过时界面覆盖已写入的较新行。用户显式恢复加入旧下载时，旧结果失效后仅在列表仍缺失且未再次删除的条件下补发一次下载；已有新行不覆盖，页面离开后也不访问失效的界面引用。热门入口仍能重新填充已有但频道为空的内置列表。

三个新增状态文案同步所有语言文件，保持键名一致；默认节目单、自定义源、版本和发布信息未改。

## 验证结果

测试均使用假 HTTP 与隔离数据库，不访问真实平台。较新内置行的保护用例模拟独立存储快照写入，不代表完整备份文件导入；当前备份格式排除内置热门行，备份中的删除设置与自定义列表仍按既有规则处理。

| 验证 | 结果 |
|---|---|
| 修改前实现：新增包级回归 | 5 项运行，2 通过、3 断言失败；覆盖删除标记、晚下载复活和覆盖较新存储快照 |
| 修改前实现：新增页面回归 | 14 项运行，3 通过、11 失败；新装手机/桌面/电视样式均重现列表为空；独立快照写入用例以最终直接存储写入夹具另行复验，旧实现仍失败 |
| 修改后新增回归 | 包 5/5、页面 14/14 通过 |
| `live_iptv` 全包测试 | 52/52 通过 |
| IPTV、翻译、电视界面与设置嵌入页相关测试 | 93/93 通过 |
| `live_iptv`、`pure_live` 静态分析 | `dart analyze --fatal-infos` 均无问题 |
| 变动 Dart 文件格式、`git diff --check` | 通过 |
| 独立代码与验证证据审查 | 通过；最终候选完整门禁仍待执行 |
| 最终候选完整门禁、打包与原机验收 | 待完成，不计为通过 |

主要复现和复验命令（在仓库根目录执行）：

```sh
(cd packages/live_iptv && dart test test/import_test.dart --plain-name L01.4 -r expanded)
(cd apps/pure_live && flutter test --no-pub test/features/iptv/iptv_page_test.dart --plain-name L01.4 -r expanded)
(cd packages/live_iptv && dart test -r expanded)
(cd apps/pure_live && flutter test --no-pub test/features/iptv test/i18n_test.dart test/tv/tv_test.dart test/features/settings/standalone_pane_test.dart -r expanded)
(cd packages/live_iptv && dart analyze --fatal-infos)
(cd apps/pure_live && dart analyze --fatal-infos)
```

## 停在哪

代码和上述回归已通过，待最终合并候选运行 `bash tools/gate/gate.sh --all`。真实下载服务可用性、手机/电视/Windows 原机入口与遥控器操作仍按 [verify.md](verify.md) 核验。未发布更新，未关闭 issue #72；widget 测试不能替代原机验收。

## 2026-10-27 合并与完整门禁

[PR #77](https://github.com/wzgrx/PureLive/pull/77) 已合并，合并提交 `c2626085805d9e8a8c6a2c75235e46e280298369`。最终候选 tree `bbc7c91959a1a2d54e603f48ee4447d3214df00e` 的 `bash tools/gate/gate.sh --all` 退出码为 0，日志终态为 `gate: passed (all, 14 members)`；合并后的 tree 与该候选一致。首次失败记录保留，最终通过不覆盖或改写失败历史。

该结果包含完整自动化门禁，不等同于发布或原设备验收。尚未发布含本次修复的安装包，5.4.18 不包含这些改动；各任务的原设备验证边界保持不变。
