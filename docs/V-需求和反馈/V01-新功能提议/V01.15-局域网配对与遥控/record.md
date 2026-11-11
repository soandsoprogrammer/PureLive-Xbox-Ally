# record

2026-10-30：核对最新 master、全部开放 issue 和历史回复。用户已委托维护决策、开发、合并、发布与已验证 issue 收尾。

## 2026-10-30 第二实现检查点

已实现默认关闭的局域网接收服务、六位配对码、12小时会话、撤销/轮换、mDNS与UDP发现、地址/二维码、App和内置浏览器控制端、直播链接推送，接入手机/电视/多画面播放器与电视方向/确认键。新5项真实loopback双客户端、过期/撤销、旧目标隔离、晚到链接和异常输入测试通过；修正拒绝请求未消费POST正文导致连接复用失败。原设置布局三项失败已修正并复验39通过；未修改归档基线。跨设备和浏览器/系统界面验收未完成。

所有九项需求完成后统一发版。当前未跑最终全量门禁，未推送、未发布、未关闭issue。


### 2026-10-30 Android 17 LAN runtime access correction

A final platform-permission audit found that the new playback receiver, discovery and pairing paths did not use the existing Android 17 runtime permission bridge. The manifest already declared ACCESS_LOCAL_NETWORK, but that does not grant it for target SDK 37. Android and Flutter primary documentation require permission before Dart sockets are opened: https://developer.android.com/privacy-and-security/local-network-permission and https://docs.flutter.dev/platform-integration/android/local-network-permission . The earlier API28 native acceptance could not exercise this enforcement, so that coverage gap is explicitly retained.

Three refusal regressions failed before wiring. Receiver bind, discovery and pairing now request access before network I/O; refusal remains distinct from wrong address/code and shows a LAN-specific translated explanation. Stopping while a prompt is pending invalidates late approval. All 42 integrated remote/settings/projection cases passed, followed by all 11 remote/copy cases and fatal-infos analysis after the wording correction. Tests verify no receiver/code/session/discovery side effects on refusal, retry after approval, cancellation and real UI messages; fake discovery fails before any real multicast I/O.

A new, isolated API37/x86_64 generated-data AVD displayed the actual system permission prompt. Refusal left reception off; retry and Allow started the receiver; its browser entry returned HTTP200 through an owned loopback forward, and unauthenticated status returned401. Reception was stopped, the code retired, permission restored to ungranted, forward removed and the owned AVD stopped with data preserved. This was a working-source profile, not a frozen release package; only its refusal-copy key/locale wording changed afterwards, with final-package copy/native revalidation still required. It is not physical K90 or multicast LAN acceptance. Every installer and the complete gate will be regenerated from the corrected frozen source before publication.


### 2026-10-31 Full language-parity correction

The full gate for a32ed430 rejected one i18n parity test: the new LAN-refusal sentence existed only in the two base languages, while thirteen selectable languages require the same key set. All thirteen now have localized text, preserving sorted four-space JSON and existing placeholder/line-break contracts. The complete i18n suite and the real remote-settings refusal widget test pass. No failed-source installer was built or published. Permission and playback production code did not change. The failed gate and source bundle are retained separately; the corrected source gets a fresh all/14 gate and all installers.


## 2026-10-31 全部需求统一发布与收尾

[5.4.24](https://github.com/wzgrx/PureLive/releases/tag/v5.4.24)已公开；构建源码`f053ffc90e9d0a8ad4e69d72fe153c28d6f809cc`，PR#117合并`ff4ebe894549ae0e5f57cdf57f53fb1b5035562d`。九项需求全部实现，十包及校验文件经远端SHA-256、匿名下载和完整性清单逐项核对。原生证据的实际源码与覆盖边界见Y01.35/verify.md；原设备问题#33/#47/#49继续开放。

旧库提交`81122a0da4b99387a307829ed3d57141a19536d2`只更新两个JSON；新鲜基线与最终数据同六项历史版本页失败，兼容与全部215条历史保留通过。D-078只适用于本版。现代同步README、任务和两个JSON后重新执行完整门禁，再合并并匿名复读双库四份更新文件。
