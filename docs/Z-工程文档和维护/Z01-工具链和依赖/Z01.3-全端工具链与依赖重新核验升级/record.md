# Z01.3 记录

## 2026-10-26 清点

已保存初始源码 3a8b1e914、官方版本查询、pub outdated、Windows 实例和实际 CMake 选择、本机 Flutter/JDK/Gradle/Clang。独立证据目录 outputs/purelive-reassessment-20261026 不提交用户数据。旧候选未发布。

检查器只核对 JDK feature release，漏掉补丁升级；Android 包用数字路径判断稳定性而没有读取 channelRef；查询失败不导致默认退出非零。Apple 工作流固定寻找 Xcode_26，Windows 实际 CMake 来自 Visual Studio 自带目录而非 PATH。下一步补齐这些缺口并验证具体升级。

## 升级与定向验证

本机 WSL 采用独立 Temurin 27.0.1.0.2+1 与 Python 3.15.2；Windows 独立安装 Python 3.15.2、Inno 7.1.0、独立 CMake 4.4.4，原工具保留。Python 3.15.2 为 2026-10-25 官方维护发布，Windows 安装包 SHA-256 与 PSF 签名核对；WSL 官方源码 SHA-256 核对后编译，ssl/sqlite3/bz2/lzma/ctypes/venv/tomllib 导入通过。Visual Studio 18.11.2 已是官方 stable channel 当前版，Flutter 使用其附带 CMake 4.3.1-msvc1。

10 个直接依赖升级，锁文件共 48 项变化；screen_retriever 0.3 正式迁移、窗口位置快照及时释放原生句柄、不再持久化进程内 ID；window_manager 从官方发布档案引入并保留 MIT 许可，仅迁移显示器约束和工具函数。Android/Windows/Linux/macOS 生成注册清单删除旧 screen_retriever 插件。未更新原生媒体库 ABI。

检查器 Android 预发布选择在旧实现失败（误选 31.0.9，正确稳定值 30.0.1），修正后 8 项通过；增加完整 JDK、Dart、Xcode、CocoaPods、桌面工具与 Python 查询，未知查询不再成功退出。实际查询 72 项无落后、无失败。5 个传递包 cli_util、coverage、cross_file、material_color_utilities、package_config 被上游约束，保留解析器可用的最高版本，无过期/撤回/安全公告标记。

14 个成员静态分析全部通过，53 项桌面/小窗回归通过。Inno 版本探针用新 7.1.0 成功、原 6 拒绝，产物关闭，不执行安装。曾误用仓库根 dart analyze 包含历史 fixtures 和独立 third_party 测试产生 157 项诊断；保留原日志，之后按真正工作区成员检查，没有修改或掩盖历史样本。

下一步：冻结此阶段源码运行完整门禁，继续全部 issue 的独立复核；新工具链的正式跨平台构建和最终包原生验收尚未完成，当前不发布、不关闭未验证问题。

## 首轮完整门禁与本机实际版本

首轮 all/14 源码指纹一致，所有步骤除 live_danmaku 一项耗时断言通过：`/加.*群/` 在并发测试中被 2 ms wall-clock 预算判为 tooSlow。保留失败日志；未改阈值或跳过测试。随后按原命令独立重跑整个 live_danmaku，1678 项全部通过。最终推送仍必须有完整 all/14 成功，不能用单项重跑替代。

另发现 Flutter 的 jdk-dir 优先于 JAVA_HOME，旧共享配置仍指向旧 JDK。本机创建独立 XDG_CONFIG_HOME，保留共享设置；flutter doctor 实际 Java 路径和版本确认使用 Temurin 27.0.1.0.2+1。doctor 的 Android license status unknown 需继续检查，不记为全部工具链通过。跨平台原生构建开始，结果另记。

## 原生编译与额外工具核验

7d17e6213 源码下 Android arm64 profile、Linux release、Windows release 均编译成功；Windows 用 Inno 7.1.0 生成安装包和便携包。它们是工具升级阶段的验证产物，不是后续修复后的最终候选，也没有公开发布。Android Gradle 输出确认 launcher/daemon 都使用新 Temurin。

cmdline-tools 23.0 实际安装在 SDK 的 latest 子目录，已纠正项目 PATH。它的 sdkmanager 兼容脚本转发到独立 Android CLI，后者另有版本更新；按官方更新命令升级到 1.1.16717390，在项目 XDG 安装中核对实际版本，保留原 SDK launcher。原 launcher 文件哈希没有变化，真实版本是其加载的嵌入安装，不能以外层文件哈希猜版本。检查器补入官方 Android CLI release notes。Flutter doctor 的旧 license 探测仍与新 CLI 不兼容；实际 Gradle 构建通过，不把 doctor 的 unknown 冒充已通过。

Apple 工作流增加官方 setup-python v7.1.0 固定提交，并从 toolchain.env 选择 Python 3.15.2；helper 核对实际 Python。Xcode 27.1/CocoaPods 1.17.0/Python 3.15.2 的云端构建仍待最终完整门禁后运行。

## 正式编译器与最终工具清单

发现系统的 Clang 23.1.5 是开发快照（++20261020），并非官方正式发布。已另装 LLVM 官方最新正式版23.1.4，核对GitHub发布档案SHA-256，实际C++编译和运行通过；系统原快照保留，项目CC/CXX和PATH指定独立正式版。最终Linux包将清理构建缓存的影响（保留旧构建目录）并核对CMake选中的编译器。Apple/Windows仍分别使用固定Xcode/Visual Studio的编译器，不混用LinuxClang。

检查器补入Clang与vendored window_manager的官方发布基线，最终75项全部当前、查询失败0。官方Actions版本核对：checkout7.0.1、upload-artifact7.0.2、setup-python7.1.0、flutter-action2.23.0。原生播放器预构建也重新查询供应方：Darwin0.6.8、Windows202609151348、Android1.3.1、Linux20260810均仍是其最新发布；本项目Android/Linux x64使用自建mpv0.41.0/FFmpeg9.0.2。供应方Windows为FFmpeg master、Apple版本未声明，不能把所有平台运行库都写成相同FFmpeg版本。

45210494b的完整门禁只有应用翻译集合检查失败：新增三个文案已在中英添加，但其余13种语言尚缺。全部修复行为测试及其他13成员通过，早前正则耗时偶发失败本轮未重现。现已补齐15种语言，i18n完整专项通过；不放宽或跳过检查，继续对新固定提交跑完整all/14。

Apple云端实际验证补充：运行40347123328在setup-python阶段失败，actions/python-versions尚无macOS27 ARM64的3.15.2发行包。Python官方已提供universal2安装器，改用其发布页SHA-256固定的官方pkg，安装前验证摘要和签名，安装后验证解释器版本并配置官方证书；仅允许GitHub临时macOS主机执行。没有降级Python，也没有将尚未编译的Apple包算作通过。来源：https://www.python.org/downloads/release/python-3152/ 、https://docs.python.org/3/using/mac.html 。全部Apple工作流使用同一个引导脚本。

Apple运行40355411455已实际通过官方Python3.15.2安装、Xcode27.1/CocoaPods1.17.0核对及macOS、iOS正式包编译。后续iOS模拟器构建、启动、安装和应用launch也完成；截图返回NSPOSIXErrorDomain22，原因是最新iOS27.1的iPhone Duo包含两个显示面板，旧命令未选择面板。日志列出display3为LCD-1、display1为primary LCD，现两处截图都显式指定display1。该次后续原生录制探针和Mac精确包复启作业被跳过，不计作通过；最终新源码需重建重验。主屏截图不外推双屏全部状态验收。


## 5.4.18 最终交付

5.4.18实现、分层验证及发布收尾见交付记录；未覆盖的原设备场景不外推。

[交付与验证范围](../../../Y-发布和运营/Y03-发布说明和README/releases/v5.4.18.md)。此前候选待验状态由本节更新；原始失败证据保留。
