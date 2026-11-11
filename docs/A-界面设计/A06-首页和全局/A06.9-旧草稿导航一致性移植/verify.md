# 发布验证

5.4.26+5130，安装包源码`8d57daacf06595ff5641eefcc5430166e379da26`，代码PR [#122](https://github.com/wzgrx/PureLive/pull/122)，代码合并`4141ed1805239a01932237a1d6203ba9863fed66`。修订源码通过完整all/14门禁，源码无漂移。播放器127项、导航70项、TV设置/焦点50项、壁纸11项回归通过；原始修改前失败记录与第一候选均保留。

最终十包与SHA256SUMS逐项核对构建、本地和GitHub摘要，并重新匿名下载验证；发布页[5.4.26](https://github.com/wzgrx/PureLive/releases/tag/v5.4.26)。Windows独立目录、Android9专用AVD、Linux最终TAR、iOS模拟器、托管Mac最终ZIP及独立原生录制/播放探针的身份和证据分别记录。

源证据位于仓库外outputs/purelive-5426-20261031；第一候选位于purelive-5426-attempt1-20261031，未发布且不作为最终包验收。原47文件草稿逐文件哈希与HEAD保留，取舍见V03.9/migration.md。原Huawei/Sony/Honor/GTX760、混合DPI及实体K90/Apple硬件未验证，#33/#47/#49继续开放。模拟器没有可听硬件音频输出。

本轮另收到5.4.25原机新日志：[33反馈](https://github.com/wzgrx/PureLive/issues/33#issuecomment-6538264896)、[49反馈](https://github.com/wzgrx/PureLive/issues/49#issuecomment-6538486728)。首个实例file-loaded并播放，后续不同实例已engine-ready/start-file，仍出现轨道数0与buffering_stall_timeout。原生初始化超时不再是这两份日志显示的阻塞点；媒体载入/解码资源或源链路等原因尚未区分，没有证据认定视频壁纸导致该现象。本次移植不声称解决这些原机换房反馈，继续保留开放。

有效滚轮显示滑块后，旧隐式控制器拖动时位置仍30，期望大于80；显式控制器修复通过。收藏图标原实现0、新合同1。TV三根页统一标题、首焦点、上下导航和透明背景，以及同步地址确认trim/取消保值均在50项专项和最终完整门禁覆盖。完整实体电视遥控器与所有桌面交互仍待覆盖。
