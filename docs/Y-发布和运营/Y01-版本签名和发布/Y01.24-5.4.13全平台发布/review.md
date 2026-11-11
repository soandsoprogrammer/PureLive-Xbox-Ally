# Y01.24 5.4.13 全平台发布（构建号 5117）：电视遥控导航和设置焦点

来源：[issue #37](https://github.com/wzgrx/PureLive/issues/37)、[issue #38](https://github.com/wzgrx/PureLive/issues/38)、[issue #39](https://github.com/wzgrx/PureLive/issues/39)。从 5.4.12 完整收尾的主分支开始；计划在同一提交构建 5.4.13+5117。

## 清点与方案

- 升级弹窗：复用现有 NewVersionDialog，保留项目链接、说明、跳过、其他下载方式、取消和下载按钮。电视方向导航下，说明区不再把焦点交给没有焦点外观的文本选择区域；长说明必须能遥控滚动、显示焦点、并在边界离开到操作键。手机触摸选择、桌面 Enter/Esc 和点击链接保持。
- 设置：TvSettingsGroup 外围 4 个画布像素内边距与内侧描边叠加，和共享 SettingsGroup 的无内边距边界不同。统一电视整行底色与分组边界及圆角；维持整行不放大、描边在视口内，保留原 #30 的防裁切回归。
- 壁纸：使用真实公开 JSON API、缩略图、原图分步只读取样，不照搬上游依赖扩展身份的 iTab 接口，不增加盲目重试或全局超时。当前 curl 和同一 IoLiveHttp 在本机均取得 24 条 JSON、缩略图和原图片段；原电视超时尚未复现，不能据本机通过而关闭 #38。
- 原电视、华为播放和受影响斗鱼账号证据分开；#33 的缓冲超时只证明未取得可播放数据，不能确定是解码器或签名故障。

按 D-003 选择最小修正，沿用既有入口、组件、设置和数据。正式包、用户数据与账号不操作。原始反馈的三张设置照片留在任务外部输出，定向合成图与真实设备图分开记录。

## 验收

| 项目 | 要求 |
|---|---|
| 升级短说明 | 遥控从项目链接能到达跳过、取消、其他下载方式和下载按钮 |
| 升级长说明 | 焦点可见、上下滚动，到边界能离开；OK 不误触下载 |
| 无包与窄屏 | 更新跳转、跳过持久化、Back/Esc 取消和桌面 Enter 保持 |
| 设置边框 | 一级、背景子页、共享子页和平台排序的内外边界一致，720p/1080p/4K 不裁切 |
| 壁纸 | 记录真实 API/图片结果和故障回归；无法复现时如实保留开放 |
| 发布 | 改前失败回归、完整 14 成员门禁、十包同源与十一项哈希、K90 v4dev 和各端启动图 |

本节是开工方案。回归、根因、截图、构建与发布结果随后分别补齐，不提前标完成。


## 本轮实现与验证

生产代码只改 update_prompt.dart、tv_settings_rows.dart 和 live_ui 的 settings_row.dart，另按发布要求同步版本号。#37 根因是 MarkdownText 的 SelectionArea 取得方向键焦点但没有可见边框，裸方向键被用于选择／滚动而不能进入底部操作。电视方向模式现在由可见的说明区接住焦点，分段滚动，到边界让出方向导航，屏蔽说明区的 OK 安装；桌面和手机仍保留文本选择、Enter/Esc 与触摸。

#39 根因是 TvSettingsGroup 的 4 个画布像素内边距与 5.4.10 起的内侧描边叠加，共享 SettingsGroup 没有这圈内边距；外围与行圆角也不一致。移除电视分组内边距并使用与行一致的圆角，共享分组仅在 TV 模式使用行圆角；不改变卡片放大、手机分组或 #30 内侧描边。

修改前生产文件与 a187316fa 完全一致。有效 RED：长／短说明连续 Down 仍不能到达操作键；三个尺寸电视分组边缘是底色而非焦点框；共享行对照本来通过。首次过严的共享颜色断言误将既有两种近白色要求完全相同，已排除，不作为缺陷。修正后两项遥控回归与六项分组像素回归通过，反向离开、长说明滚动、OK 不误装、跳过持久化与相邻操作键也通过，合成图运行通过。原 #30 防裁切及全部既有升级／下载测试将在全量门禁覆盖。

Wallhaven 本轮只读请求成功，API 24 行、缩略图与原图各读取 1024 字节，未使用账号、没有写请求；这不能证明 Sony 端已经恢复。#38 维持开放。华为新日志只缩小到等待音视频数据超时，未据此盲改解码器，#33 继续开放；#15 无新的受影响账号原因码，继续开放。

同提交正常 profile 用于 K90 冒烟；另计划用同提交、相同包名和构建号、仅显示较旧版本号的 profile 触发真实公开升级弹窗，验证后装回正常 5.4.13 profile。此辅助包不公开，不改更新通道，不清除用户数据；变体与正式包证据单独记录。完整门禁和构建、原生验证尚待完成。


## #38 后续截图与重试子问题

开工后收到原报告者的新截图及“重试失焦”的补充：截图实际分类为 connect 连接失败，并非 timeout；图片是列表请求失败阶段，尚未到缩略图加载。原网络故障仍未复现，本机成功不能作为关闭依据。

暂停本轮未完成门禁和待构建进程后补充回归。修改前 tv_wallpaper_pages.dart 与 a187316fa 一致，方向键保留单个重试按钮焦点的断言本来通过；实际失败是按 OK 已发起第二次请求，旧错误页却仍显示，不能把此结果写成已复现所有遥控器失焦。修正只是在请求开始清除旧错误，使失败页变为加载；原 loading 互斥、失败按钮 autofocus 和页码逻辑保留，不改网络栈、超时、重试次数或焦点策略。

受控请求回归现在通过：首次连接失败、四方向键、OK 发起请求、加载替换旧错误、重复 OK 不排队、再次失败后重试焦点恢复、成功空列表。原 Sony 网络与失焦主诉仍待设备核验，#38 保持开放。首次测试花括号的静态错误及为新证据暂停的门禁日志均已保留；本次最终源码将重新运行完整门禁，未将停止的轮次算作通过。


## 共享分组既有回归适配

完整门禁的产品与应用测试通过，但 live_ui 既有“电视分组不裁切”测试以旧圆角常量作为容器查找条件，电视分组圆角对齐后无法找到目标。未删除或放宽防裁切检查：改为直接定位 SettingsGroup 内的外层 Material，同时断言手机仍为 AppRadii.card／Clip.antiAlias，电视为 AppRadii.listRow／Clip.none。该文件全部 24 项回归与静态检查通过。原完整失败日志保留，不计作全量门禁通过；最终源码随后重新冻结跑完整 all/14。


## 新到 #15 原因码与范围补充

新反馈在 5.4.12 首次提供 qualities / ApiChanged / douyuDescriptorRounds，随后同房间能播放且缓存一段时间后恢复失败。该原因码只能证明 enc_time 被本地 1..16 范围拒绝，不能据此知道实际是非正数还是超过 16，或证明所有账号故障都由此引起。

[上游报告](https://github.com/liuchuancong/pure_live/issues/892#issuecomment-5863753809) 提及登录态 enc_time=1000；发帖者自称 AI 参考，未在本次账号独立采集，作为线索而非已验证平台事实。现有签名本身按 enc_time 次 MD5 迭代，并无 16 次算法限制。解析上限是独立的本地兼容限制。

本版只将上限统一为 DouyuDescriptor.maxHashRounds=4096，覆盖较高次数并保持有限 CPU 成本；拒绝 0、负数、4097 和极大整数，保留字段、有效期、账号身份缓存、五分钟生命周期、原有最多一次重试和登录续期。没有关闭证书校验、绕过鉴权或收集账号凭据。

修改前新增三项回归全部失败；独立 Python hashlib 生成 1/16/17/1000/4096 次、普通/特殊签名共十个向量。另验证字符串轮数、安全范围、过期缺字段，以及模拟登录身份下 0/1/299/300 秒请求和缓存重取的完整 adapter 链。旧 S07 合成向量原样保存：仅旧 enc-time-17 的拒绝预期改为可用和独立哈希断言，其他旧向量继续逐项比较。先前全套唯一失败为这项旧边界预期，原日志保留。

验证全部离线，不访问用户账号、读取验证码或索取 Cookie。待 5.4.13 发布后请受影响账号实际复测；#15 继续开放，不能用合成响应声称登录问题全部解决。


## 5.4.13 发布交付

[5.4.13](https://github.com/wzgrx/PureLive/releases/tag/v5.4.13) 已公开，PR #40 合并 `83ab860fd914cc16ea38552c6fc0b6a76669a532`；构建与标签固定 `ae2be3c47a4e10cc52ec734683e1818d13c7a8b8`。完整门禁 all/14 通过，十个正式包和 SHA256SUMS 共十一项远端哈希及公开下载通过。

有效 RED 与修正后九项重点回归分别保留：升级说明可遥控滚动并离开、操作键与跳过状态、三个尺寸设置边框实际像素、壁纸重试从旧错误切换为加载且不排队。原 #30 防裁切及全部既有升级/下载测试由完整门禁覆盖。

K90 正常 5.4.13/5117 profile 与同源较旧显示版本号的非公开升级弹窗 profile 分别核验，后者只用于触发已公开更新通道；结束恢复正常 profile、原界面模式和精确旋转，数据保留。Windows 便携版、Linux、macOS 与 iPhone 模拟器首页逐张查看，安装包与运行文件哈希匹配。原 Sony 电视与遥控器、Apple 真机、Windows 安装覆盖和长期播放仍未完整验收，界面任务保留待真机；#37/#39 按修复发布回复关闭。

#38 只修正确定复现的重试加载反馈，网络与原设备失焦不作已修复声明，继续开放；#33 华为缓冲继续开放。#15 较高签名轮数的本地限制已修正，独立 Python 向量及五分钟缓存重取、斗鱼解析/适配器 113 项回归通过，实际账号仍待复测并保持开放。本地完整回执保存在 outputs/purelive-5.4.13。


## 更新通道与实际原生验证

两个 JSON 字节完全一致，旧解析器、版本比较、包选择与全部历史保留通过。最终两库远端提交见 PR 与发布审计；新仓库推送前再次完成完整门禁。

旧库完整门禁未通过：5.4.12 基线与 5.4.13 候选为相同六项历史版本页失败，无新增；其余检查通过。本次两文件例外已明确授权并记为 D-055。

K90 实际交互摘要：

```json
{
  "source_commit": "ae2be3c47a4e10cc52ec734683e1818d13c7a8b8",
  "recorded_at": "2026-10-24T12:54:10.856723+00:00",
  "normal_5_4_13_profile_restored": true,
  "original_ui_mode_restored": true,
  "original_ui_mode": "auto",
  "actual_published_update_dialog_remote_path_passed": true,
  "settings_frame_boundary_passed": true,
  "remote_sequence": "Down initializes project, Down notes (visible white border), notes OK does not install, Up project (XML focused), Down notes, Down other download methods, Right cancel (XML focused), Right download and install (XML focused, never activated), Left cancel and OK dismiss.",
  "update_feed_version": "5.4.11",
  "qa_display_version": "5.4.10",
  "data_preserved": true,
  "only_v4dev_operated": true,
  "actual_installed_identity_verified": true,
  "settings_checks": "TV platform/background groups and shared settings: visible focus boundaries manually inspected; original focus zoom true restored.",
  "restoration": "Selected Auto from mode dialog, restored exact free/user_rotation=0 and normal 5.4.13/5117; final screenshot shows original populated favorites in desktop/phone layout.",
  "unverified": [
    "Original Sony TV and remote",
    "Long notes scroll and download branch on physical device; controlled widget regressions only",
    "Wallhaven original Sony timeout"
  ]
}
```

手机原始截图保留本地，不公开个人关注列表。

[Windows 便携包首页](verify/windows-init.jpg)；[Linux 包首页](verify/linux-home.jpg)。

[macOS 首页](verify/macos-home.png)；[关闭后重开首页](verify/macos-reopened.png)。macOS 最终 ZIP 另在两个独立环境原样解包验签并启动；iOS 为模拟器，原自签设备尚未覆盖。

## macOS 拒绝候选、对照与最终缓解

B1 两个候选的乱码／黑屏证据保留在 Actions 与本地，不作为定稿图片提交仓库。六作业精确包对照中默认路径第二启出现黑屏并记录 GPU Hang；Skia 四次启动的 16 帧正常。因此新源采用官方支持的 Mac-only 回退，全部十包重新构建，最终 ZIP 在两个独立环境原样验签、启动及菜单和关窗重开逐图核验。底层驱动／云环境／引擎原因仍未确定，其他 Mac 硬件和长期播放待验证。详细过程与作业链接见 Z02.5。

## 移动端手势与原 iPhone 验收范围

六项修改前失败证明原生回读期间丢弃位移和旧回读覆盖；修正后 18 项受控延迟与 26 项现有房间回归通过。iPhone 15 Pro Max 原反馈已确认 iOS 18.7.8，亮度／媒体音量仍待复测；#41 保持开放，不把方法通道模拟写成真机修复。

## Apple 录制能力接线

构建清单已有 iOS/macOS FFmpeg 包，旧能力判断却把两端排除，导致 ffmpeg 注入 null。修改前清单驱动的两个 Apple 回归失败，修正后七项能力与四项现有接线检查通过。两个云端原生入口均真实执行一秒 PCM→WAV；回执、输出头和 8000 帧内容独立检查。该入口与正式包的 Dart 入口分开，证明原生内核和同一 Runner 可用，不代表原自签 iPhone 的真实直播、导出、后台或长录已验收；#42 保持开放。

[国内五大平台巡检记录](verify/platform-patrol.md)。


## 发布期间新增反馈

#42 的四张补充截图已逐张查看：应用为 5.4.12，iOS 27.2；签名工具名称和版本尚未确认，不公开截图中的签名身份。另询问黑色留白，现有“竖屏全屏画面模式 → 完整画面”已提供，已回复操作路径（[回复](https://github.com/wzgrx/PureLive/issues/42#issuecomment-6384554072)）。原设备录制、停止和导出仍待复测。

#43 的侧栏现有换台图标和目标格回调已查明，已回复操作位置（[回复](https://github.com/wzgrx/PureLive/issues/43#issuecomment-6384583426)），原 Windows 版本／缩放／截图与明确文字入口诉求待补充；登记 V02.40，保持开放，不列入 5.4.13 已修复项。

## Apple 验证清理与独立复核

原 Apple 作业两端小样成功后，macOS 退出等待挂起；取消后四包校验、上传仍成功，原 cancelled 状态保留。两端输出文件和完整 WAV 数据已独立检查；追加的两个固定源 ZIP 作业逐图核验。工作流清理修正及复核入口单独由 [PR #44](https://github.com/wzgrx/PureLive/pull/44) 合并，有独立完整门禁与实际清理回归，十个正式包仍固定同一产品源。


菜单覆盖边界：最终 ZIP 两个独立作业的四张菜单调用后帧正常，但下拉项未出现在截图；实际 Edit 菜单展开证据来自正常构建同一候选应用。不把调用后截图扩大为四次展开菜单验收。
