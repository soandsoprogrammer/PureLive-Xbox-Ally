# E03.20 记录

## 2026-10-15

两处都是 Kick 那边的变化，代码自 5.0.0 起没有改过。

### 1. API 不再接受 HTTP/1.1

- 现象：`stream/livestreams` 等接口回 403 `{"error":"Request blocked by security policy."}`，应用显示“需要登录账号 / 该平台数据已被风控隐藏”。
- 排查：同一个代理、同样的请求头，`curl --http2` 回 200，`curl --http1.1` 回 403；以前能用的 Android 系统 TLS（`HttpURLConnection`）只会 HTTP/1.1，所以也被拒。用 Dart 的 `http2` 包（dart:io 的 TLS）走 HTTP/2 回 200，说明只要换成 HTTP/2，不需要原生通道。
- 修改：`live_net` 新加 `Http2LiveHttp`（`lib/src/http2_http.dart`，依赖官方的 `http2` 3.1.0）：每次请求一个 HTTP/2 连接；走代理时先发 `CONNECT` 建隧道，再在同一个连接上做 TLS；跟随重定向、超时和取消照 `IoLiveHttp`。应用里 Kick 的 API 改用它（`bootstrap.dart`）；仍然只在 Android 上注册 Kick（播放和弹幕只在 Android 上验证过）。
- 测试：`packages/live_net/test/http2_http_test.dart` 4 个用例，在本机起 HTTP/2 服务（测试时用 openssl 临时生成证书，不提交私钥）和 CONNECT 代理：请求头和状态、经代理的隧道和 403 照常返回、不支持 HTTP/2 的服务器是协议错误而不是卡住、取消和超时。

### 2. 聊天的 Pusher 应用换了

- 现象：聊天连上就断，Pusher 回 `pusher:error 4001 "App key 32cbd69e4b950bf97679 not in this cluster"`。
- 排查：Kick 网页现在先请求 `web.kick.com/api/v1/realtime/channels/{id}/chat/connection`，默认给 Centrifugo；声明只接受 Pusher 时给 `app_key 34bf7a0ff419a2a775b9`、`cluster us2`。用新密钥订阅 `chatrooms.<id>.v2` 立刻收到聊天。
- 修改：`live_danmaku` 的 `KickDanmakuProtocol.endpoint` 换成新密钥，注释写明以后变了去哪里查。

### K90 复测

经代理：Kick 热门列表、封面、在线人数正常；进直播间画面出来，聊天和飞屏弹幕正常。

## 留下的问题

- 密钥写死在代码里，Kick 再换时要再改；巡检（E07）的 P13 弹幕会发现。以后可以改成连接前从上面的接口取。
- Windows、Linux 现在也能用这个 HTTP/2 通道，但 Kick 的播放没在桌面上验证，先不开。
