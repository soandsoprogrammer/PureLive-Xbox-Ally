# Z01.2 例行依赖升级检查：记录

## 2026-10-21（续 10-20：FFmpegKit 1.0.0 的原生包；用户：“重新构建五个平台的 FFmpeg 包，不怕工作量大”）

- 10-20 那条“原生包继续用 3.x 的构建”是错的：1.0.0 配 b1 的包，K90 第一次开始录制就崩（SIGSEGV，`libapp.so` 里对空指针偏移 0x10 的读）。
- 根因：0.11.2 把全局回调的参数改了，函数名没变。`ffmpeg_kit_config_enable_log_callback`、`..._enable_statistics_callback` 在 0.6.2 的绑定里收 `FFmpegKitLogCallback`（会话句柄、日志、user_data），1.0.0 收 `FFmpegKitGlobalLogCallback`（会话 ID、序号、级别、日志、user_data），日志的内存也改成 Dart 用 `ffmpeg_kit_free` 释放。0.11.1 的原生库按旧参数回调，Dart 按新参数读，错位后读到空指针。10-20 只比了两版绑定的函数名单，没比函数签名和回调类型，所以没看出来。
- 先确认根因再动手：官方 0.11.2 包（ffmpeg-kit-builders 的 v0.11.2 发布）配 1.0.0，K90 录了 16 分钟（972 秒，三段合并成一个 mp4）和一次 37 秒的开始、停止，都正常。
- 官方 0.11.2 包逐个核对（文件 SHA-256 和 GitHub 上的一致）：Linux、Windows、iOS、macOS 都是 n9.0.2，Linux 只要 glibc 2.28；Android 的 armeabi-v7a 写的是 “FFmpeg version 669f5ab”，不是 n9.0.2——上游 `scripts/variable.sh` 默认跟 `release/9.0` 分支，各 ABI 编的时候分支位置不同。所以不直接用官方包，五个平台都自己编，FFmpeg 固定在 n9.0.2 标签（946fcce07）。
- 怎么编（`tools/ffmpeg_kit/rebuild/`，Z04 写了用法）：
  - ffmpeg-kit-builders 用 1.0.0 对应的提交 fac2076（标签 v0.11.2-android），打 `builders.patch`：FFmpeg 固定 n9.0.2；git 克隆失败后每次重试重新查引用（上游 `retry_git_or_die` 只查一次，第一次网络失败后 50 次重试都拿着空命令空转）；镜像改用阿里云源（境外源超时，`dnf update` 失败）。
  - Android、Linux、Windows 在上游的 manylinux_2_28 镜像里编（主机网络；容器自己的网络访问 GitHub 时断时续）。依赖全部从源码编（`--build-deps`/`--deps`；上游 CI 是从它自己的 release 下载，不加时缺 jsoncpp，FFmpegKit 链接失败）。Android：NDK 29.0.14206865（clang 21）、API 26，AAR 用上游的 `build_aar.sh` 打（它把找不到 Maven 账号的提示拼进 Gradle 命令，本地打包时给占位值）。Linux：GCC 14（gcc-toolset-14）。Windows：xPack MinGW-w64 GCC 15.2.0。`sudo` 会把 PATH 换成 secure_path，找不到 `/usr/local/bin` 的 automake 1.19，所以以 root 直接跑。
  - iOS、macOS：`.github/workflows/ffmpeg-kit-apple.yml`（macos-14，同一份脚本和选项）。第一次跑编译成功，自己的检查失败：`strings | grep -m1` 在 pipefail 下 grep 先退出、strings 被截断，整条管道算失败（日志里已经找到 n9.0.2）；改成先写文件再找。
- 检查（`tools/ffmpeg_kit/rebuild/check.sh`，拿官方包试过，能查出 armeabi-v7a 的问题）：每个二进制带 n9.0.2；Android 三个 ABI、已 strip、64 位的 LOAD 16 KiB 对齐；Linux 只依赖系统库、glibc 最高 2.28；Windows 只导入系统 DLL 和 UCRT。和官方包比：FFmpeg 的 `--enable`/`--disable` 选项完全相同，Android、Linux、Windows 的依赖表相同，大小相差不到 0.1%；Windows 多导出一个测试函数 `ffmpeg_kit_test_emit_unattributed_log`（fac2076 比官方 Windows 包晚），授权文件多了 jsoncpp、pthread-win32。
- iOS、macOS（工作流运行 39458124411）：iOS 是 arm64 真机加 arm64 模拟器，macOS 是 arm64 加 x86_64，最低系统都是 13.0，和官方一样。iOS 的二进制比官方大 3 MB、dSYM 只有 2.3 MB（官方 64 MB）：代码段和数据段和官方相差不到 32 KiB，差别是我们的 iOS 二进制留着调试映射（stabs，16 万条符号，官方 4 万），dSYM 里几乎没有 DWARF；macOS 两边一样（dSYM 都是 52 MB）。不影响使用，Xcode 打包应用时会剥掉嵌入框架的调试符号；苹果平台的录制本来就还没开。
- 实际加载：Linux（Python ctypes）和 Windows（PowerShell P/Invoke，在 PC 上）都报 FFmpeg n9.0.2、FFmpegKit 0.11.2、base；再用 `ffmpeg_kit_execute` 把 K90 的录像截 10 秒、原样封装，两边都输出 10.1 秒的 H.264 + AAC，完整解码无错。
- `tools/ffmpeg_kit/rebuild/build.sh` 从空目录跑了一遍三个平台（38 分钟，含建工具链镜像），`check.sh` 通过——脚本本身验证过。前两次没跑完：Gradle 下载插件、容器里下载 Android SDK 时 TLS 被断开，加了重试。
- K90（自编 AAR 的 profile 包，APK 里的 `libffmpegkit.so` 和 AAR 里的哈希一致）：斗鱼 24422 录 36 秒，停止后保存，完整解码无错；再录 6 分 6 秒跨过 5 分钟分段，两段合成一个 366 秒的 mp4，完整解码无错，时间戳没有超过 1 秒的断档；没有崩溃。
- 发布为内部预发布 `native-ffmpeg-9.0.2-b2`（五个文件的 GitHub 摘要和本地 SHA-256 一致），`tools/ffmpeg_kit/bundles.txt` 和根 `pubspec.yaml` 改指向它；`fetch.sh` 从发布页下载五个包，校验通过。

## 2026-10-20（5.4.5 发布前，用户：“工具链的版本，看一下有更新吗？”“先升级，再发 5.4.5”）

- `check_latest`：63 项，8 项落后，6 项查询失败（GitHub 匿名接口 403，pub.dev 握手失败）；用 `gh api` 和 pub.dev 接口补查：mpv 0.41.0、FFmpeg 9.0.2、Kotlin 2.4.21、yaml、pinyindart 都是最新。
- 升了：
  - Gradle 9.8.1 → 9.8.2（`gradle-wrapper.properties` 的 sha256 取自 services.gradle.org，和下载的包一致；本机 `GRADLE_USER_HOME=~/.gradle-purelive-v4`，wrapper 下载中断时把核对过的包放进 `wrapper/dists/gradle-9.8.2-all/5xecsnx1v1ypz0za8yyzm2yym/`）。
  - go_router 18.1.0、hive_ce 2.22.0、material_ui 1.7.0（10-15 留到发布后的那几项）。
  - tray_manager 0.7.0 → 0.8.0（随之 nativeapi 0.5.2）：托盘图标的尺寸改用 nativeapi 自己的 `Size`，应用直接依赖 `nativeapi: ^0.5.2`；Windows 的 `getBounds()` 改成逻辑像素，我们没用托盘的位置。
  - open_filex 4.7.0 → 5.0.0：iOS 最低 13（我们 15），加了 Swift Package Manager 支持（我们的 iOS 用 SPM）。
  - ffmpeg_kit_extended_flutter 0.6.2 → 1.0.0：构建钩子把原生接口锁到 0.11.2（0.6.2 是 0.11.1）；两版生成的 FFI 绑定逐个比对，1.0.0 只多 FFplay 的 `ffplay_kit_copy_frame`、`ffplay_kit_get_frame_buffer_size`（`@ffi.Native`，调用时才找，录制不用），当时据此判断原生包不用换——判断错了，第一次录制就崩，见 10-21 那条（包按 0.11.2 重编，`native-ffmpeg-9.0.2-b2`）；钩子照旧读 `ffmpeg_kit_extended_config` 的本地包。
  - media_kit 上游 6b188ae → 83b7ca6：上游把 Android 的 libmpv 换成 v1.3.1，我们只有 x86 用上游的包，跟着换（sha256 下载核对一致）；上游新加的鸿蒙（OHOS）构建没有带过来（不发鸿蒙版）。
- 没升：screen_retriever 0.3.0——window_manager 0.5.2（最新）要求 `screen_retriever ^0.2.2`，解析不了；等 window_manager 跟上再升。0.3.0 的显示器 ID 每次启动都变，到时“记住小窗位置”的显示器判断要改用名称加位置。
- 验证：`flutter analyze` 通过；Android profile 构建通过（Gradle 9.8.2，`libffmpegkit.so`、`libmpv.so` 都在，原生库和 5.4.4 的测试包逐个比过）。

## 2026-10-14

- `GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart`：Flutter 3.47.7、Kotlin 2.4.21、sqlite3 3.7.1、hive_ce 2.21.0、test 1.33.0、media_kit 上游（libmpv android 1.3.0）、tray_manager 0.8.0、screen_retriever 0.3.0 有新版。
- 升了：Flutter 3.47.6 → 3.47.7（Dart 还是 3.13.5）；Kotlin 2.4.20 → 2.4.21：AGP 9.4.1 自带 Kotlin 2.4.20，`android.builtInKotlin=true` 下改用较新的版本要在 `apps/pure_live/android/settings.gradle.kts` 声明 `org.jetbrains.kotlin.android` 2.4.21（`apply false`），构建缓存里出现 `kotlin-compiler-embeddable/2.4.21`；sqlite3 ^3.7.1、hive_ce ^2.21.0（live_store）；全部成员 `test: ^1.33.0`。
- `test_api` 的覆盖从 0.7.14 改成 0.7.15：test 1.33.0 和 test_core 0.6.21 锁死 0.7.15，第一次门禁纯 Dart 成员的 `dart test` 编译失败（`Suite`、`MessageType` 找不到）——pub get 时覆盖强行用了 0.7.14 没报错，根因在这里；3.47.7 的 flutter_test 还是锁 0.7.12，换成 0.7.15 后 `flutter test` 照常。
- 验证：`flutter build apk --profile --target-platform android-arm64` 通过（146.7 MB）；`tools/gate/gate.sh --all` 通过。
- media_kit 上游 803c4a2 → 6b188ae：上游只改了 `native_bundles.json` 里 Predidit 的 libmpv 包到 v1.3.0；我们的 arm64、arm、x86_64 早就换成自己编的 mpv 0.41.0 + FFmpeg 9.0.2，所以只有 x86 一项跟着换（SHA-256 下载核对过，和上游一致），K90 用的 arm64 不变，不用真机复测。
- 没升：tray_manager 0.8.0、screen_retriever 0.3.0（桌面，现在只做 Android）。
- 下次：2026-11 上旬。

## 2026-10-08

- `GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart`：59 项，8 项落后，查询全部成功。
- 升了 6 个 pub 包（都在原约束内，只改 `pubspec.lock`）：url_launcher 6.3.2 → 6.3.3、drift 2.35.1 → 2.35.2、connectivity_plus 7.3.1 → 7.3.2、hive_ce 2.20.1 → 2.20.2、share_plus 13.3.0 → 13.3.1、material_ui 1.5.0 → 1.6.0。`tools/gate/gate.sh --all` 通过（14 个成员）。
- 没升：Flutter 3.47.5 → 3.47.6、Gradle 9.8.0 → 9.8.1（工具链，要换本机 SDK；当时有多个代理在用同一个 SDK 跑测试，下次一并升，改 `toolchain.env` 后跑门禁和一次 APK 构建）。
- 工具链（同日第二轮）：Flutter 3.47.5 → 3.47.6（Dart 3.13.5）、Gradle 9.8.0 → 9.8.1（`gradle-wrapper.properties` 的 sha256 取自 `services.gradle.org`，和本机下载的包一致）；`toolchain.env` 新增 `ANDROID_PLATFORM_TOOLS=37.0.1`、`ANDROID_CMDLINE_TOOLS=23.0`、`ANDROID_CMAKE_VERSION=4.1.2`，`check_latest` 也查这三项（14 项、落后 0）。AGP 9.4.1、Kotlin 2.4.20、JDK 27（本机 27.0.0+35）、compileSdk 37.2、build-tools 37.0.0、NDK 30.0.16248370 本来就是最新。
- 查出的偏差（根因）：`toolchain.env` 写着 NDK 30.0、compileSdk 37.2，但 `app/build.gradle.kts` 是 `compileSdk = 37`、`ndkVersion = flutter.ndkVersion`（Flutter 3.47 默认 28.2.13676358），插件模块用 AGP 默认的 NDK 和 CMake 3.22.1——上次构建日志里 376 处 `ndk/28.2`、144 处 `cmake/3.22.1`。改成 `android/build.gradle.kts` 读 `toolchain.env`，给 app 和全部插件模块设 `compileSdk` 37 + `compileSdkMinor` 2、`buildToolsVersion`、`ndkVersion`，有 C/C++ 的插件（`jni`、`cnativeapi`、`ffmpeg_kit_extended_flutter`）设 CMake 4.1.2 并加 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`（`ffmpeg_kit_extended_flutter` 要求 CMake 3.4.1，CMake 4 不接受低于 3.5）；顺带把已弃用的 `BaseExtension` 换成 `CommonExtension`。
- `test_api 0.7.14` 的覆盖仍然需要（3.47.6 的 flutter_test 还是锁 0.7.12），只改了注释里的版本。
- 验证：`flutter build apk --release --target-platform android-arm64` 通过（125.4 MB，lint 通过），日志里只有 Gradle 9.8.1、`platforms/android-37.2`、`build-tools/37.0.0`、`ndk/30.0.16248370`、`cmake/4.1.2`；`tools/gate/gate.sh --all` 通过。
- 下次：2026-11 上旬。

## 2026-10-15（5.1.0 稳定版发布前）

- `check_latest`：63 项，落后 6 项，4 项查询失败（GitHub API 限流 403：mpv、FFmpeg、media_kit、Kotlin，和 10-14 那轮一样，当时是最新）。
- 当场升级：`http2` 2.3.1 → 3.1.0（E03.20 新加的依赖，应当用最新），`live_net` 测试通过。
- 留到发布之后：`go_router` 18.0.2 → 18.1.0、`hive_ce` 2.21.0 → 2.22.0、`material_ui` 1.6.0 → 1.7.0、`tray_manager` 0.7.0 → 0.8.0、`screen_retriever` 0.2.2 → 0.3.0。原因：都是 5 天内的新版本，路由、存储和桌面托盘牵动面大，稳定版发布前不换；发布后单独升级、跑门禁和快速测试。
- 下次：5.1.0 发布后（上面 5 项），然后 2026-11 上旬。
