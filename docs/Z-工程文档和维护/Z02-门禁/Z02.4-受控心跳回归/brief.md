# Z02.4 Showroom 心跳回归使用受控时间

5.4.13 全量门禁中，旧测试依靠 20 毫秒心跳和 5 毫秒轮询回答 PING，负载下超过 1 秒静默窗口，错误触发重连。失败日志完整保留，不能盲目重跑作通过。

共享 LiveSocket 的三处 DateTime.now() 改为 clock.now()；默认 Clock 仍读取系统时间，不改周期、阈值、重连策略或平台协议。clock 1.1.2 已在现有锁文件中，不升级依赖。Showroom 测试用现有 fake_async 1.3.3 同步控制时钟、定时器和微任务，所有新增周期至少 1 秒。

验收：连续 7 秒逐 tick 回 ACK（超过两个静默窗口）不重连；手动 heartbeat 恰好多一个 PING；停止 ACK 后第 3 秒报告 disconnected，第 5 秒（单端点完整一轮退避 2 秒）关闭旧 socket 并重新 SUB，最后 close 无残留定时器。保留录制、握手和本地服务器等其他测试。

先跑 Showroom 文件、live_net 与 live_danmaku 全套、静态分析，再冻结源码执行完整 14 成员门禁。未通过不得提交、推送或构建发布候选。无设备操作或新 UI。
