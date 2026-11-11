# V03.8 全部历史 issue 重新审查清单

本次抓取50条issue（10开放、40关闭）、177条评论和558个时间线事件；2026-10-26再次查询无新增或更新。重新核对原始报告、关闭后追评、历史任务/提交及对应当前实现，优先用可复现行为判断；不按旧回复的“已修复”直接结案。原始数据与完整构建日志保存在独立工作输出目录，不上传带用户信息的原始日志。

以下是处理结论与验收边界，不是“50项全部原机通过”的报告。未新发现缺口的既有修复保持，纳入本次最新依赖的完整门禁；原设备未覆盖的项目仍如实记录。#16/#23、存储误重连和设置焦点缺口有本轮修改前失败证据。

| Issue | 抓取状态 | 本次复核与处理 |
|---|---|---|
| [#1](https://github.com/wzgrx/PureLive/issues/1) | closed | 斗鱼登录入口与 #15 联合回归；原条只有“已更新”，不据此声称所有登录方式原机通过。 |
| [#2](https://github.com/wzgrx/PureLive/issues/2) | closed | Cookie/取流授权归入 #15 的身份、签名缓存与错误处理复核。 |
| [#3](https://github.com/wzgrx/PureLive/issues/3) | closed | 保留旧仓库搬家说明和双更新通道，发布时验证具体版本数据。 |
| [#4](https://github.com/wzgrx/PureLive/issues/4) | closed | 平板底栏与玻璃布局保留，纳入尺寸及新依赖回归。 |
| [#5](https://github.com/wzgrx/PureLive/issues/5) | closed | 已检查方向恢复的代次和进入前方向记忆；原平板未操作。 |
| [#6](https://github.com/wzgrx/PureLive/issues/6) | closed | IPTV列表选择及内置删除标记保留，最终升级数据检查继续。 |
| [#7](https://github.com/wzgrx/PureLive/issues/7) | closed | 原用户确认旧iPadOS14.3不满足当前最低系统；不宣称已支持。 |
| [#8](https://github.com/wzgrx/PureLive/issues/8) | closed | 设备同步对话框与公共TV焦点路径复核。 |
| [#9](https://github.com/wzgrx/PureLive/issues/9) | closed | 底栏尺寸纳入导航和大字回归。 |
| [#10](https://github.com/wzgrx/PureLive/issues/10) | closed | 关注徽标保留；不改原状态含义。 |
| [#11](https://github.com/wzgrx/PureLive/issues/11) | closed | 玻璃性能仍区分结构测试、原生体验和帧时测量。 |
| [#12](https://github.com/wzgrx/PureLive/issues/12) | closed | 桌面音量控件保留；新窗口工具链已实际播放。 |
| [#14](https://github.com/wzgrx/PureLive/issues/14) | closed | 窄横屏和TV触摸路径保留，纳入布局回归。 |
| [#15](https://github.com/wzgrx/PureLive/issues/15) | closed | 原用户已有5.4.13登录播放及重启确认；签名身份/TTL/轮次上限逻辑复核。 |
| [#16](https://github.com/wzgrx/PureLive/issues/16) | closed | 本轮新复现同内容后续付费事件丢失，D07.8修复接收、历史和录制三处。 |
| [#17](https://github.com/wzgrx/PureLive/issues/17) | closed | 关注页上键焦点记忆与 #35 层级返回合并核验。 |
| [#18](https://github.com/wzgrx/PureLive/issues/18) | closed | 关闭后的字母房间反馈由 #29 后续修复承接，不能漏读该追评。 |
| [#19](https://github.com/wzgrx/PureLive/issues/19) | closed | 关闭自动录制保留任务，已检查共享record_actions及恢复测试。 |
| [#21](https://github.com/wzgrx/PureLive/issues/21) | closed | 多画面静音与M快捷键保留，纳入新依赖回归。 |
| [#22](https://github.com/wzgrx/PureLive/issues/22) | closed | 首选平台选择复用TV公共行和对话框。 |
| [#23](https://github.com/wzgrx/PureLive/issues/23) | closed | 关闭后未读角标要求此前缺失；D07.8补齐且有修改前失败的真实入口测试。 |
| [#24](https://github.com/wzgrx/PureLive/issues/24) | closed | iPad手势与 #41 共享路径复核；无原iPad真机结论。 |
| [#25](https://github.com/wzgrx/PureLive/issues/25) | closed | 唤醒锁引用计数、串行写入、前台恢复已检查；真实长期播放仍分开验证。 |
| [#26](https://github.com/wzgrx/PureLive/issues/26) | closed | KICK功能已交付，保留原生HTTP/2与代理设置；不重写已验证的登录/网络路径。 |
| [#29](https://github.com/wzgrx/PureLive/issues/29) | closed | 自定义抖音字母房间对应 #18 追评，保留链接和adapter回归。 |
| [#30](https://github.com/wzgrx/PureLive/issues/30) | closed | 焦点环完整性转入公共TV行与尺寸测试。 |
| [#32](https://github.com/wzgrx/PureLive/issues/32) | closed | 1x4竖排保持布局保存与会话复用回归。 |
| [#33](https://github.com/wzgrx/PureLive/issues/33) | open | 仍开放：原华为电视换房失败及音画不同步未证明根因；G02.8补正式包诊断，不能把零尺寸销毁日志当根因。 |
| [#35](https://github.com/wzgrx/PureLive/issues/35) | closed | 关注页返回两级路径保留，不重置筛选或用户已选焦点。 |
| [#37](https://github.com/wzgrx/PureLive/issues/37) | closed | 更新弹窗按当前路径回归；注意旧归档编号相同不代表同条新库issue。 |
| [#38](https://github.com/wzgrx/PureLive/issues/38) | closed | 原用户已确认重试焦点可用；Wallhaven源域名与网络差异不能误归为焦点错误。 |
| [#39](https://github.com/wzgrx/PureLive/issues/39) | closed | 共享TV边框、主题及多尺寸一致性复核。 |
| [#41](https://github.com/wzgrx/PureLive/issues/41) | closed | 原用户后来确认实际安装旧5.4.5；新包恢复，不能继续当新版本权限故障。 |
| [#42](https://github.com/wzgrx/PureLive/issues/42) | open | 仍开放：既有iOS旧UUID默认路径重定向匹配截图；本轮H01.9另修存储失败误重连，原机签名安装未复测。 |
| [#43](https://github.com/wzgrx/PureLive/issues/43) | closed | 多画面直接选频道路径保留，纳入会话/布局测试。 |
| [#46](https://github.com/wzgrx/PureLive/issues/46) | closed | TV菜单边缘裁切与公共焦点环复核。 |
| [#47](https://github.com/wzgrx/PureLive/issues/47) | open | 仍开放：混合显示器白屏/内外几何不同，当前机器未复现原组合；新工具链原生窗口操作通过，不据此关闭。 |
| [#48](https://github.com/wzgrx/PureLive/issues/48) | closed | EPG延迟与RTP识别/解复用回归保留；本机原生MP4与节目单已查看，不能代替原运营商组播。 |
| [#49](https://github.com/wzgrx/PureLive/issues/49) | open | 仍开放：两个网络都有成功与失败，已核对A→B→A全过程；G02.8补状态快照，不改未经证明的解码/重连策略。 |
| [#52](https://github.com/wzgrx/PureLive/issues/52) | closed | 禁用代理输入的焦点跳过规则保留，专门回归通过。 |
| [#53](https://github.com/wzgrx/PureLive/issues/53) | closed | 右键已有窗口内全屏往返，不是无条件退出房间；本轮Windows原生重新看到该行为。 |
| [#54](https://github.com/wzgrx/PureLive/issues/54) | closed | TV日志导出是诊断工具，不把交付导出能力当播放故障修复。 |
| [#56](https://github.com/wzgrx/PureLive/issues/56) | closed | 宽屏设置嵌入与当前导航结构复核。 |
| [#58](https://github.com/wzgrx/PureLive/issues/58) | closed | macOS遮挡与最小化策略区分保留；最终新Xcode原生探针继续执行。 |
| [#59](https://github.com/wzgrx/PureLive/issues/59) | open | 本地配置预览TV路径纳入A11.8公共设置；本轮A11.9另补加载中覆盖后的焦点恢复。 |
| [#60](https://github.com/wzgrx/PureLive/issues/60) | open | 五类手机设置动画沿用A11.8公共页面改动，待最终包手机操作。 |
| [#61](https://github.com/wzgrx/PureLive/issues/61) | open | 七类TV设置公共样式与布局已重新对照原截图；A11.9补焦点生命周期缺口。 |
| [#62](https://github.com/wzgrx/PureLive/issues/62) | open | 冷启动已有焦点必须直接从FocusNode读取；本轮再覆盖异步加载、弹窗往返和不抢用户焦点。 |
| [#63](https://github.com/wzgrx/PureLive/issues/63) | open | 分区平台图标沿用A11.8修复，待最终候选与各主题核验。 |
| [#65](https://github.com/wzgrx/PureLive/issues/65) | open | 导航显示/隐藏设置与中键全屏保留；本轮Windows实际中键往返和小窗恢复通过。 |


## 审查期间新增反馈

2026-10-27重新读取仓库：共51条issue，13条开放；#16/#23是本轮重新打开，新增#68于审查期间提交。

| 条目 | 当前状态 | 重新判断 |
|---|---|---|
| [#68](https://github.com/wzgrx/PureLive/issues/68) | open | 下播或最终播放失败后自动切换到其他在线关注房间，含多画面；属新增功能提议V01.11，已回复默认关闭、现有恢复耗尽后才触发、各窗口独立、排除其他窗口房间、无候选停止。未实现，不随5.4.18缺陷修复关闭。 |

## K90最终包复核补充

e3e候选首次IPTV进入暴露窄横屏焦点已存在但在可视区域上方。已将回归边界从整页改为实际滚动视口，并在修改前复现；A11.9按上下边界选择滚动策略。其余六个TV页的初始焦点和Down移动、手机设置返回位置、安装后原数据保留已核对；新修复包仍待同源原生及全量验证，不提前关闭#61。

## K90导航安全区复核补充

678候选实际上滑隐藏后，分区分类行与状态栏文字重叠。16项带系统边距的真实主页回归均在修改前失败，公共手机外壳接管隐藏期间的SafeArea后完整42项首页回归通过。原设置已恢复，新同源包继续验证；#65不提前关闭。

## 电视共享Material按钮补充

K90在当前输入模式中普通按钮有逻辑焦点、位置可见却没有边框。A11.9以电视局部主题覆盖统一边框，不强制全局输入模式。修改前5项电视绘制失败、5项普通触摸保持通过；修复后10项加原40项电视回归全部通过，新同源包继续复验。

完整路由补查：透明背景Theme覆盖了局部标准按钮样式；真实IPTV两种尺寸的焦点绘制断言先失败，调整Theme层级后50项电视回归通过。组件测试和实际路由证据分别保留，新同源手机检查继续。
