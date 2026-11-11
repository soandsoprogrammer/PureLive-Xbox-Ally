# 修复记录

2026-10-31，基线62d2e949。#47显示位图与可点击坐标不一致、轻微改变尺寸即可恢复。原设备GTX760/混合DPI未在本机，不能把ANGLE上游个案当同一根因。

源码确认window_manager.waitUntilReadyToShow的callback类型是VoidCallback，调用时不await。旧DesktopShell传async闭包，恢复位置/最大化/显示/聚焦未完成就可能runApp。另一个原生首帧回调再次SW_SHOWNORMAL，会覆盖保存的最大化。现在依次await原生ready、完整恢复、Windows layoutReady，再允许runApp；正常显示由Dart单独负责，准备失败页仍保留原生显示兜底。

新增异步最大化屏障测试，旧回调行为失败，修复通过。Windows增加只作用于Flutter子窗口的启动期尺寸再同步：读取当前client bounds、宽度减1再精确恢复、ForceRedraw，不改变顶层窗口尺寸/焦点/最大化/DPI。思路参考rustdesk/rustdesk PR15717；没有照搬其架构。首帧后仅执行一次有效同步；无首帧时最多5次1秒间隔尝试，销毁时取消计时器和弱回调，防止持续界面抖动和过期回调。

原生构建、普通/最大化/全屏回归待补入5.4.25发布验收。#47继续保留原设备确认。


## 发布验收补记

代码PR [#119](https://github.com/wzgrx/PureLive/pull/119)已合并。构建源码`7c3136d04c96982be9b7252af985962b0829b314`，合并提交`a98239d167b4ae261d06b42677bfb2b9e1472173`。完整门禁、同源十包和原生范围详见verify.md及Y01.36。原设备验收仍保留开放。
