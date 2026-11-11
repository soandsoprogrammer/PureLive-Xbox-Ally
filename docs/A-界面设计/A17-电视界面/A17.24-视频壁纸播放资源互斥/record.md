# 实现记录

2026-10-31，基线248f9312255308a1be61c760b6363d421afb8a15。用户授权自主移植、优化和发布。

旧壁纸仅暂停仍占解码器。本次进入TV直播/点播前等待背景会话实际退役；退出前台后等待其原生清理再恢复背景。新增waitForResourceRelease区分dispose的有界宽限与实际释放。壁纸切换意图合并，迟到open/loop按所有者拒绝，清理超时禁用该背景重新分配；前台超时仍保留hold直到实际清理成功。旧房替换的清理也单独持有hold，不让离开页面后背景提前恢复。会话9项和壁纸11项回归通过；控制流不串行阻塞换台。

测试和原始反证位于仓库外outputs/purelive-5426-20261031。全量门禁、最终安装包与原生证据在发布收尾补记。

## 发布前补充回归

第一候选保留在仓库外purelive-5426-attempt1-20261031，未发布。更换key时新组件先init、旧组件后dispose；只在dispose跟踪清理仍太晚。新增测试在旧候选期望1个解码器、实际2个，明确失败。修复保留离场会话清理作为背景hold与前台有界屏障，新组件在本帧finalizeTree后应用启动意图，没有固定延时；实际释放失败则保持背景禁用。11项壁纸回归与静态检查通过，重新冻结、完整门禁与全部构建。

## 发布收尾


5.4.26+5130，安装包源码`8d57daacf06595ff5641eefcc5430166e379da26`，代码PR [#122](https://github.com/wzgrx/PureLive/pull/122)，代码合并`4141ed1805239a01932237a1d6203ba9863fed66`。修订源码通过完整all/14门禁，源码无漂移。播放器127项、导航70项、TV设置/焦点50项、壁纸11项回归通过；原始修改前失败记录与第一候选均保留。

最终十包与SHA256SUMS逐项核对构建、本地和GitHub摘要，并重新匿名下载验证；发布页[5.4.26](https://github.com/wzgrx/PureLive/releases/tag/v5.4.26)。Windows独立目录、Android9专用AVD、Linux最终TAR、iOS模拟器、托管Mac最终ZIP及独立原生录制/播放探针的身份和证据分别记录。

源证据位于仓库外outputs/purelive-5426-20261031；第一候选位于purelive-5426-attempt1-20261031，未发布且不作为最终包验收。原47文件草稿逐文件哈希与HEAD保留，取舍见V03.9/migration.md。原Huawei/Sony/Honor/GTX760、混合DPI及实体K90/Apple硬件未验证，#33/#47/#49继续开放。模拟器没有可听硬件音频输出。

本轮另收到5.4.25原机新日志：[33反馈](https://github.com/wzgrx/PureLive/issues/33#issuecomment-6538264896)、[49反馈](https://github.com/wzgrx/PureLive/issues/49#issuecomment-6538486728)。首个实例file-loaded并播放，后续不同实例已engine-ready/start-file，仍出现轨道数0与buffering_stall_timeout。原生初始化超时不再是这两份日志显示的阻塞点；媒体载入/解码资源或源链路等原因尚未区分，没有证据认定视频壁纸导致该现象。本次移植不声称解决这些原机换房反馈，继续保留开放。
