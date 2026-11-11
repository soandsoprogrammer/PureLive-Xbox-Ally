# H02.2 任务书

先读 AGENTS、PROCESS 第 5/8/14 节、ENGINEERING 和本目录 README。

范围：recording_platform.dart 的平台能力判断、录制接线回归、隔离 Apple native smoke 入口与正常 Apple 工作流的模拟器核验。保持所有已支持端和无内核端行为。先记录同等原行为的 RED；再修正 iOS/macOS 注入。测试不联网、不新增短定时器。

验证分开记录：能力与接线测试、FFmpeg 原生运行、包内框架和签名检查、原自签设备的录制与导出。前几项不能替代后者，未复测时 #42 保持开放。最终冻结新源，完整 all/14 后同源十包重建。
