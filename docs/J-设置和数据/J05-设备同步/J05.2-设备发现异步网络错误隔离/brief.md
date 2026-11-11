# J05.2 任务书

先读 AGENTS、PROCESS、ENGINEERING，以及 remote_sync_service.dart 和 services_test.dart。允许改设备同步服务错误监听、相关测试、本任务文档与登记表；禁止跳过测试、放开系统网络限制、改变版本或用户数据。

1. 可控 socket 在 send 返回成功后异步发出错误时，不向应用错误区泄漏。
2. 已启动后连续接收异步错误仍不终止 HTTP/mDNS；地址、配对码和二维码保持可用。
3. stop 继续关闭发现 socket、mDNS 与 HTTP，不留下定时器。
4. 保留真实服务测试；新增测试不用真实平台/广播网络，定时器至少一秒。
5. 取得红绿证据、独立审查和完整 --all 结果后才可推送/合并。真机局域网验收独立保留。
