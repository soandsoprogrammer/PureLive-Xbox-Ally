# 5.4.14 全平台发布

本轮 A13.5；计划固定一个提交构建十包，完整门禁、身份、远端哈希、匿名下载及两库更新各自核对。现已公开发布；实际验证范围与更新通道状态见下方交付记录。


## 5.4.14 发布交付

[5.4.14](https://github.com/wzgrx/PureLive/releases/tag/v5.4.14) 已公开，PR #45 合并 `f3a1f81aa9442017a0d783f81e8f07176d935418`；构建与标签固定 `90b39a91b7056632d4f80d2a7668f62b5dfe35ff`。源提交完整 all/14 通过，十个正式包和 SHA256SUMS 共十一项远端 SHA-256 匹配，匿名 HEAD 与校验文件内容检查通过。

Windows 从已校验便携包的隔离额外实例运行，使用无凭据的三个公开房间；第三、四格为空时，右键第二格即在音量下方显示选台。沉浸和全屏都实际替换第二格，第一格直播继续，模式保持；选已有第一格房间只选中原格，不重复播放。Esc 先关面板、再退回普通模式；测试窗口已退出，正式安装与启动项未操作。静音测试不证明听感或长期多路负载。

K90 仅 com.mystyle.purelive.v4dev 的同源 5.4.14/5118 profile 保留数据安装并确认首页及安装 APK 哈希；原界面和旋转保留。该冒烟不等同于手机横屏长按或电视遥控器逐项验收，A13.5 保留待真机。Linux、macOS 最终 ZIP 与 iPhone 模拟器首页逐张检查；Windows 安装覆盖、Apple 真机、电视与长期播放仍未完整验收。

macOS 两个独立作业各对最终原样 ZIP 验签并两次启动，在 5/30/90 秒、菜单调用及关窗重开后检查；四次启动均为 Skia Metal，未见已知 GPU Hang 签名。该结果仅覆盖云端测试环境，其他 Mac 硬件仍待使用反馈。Apple 原生内核各执行一秒 PCM→WAV 且独立核对头与内容，不作为 #42 原自签设备的直播录制／导出验收。

国内五大匿名只读巡检共 64 项通过，抖音主播搜索为既有不支持项；每站弹幕观察 25 秒，不登录、不发言。#15 后续获得原受影响用户 Win11 与 Android 登录、重启、离开房间等待后返回均恢复的反馈，并结合小米 13 反馈回复关闭；等待时长未精确给出，不扩大为精确五分钟或长期全账号验收。#33/#41/#42 继续开放。#38 反馈者自行关闭后进一步确认原 Sony 的重试按钮焦点已恢复；其 .cc API 需代理的网络条件与误认 .pics 为官网分别记录，不扩大为所有网络的结论。构建期间新增 #46 菜单首项焦点框裁切、#47 Windows 偶发白屏及 #48 IPTV 节目单首次刷新／RTP 导入，均已评估回复并继续开放，不作为本版已修复项。

两个更新 JSON 经过旧解析器、版本比较、包选择和全部历史保留检查；旧库完整门禁仍有相同六项版本页历史失败，无新增；维护者已明确授权仅适用于 5.4.14 的两文件例外，记为 D-056。旧库提交 `82db9249d8908f0a75beb0bb5b6a212b871c779e` 已核对只修改 assets/version.json 和 assets/releases.json，两库内容逐字节相同；不改归档代码或测试，不覆盖未来版本。新仓库发布记录与更新文件推送前仍执行完整 all/14。各项回执保存在本地 outputs/purelive-5.4.14，最终远端提交及通道状态见 PR 审计。


## 原生验证图片

[windows-home](verify/windows-home.jpg)；[windows-immersive](verify/windows-immersive.jpg)；[windows-fullscreen](verify/windows-fullscreen.jpg)；[windows-existing](verify/windows-existing.jpg)；[linux-home](verify/linux-home.jpg)；[macos-home](verify/macos-home.jpg)；[macos-reopened](verify/macos-reopened.jpg)。手机原始图片含个人关注信息，仅保留本地。

[五平台巡检记录](verify/platform-patrol.md)。
