# J05.2 记录

## 根因与修复

UDP 本地发送/接收失败可异步出现在 socket Stream；同步捕获 send 的异常不足以处理它。新增 onError 在第一次 announce 前注册，不停止 HTTP 服务或 mDNS，不改变配对码和二维码状态。

## 回归证据

- 既有服务及同步页面回归中的 17 项失败具有相同的未处理广播错误根因。
- 保留测试 socket 接口、仅移除 handler：两项可控发送/接收错误测试均真实失败。
- 恢复 handler：完整 services_test.dart 与 remote_sync_test.dart 43/43 通过，包括上述 17 项用例和新增的错误后关闭对照。
- 测试实际请求 loopback HTTP 状态接口、注入 mDNS 对端、检查配对码/二维码及 stop 清理。
- 最终格式与定向分析通过，独立代码及回归审查未发现阻断意见。

## 复核命令与边界

按仓库固定 Flutter 3.47.8 / Dart 3.13.7 工具链运行：

```sh
cd apps/pure_live
flutter test test/services_test.dart test/features/remote_receiver/remote_sync_test.dart
dart analyze --fatal-infos
# 回到仓库根目录后
bash tools/gate/gate.sh --all
```

包含 G02.9/J05.2 的修复代码已通过完整 14 成员门禁；发布前仍须核对最终候选树与远端一致性。没有跳过原生 hook 或真实既有测试，没有修改网络权限、版本或用户数据。局域网原设备互发现、后台和其他平台验收仍以各自清单为准。

## 合并结果

2026-10-27：[PR #76](https://github.com/wzgrx/PureLive/pull/76) 已合并为 `79acc2e4cd49fef0e9b5ecd7decf4eb02c93046f`。远端提交树与公开候选 `8cc473f805a0b491d27f55c4e6eaffcf3e5dd403` 一致。完整门禁之后只有公开任务文档精简，生产代码、测试、依赖和构建/门禁输入逐字节不变，文档及结构检查重新通过；没有将旧完整测试记录写成在新文档树上重跑。原机验收与新版本发布仍未完成。
