# V03.7 5.4.18反馈与上游证据对照

## 范围与方案

核对Flutter焦点API、Windows引擎尺寸/白屏历史问题和本地固定SDK源码、iOS沙箱路径规则。原#33/#42/#47/#49继续按实际证据跟进，不把相似上游报告或模拟器当原机验收。

## 决策

按D-003由维护者选择建议A：复用当前组件、背景、设置、返回和窗口内全屏。新设置默认保持现状；本次授权来自用户明确要求解决并发布。没有取得新的旧库门禁例外。

## 搜索来源与可用边界

- [Flutter焦点说明](https://docs.flutter.dev/ui/interactivity/focus)：节点的真实焦点与焦点高亮模式需要分开。本应用电视绘制直接使用自有状态，不能据此直接全局强制traditional；须定位实际节点与重建。
- [焦点边界API](https://api.flutter.dev/flutter/widgets/TraversalEdgeBehavior.html)：方向边界可停止；用于核对路由内首项Up和滚动跟随，需本地回归。
- [Flutter Windows尺寸交换缺陷187922](https://github.com/flutter/flutter/issues/187922)及[修复187954](https://github.com/flutter/flutter/pull/187954)：历史上存在隐藏启动期间空帧尺寸交换，但必须先对照本地固定SDK是否已修正，不能直接当#47根因。
- [Impeller启动耗时191860](https://github.com/flutter/flutter/issues/191860)：耗时报告不等同白屏或尺寸错误；核对应用实际渲染器后再判断相关性。
- [Apple沙箱文件访问](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)：应从系统获取当前应用容器目录；不根据一条路径错误推断内核缺失或为全部平台重置目录。

原始GitHub issue/comments保存本地outputs/purelive-5.4.18，真实截图不提交到仓库。


## 新一轮精确窗口线索

GitHub搜索发现[Flutter194679](https://github.com/flutter/flutter/issues/194679)：快速最大化／还原、迟到帧与旧resize target相互作用，可能造成画面缩在左下角。固定SDK的OnWindowSizeChanged在surface_will_update=false时同样没有清理pending target。此为与#47图片较接近的候选机制，尚未在本应用或原笔记本复现；不复制未经本应用验证的抖动尺寸方案、不更换SDK，不关闭#47。后续需核对触发时是否快速最大化／还原，以及轻微调整窗口尺寸能否恢复。[188270](https://github.com/flutter/flutter/issues/188270)则针对新多窗口API的次级窗口，本应用原报告是主窗口，不混为一谈。


## 5.4.18 最终交付

5.4.18实现、分层验证及发布收尾见交付记录；未覆盖的原设备场景不外推。

[交付与验证范围](../../../Y-发布和运营/Y03-发布说明和README/releases/v5.4.18.md)。此前候选待验状态由本节更新；原始失败证据保留。
