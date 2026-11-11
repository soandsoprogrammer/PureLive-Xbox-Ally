# Y01.28 验证结果

5.4.17同源十包与11项哈希及匿名访问通过，PR合并、#53/#58回复关闭；新库更新JSON和记录独立完整门禁，旧库相同六项历史失败的本版例外等待授权，未同步旧远端，发布收尾不记为全部完成。

[完整证据与范围](../../Y03-发布说明和README/releases/v5.4.17.md)。源码、定向回归、全量门禁、构建、原生交互和原设备验收分开记录，仅计入实际已验证范围。


## 无账号隔离截图

[windows-inline](verify/windows-inline.jpg)；[windows-fullscreen](verify/windows-fullscreen.jpg)；[linux-home](verify/linux-home.jpg)；[macos-home](verify/macos-home.jpg)；[macos-covered](verify/macos-covered.jpg)。真实K90截图仅本地保存。


## 2026-10-26 发布期间原机确认

原报告者随后确认实际运行一直是5.4.5，覆盖未替换，重新安装新版后亮度和音量手势恢复；按原机确认回复关闭#41。新版本的精确构建号未提供，不写成确定5.4.17构建的验收，覆盖未生效原因未知。证据：https://github.com/wzgrx/PureLive/issues/41#issuecomment-6402728137。此前680字节三行日志缺少attached与旧包身份吻合；没有新增手势代码修复。


## 5.4.17 旧库授权后收尾

5.4.17同源十包及11项哈希、匿名访问、PR合并和#53/#58回复关闭完成；新库更新JSON已通过独立完整all/14发布。旧库取得本版单次授权D-064后仅同步两个已校验JSON，提交143242daaf7d800ebc9742c25e87e5d5869bb2b8；记录收尾再次完整门禁后推送，更新通道及最终远端留独立回执。

此前“待授权”段落是当时状态，由本节更新；未将上版例外复用为本版授权。
