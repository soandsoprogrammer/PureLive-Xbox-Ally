# 实现记录

2026-10-31，基线248f9312255308a1be61c760b6363d421afb8a15。用户授权自主移植、优化和发布。

根因：原生最大化/取消最大化或重新聚焦时不一定另发restore事件，minimized标记可能持续true，影响播放后台策略。三个对应回归旧实现失败，普通restore和blur对照通过；修复后五项通过。只在实际恢复事件清除标记，不改手动暂停策略。Windows完整恢复屏障和首帧子窗口同步继续保留。

测试和原始反证位于仓库外outputs/purelive-5426-20261031。全量门禁、最终安装包与原生证据在发布收尾补记。

## 发布收尾


5.4.26+5130，安装包源码`8d57daacf06595ff5641eefcc5430166e379da26`，代码PR [#122](https://github.com/wzgrx/PureLive/pull/122)，代码合并`4141ed1805239a01932237a1d6203ba9863fed66`。修订源码通过完整all/14门禁，源码无漂移。播放器127项、导航70项、TV设置/焦点50项、壁纸11项回归通过；原始修改前失败记录与第一候选均保留。

最终十包与SHA256SUMS逐项核对构建、本地和GitHub摘要，并重新匿名下载验证；发布页[5.4.26](https://github.com/wzgrx/PureLive/releases/tag/v5.4.26)。Windows独立目录、Android9专用AVD、Linux最终TAR、iOS模拟器、托管Mac最终ZIP及独立原生录制/播放探针的身份和证据分别记录。

源证据位于仓库外outputs/purelive-5426-20261031；第一候选位于purelive-5426-attempt1-20261031，未发布且不作为最终包验收。原47文件草稿逐文件哈希与HEAD保留，取舍见V03.9/migration.md。原Huawei/Sony/Honor/GTX760、混合DPI及实体K90/Apple硬件未验证，#33/#47/#49继续开放。模拟器没有可听硬件音频输出。

本轮另收到5.4.25原机新日志：[33反馈](https://github.com/wzgrx/PureLive/issues/33#issuecomment-6538264896)、[49反馈](https://github.com/wzgrx/PureLive/issues/49#issuecomment-6538486728)。首个实例file-loaded并播放，后续不同实例已engine-ready/start-file，仍出现轨道数0与buffering_stall_timeout。原生初始化超时不再是这两份日志显示的阻塞点；媒体载入/解码资源或源链路等原因尚未区分，没有证据认定视频壁纸导致该现象。本次移植不声称解决这些原机换房反馈，继续保留开放。
