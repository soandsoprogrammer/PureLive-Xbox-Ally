# record

2026-10-30：核对最新 master、全部开放 issue 和历史回复。用户已委托维护决策、开发、合并、发布与已验证 issue 收尾。

## 2026-10-30 实现检查点

五项能力已接入；#115修复前失败已保留，新增暂停/取消边界回归；#108独立正负dB与默认继承、多画面复用回归通过；#106四种手势回归通过；#110十三项焦点回归通过。三成员静态分析通过，修改后的四组界面/自动切房集成107项通过。完整门禁、所有九项需求和最终原生验收未完成，当前不推送、不发布、不关闭issue。


### 2026-10-30 版本身份复查

第二轮all/14中，其余成员通过，应用版本常量与pubspec未同步导致安装版本/更新页断言失败，构建队列已拒绝启动。候选7657539及完整失败日志保存在仓库外，未推送、构建或发布。现同步pubspecVersion与pubspecBuild到5.4.24+5128，版本页与更新对话框47项回归通过，重新冻结并执行全量门禁；不改已发布更新JSON。


### 2026-10-30 原生验收后的候选重新冻结

首个bce367e4候选的14成员门禁、本地六包和Apple四包成功，仍未公开。实测后补齐回看推荐标签/文字对比度、异步旧时钟隔离、遥控设置搜索，并用真实mpv句柄复现修复#33日志对应的跨实例静态锁阻塞。修复前失败日志和首批包完整保留；应用相关38项与播放器117项通过，六成员致命级静态分析通过。

Android独立API28普通v4dev候选验证了浏览器暂停/保持/继续、25%音量、全屏/返回，多画面选中格子的39%音量与另一格0%的隔离，亮度102→202→退出恢复102及清除窗口覆盖，房间-6/+6dB、跨单房间/多画面读取和恢复默认。该批实测记录明确绑定bce367e4，最终改动仍须由重新冻结的同源包复验。先前候选和日志保存在仓库外candidate-r3-bce367e4，不作为最终交付包。


### 2026-10-30 Native projection navigation correction

The exact 4d53681 Windows ZIP played a real generated stream in its owned fullscreen projection process. Selecting a second cell and a direct authenticated room command returned successfully but retained the first room. The production receiver replaced its sole home route on the first command; subsequent root replacements shared a GoRouter page key and retained the existing StatefulWidget/player. A real-router widget regression reproduced the stale room before the fix. The receiver now pushes its first room above home, then replaces only that room, preserving a base route and fresh room state. Four navigation/IPC tests and six-member fatal-infos analysis pass. All packages and the complete gate will be regenerated for this correction; old artifacts remain preserved outside the repository. No original-device acceptance is claimed.


### 2026-10-30 Native settings and media acceptance

The 4d53681 API28 v4dev package searched for `remote` and reached the embedded LAN controller, exposing an untitled internal group identifier in the breadcrumb. Untitled groups now omit their internal identifiers in search results, matching their normal page presentation. A regression failed before the correction; all 30 settings tests and six-member fatal-infos analysis pass.

Native 4d53681 Android playback verified a public Douyu video, paused seeking to 8:29, and switching to 480P while retaining pause and position. The exact Windows ZIP in a light app theme displayed white readable video clocks and quality text while a public video and timeline danmaku played. A generated Android foreground audio fixture verified default permanent loss pauses; opt-in mixing continues through another media GAIN; an independent fresh-session transient interruption pauses and resumes after release. The AVD has no audible hardware sink; this is native focus/clock/frame evidence, not physical call or speaker acceptance.

With automatic room switching enabled through the real settings search, generated stalled channel B exhausted its original native recovery and two more full recovery cycles, then failed channel C was attempted before normal channel D played at 21:19:41 local time. Private, timestamped logs and original screenshots remain outside the repository. No original Huawei/Sony/Windows acceptance is implied. The projection navigation correction still requires the rebuilt final Windows package to demonstrate room/window reuse.


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
