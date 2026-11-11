# V02.30 issue #26：复用 HTTP2 通道验证 Windows Kick

来源：[issue #26](https://github.com/wzgrx/PureLive/issues/26)。基线 d94f1c934（5.4.9 发布后），分支 ai/V02.26。

## 根因与范围

Kick API、播放与弹幕已有实现，但 bootstrap 以 AndroidNativeHttp 的可用性间接控制 HTTP2 客户端的创建，Windows 因此没有平台入口。

## 方案与既有行为

核对 HTTP2 客户端及代理在 Windows 的实际能力，先验证列表、搜索、房间、媒体字节、播放、弹幕和恢复，再决定是否开放 Windows；不单靠移除条件声明支持。官方文档 https://docs.kick.com/ 只作公开接口能力参考，不假定其中包含匿名网页取流。

小范围缺陷修正沿用现有界面、入口与组件，不增加新的设置或重画页面。以 3.x 行为和本次实际反馈为基线。

## 验证边界

实际 Windows 隔离实例验证；不操作 D:\Soft 下正式安装，不使用账号或付费能力。无法验证的保持开放并记录具体限制。

代码回归、构建、实际平台、设备和已发布状态分开记录；未经确认不关闭问题。
