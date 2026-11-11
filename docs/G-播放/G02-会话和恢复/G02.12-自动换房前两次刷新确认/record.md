# record

2026-10-30：核对最新 master、全部开放 issue 和历史回复。用户已委托维护决策、开发、合并、发布与已验证 issue 收尾。

## 2026-10-30 实现检查点

五项能力已接入；#115修复前失败已保留，新增暂停/取消边界回归；#108独立正负dB与默认继承、多画面复用回归通过；#106四种手势回归通过；#110十三项焦点回归通过。三成员静态分析通过，修改后的四组界面/自动切房集成107项通过。完整门禁、所有九项需求和最终原生验收未完成，当前不推送、不发布、不关闭issue。

## 真实句柄的跨实例阻塞回归

#33新日志在已取到详情/清晰度/地址后出现`engine_create_timeout`。重新检查底层分支发现`NativePlayer.lock`为静态锁，所有实例的创建、控制、停止、释放共用队列。旧内核停止回包未完成时，即使会话已隔离旧内核，替换内核仍无法初始化。[实际采用的上游代码](https://github.com/Predidit/media-kit/blob/6b188ae978808a63e5b58b7ce61f7725238c04c5/media_kit/lib/src/player/native/player/real.dart)也保留此静态锁；[mpv内部设计说明](https://github.com/mpv-player/mpv/blob/master/DOCS/tech-overview.txt)要求实例内部正确同步，并允许不同实例独立工作。

新增真实mpv句柄回归：在旧实例释放中扣住停止回包，要求替换实例在旧回包放行前完成初始化、音量控制和暂停。原实现稳定在2秒截止时间失败；改为实例锁后通过，原有每个句柄的操作顺序和事件缓冲区所有权保持。包括已有恢复、Android Surface和异步属性回归的16项及全部117项播放器测试通过。该证据确认公共代码缺陷，不代表原Huawei/Sony/Honor已验收，#33/#49继续开放。


### 2026-10-30 Native projection navigation correction

The exact 4d53681 Windows ZIP played a real generated stream in its owned fullscreen projection process. Selecting a second cell and a direct authenticated room command returned successfully but retained the first room. The production receiver replaced its sole home route on the first command; subsequent root replacements shared a GoRouter page key and retained the existing StatefulWidget/player. A real-router widget regression reproduced the stale room before the fix. The receiver now pushes its first room above home, then replaces only that room, preserving a base route and fresh room state. Four navigation/IPC tests and six-member fatal-infos analysis pass. All packages and the complete gate will be regenerated for this correction; old artifacts remain preserved outside the repository. No original-device acceptance is claimed.


### 2026-10-30 Projection lifecycle acceptance before the final freeze

The exact e2c3a6bb Windows ZIP correctly changed rooms, but replacing the projection route twice could leave the window outside fullscreen. The old room finished its route transition after the new room had entered fullscreen and called the process-wide fullscreen exit during disposal. Its synchronous runtime stop also settled shared watch-time notifiers while the widget tree was locked. A real GoRouter/LivePlayPage regression failed with both behaviors before the correction. Projection-room disposal now leaves the longer-lived projection window fullscreen, and page-initiated runtime release starts after widget unmount. Normal Windows-room fullscreen exit remains covered by the existing regression.

All 39 projection/navigation/IPC/live-page regressions pass. An incremental Windows build with the exact production-file overlay was exercised natively in a separate generated-data instance before freezing: the same child window played D, A, D and rapid A-D-A with the final A visible, retaining fullscreen and the main window's focus. Leaving the multiview wall closed the child and retained the main window. Original screenshots and file hashes are preserved privately. This is one-monitor evidence; physical hotplug and a second virtual desktop are not claimed. Every release installer and the complete gate will now be regenerated from the new frozen source; no obsolete private candidate is published.


### 2026-10-30 Android 17 LAN runtime access correction

A final platform-permission audit found that the new playback receiver, discovery and pairing paths did not use the existing Android 17 runtime permission bridge. The manifest already declared ACCESS_LOCAL_NETWORK, but that does not grant it for target SDK 37. Android and Flutter primary documentation require permission before Dart sockets are opened: https://developer.android.com/privacy-and-security/local-network-permission and https://docs.flutter.dev/platform-integration/android/local-network-permission . The earlier API28 native acceptance could not exercise this enforcement, so that coverage gap is explicitly retained.

Three refusal regressions failed before wiring. Receiver bind, discovery and pairing now request access before network I/O; refusal remains distinct from wrong address/code and shows a LAN-specific translated explanation. Stopping while a prompt is pending invalidates late approval. All 42 integrated remote/settings/projection cases passed, followed by all 11 remote/copy cases and fatal-infos analysis after the wording correction. Tests verify no receiver/code/session/discovery side effects on refusal, retry after approval, cancellation and real UI messages; fake discovery fails before any real multicast I/O.

A new, isolated API37/x86_64 generated-data AVD displayed the actual system permission prompt. Refusal left reception off; retry and Allow started the receiver; its browser entry returned HTTP200 through an owned loopback forward, and unauthenticated status returned401. Reception was stopped, the code retired, permission restored to ungranted, forward removed and the owned AVD stopped with data preserved. This was a working-source profile, not a frozen release package; only its refusal-copy key/locale wording changed afterwards, with final-package copy/native revalidation still required. It is not physical K90 or multicast LAN acceptance. Every installer and the complete gate will be regenerated from the corrected frozen source before publication.


### 2026-10-31 Full language-parity correction

The full gate for a32ed430 rejected one i18n parity test: the new LAN-refusal sentence existed only in the two base languages, while thirteen selectable languages require the same key set. All thirteen now have localized text, preserving sorted four-space JSON and existing placeholder/line-break contracts. The complete i18n suite and the real remote-settings refusal widget test pass. No failed-source installer was built or published. Permission and playback production code did not change. The failed gate and source bundle are retained separately; the corrected source gets a fresh all/14 gate and all installers.


## 2026-10-31 全部需求统一发布与收尾

[5.4.24](https://github.com/wzgrx/PureLive/releases/tag/v5.4.24)已公开；构建源码`f053ffc90e9d0a8ad4e69d72fe153c28d6f809cc`，PR#117合并`ff4ebe894549ae0e5f57cdf57f53fb1b5035562d`。九项需求全部实现，十包及校验文件经远端SHA-256、匿名下载和完整性清单逐项核对。原生证据的实际源码与覆盖边界见Y01.35/verify.md；原设备问题#33/#47/#49继续开放。

旧库提交`81122a0da4b99387a307829ed3d57141a19536d2`只更新两个JSON；新鲜基线与最终数据同六项历史版本页失败，兼容与全部215条历史保留通过。D-078只适用于本版。现代同步README、任务和两个JSON后重新执行完整门禁，再合并并匿名复读双库四份更新文件。
