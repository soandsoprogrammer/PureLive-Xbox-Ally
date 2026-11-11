# 47文件草稿取舍与5.4.26落地

草稿基线5.4.17，审查基线为5.4.25/master 248f9312；原47文件及未提交patch另有逐文件快照与SHA-256校验，原工作区保留。未提交内容没有逐行Git作者记录，目录名仅用于来源定位。

本次迁移：桌面恢复状态、首页滚动条、收藏分区图标和额外电视设置页。壁纸设计结合当前播放器重新实现；已在5.4.18及后续版本覆盖的设计继续沿用。原始设计不等于当前实现，未恢复旧阻塞队列、固定抢焦点计时器或宽泛iOS路径重写。

导航70项、电视50项、播放器127项及壁纸11项回归通过。桌面最大化/聚焦复位、收藏图标和有效鼠标滑块拖动保留修改前失败。完整门禁、最终包与原生范围见本任务记录及Y01.37；不把受控结果当原设备#33/#47/#49解决证据。

| 原草稿文件 | 原设计作用 | 当前处理 |
|---|---|---|
| `apps/pure_live/assets/translations/de.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/en.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/es.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/fr.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/id.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/it.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/ja.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/ko.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/pt.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/ru.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/th.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/tr.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/vi.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/zh.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/assets/translations/zh_Hant.json` | 新增导航标签与滚动隐藏四条文案 | 功能已有正式三项设置与文案；不恢复旧四个翻译键。 |
| `apps/pure_live/lib/app/desktop/desktop_window.dart` | 首帧后显示、1px顶层窗口尺寸扰动；补最大化/聚焦后的最小化状态恢复 | 迁移状态复位；保留5.4.25首帧与完整恢复方案。 |
| `apps/pure_live/lib/features/about/about_page.dart` | 关于页在电视外壳下使用统一标题 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/features/areas/areas_page.dart` | 普通分区的平台标签加入logo | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/features/areas/favorite_areas_view.dart` | 收藏分区的平台标签也加入logo | 采用平台图标设计，复用现有PlatformLogo。 |
| `apps/pure_live/lib/features/auth/auth_page.dart` | 账户页AppBar改用可被电视替换的公共页头 | 采用统一设置页头；与TV路由包装一起验证。 |
| `apps/pure_live/lib/features/home/home_page.dart` | 读取导航标签和底栏自动隐藏开关 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/features/home/home_views.dart` | 底栏动画隐藏、标签隐藏、侧栏共享显式滚动控制器 | 迁移独立共享滚动控制器；原隐藏、标签等现有行为保留。 |
| `apps/pure_live/lib/features/iptv/iptv_page.dart` | IPTV接入公共设置页头 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/features/live_play/live_play_page.dart` | 将引擎配置key改为公共playerConfigKey | 保留当前配置与会话所有权；不为旧电视复用搬动公共key。 |
| `apps/pure_live/lib/features/live_play/local_interaction/local_interaction_settings_page.dart` | 本地互动设置接入公共页头 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/features/live_play/logic/player_standby.dart` | 提取九字段共享播放器配置key | 不恢复旧电视复用实验的配套key重构。 |
| `apps/pure_live/lib/features/live_play/player/player_view.dart` | 桌面鼠标中键切换全屏 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/features/settings/settings_catalog.dart` | 新增标签与隐藏两个设置入口 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/features/settings/settings_page.dart` | 窄屏独立设置页改在内容Navigator内即时切换 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/features/settings/settings_tiles.dart` | 设置AppBar读取可替换的电视页头 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/routes/tv_router.dart` | 九个根路由包入TvHostedSettingsPage | 补齐账户、WebDAV、同步三个设置根路由，不覆盖后续版本/历史路由。 |
| `apps/pure_live/lib/tv/home/tv_home_page.dart` | 启动后150/400/800/1500/2500ms五次尝试恢复焦点 | 保留现有焦点生命周期修复，不迁移五个固定抢焦点计时器。 |
| `apps/pure_live/lib/tv/room/tv_live_play_page.dart` | 同页换台复用会话、串行交接、退出后交给待机池 | 采用背景资源交接思路；不采用旧串行换房队列与待机池交接。 |
| `apps/pure_live/lib/tv/settings/tv_settings_catalog.dart` | 本地配置预览走单列电视公共外壳 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/tv/settings/tv_settings_section_page.dart` | 新建电视页壳并最多等待三秒获取首焦点 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/lib/tv/wallpaper/tv_wallpaper_layer.dart` | 进入直播时停止视频壁纸，退出重新打开 | 重新实现完整资源退役、合并意图、迟到循环隔离和超时禁用；增加独立控制器与回归。 |
| `apps/pure_live/test/features/settings/settings_page_test.dart` | 把根路由跳转断言改为原位页面和返回概览 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/test/features/settings/settings_scroll_position_test.dart` | 备份页面原位进入/返回保持概览滚动位置 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/test/features/settings/standalone_pane_test.dart` | 本地互动和日志原位进入/返回 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `apps/pure_live/windows/runner/flutter_window.cpp` | 取消首帧直接Show，五秒后兜底显示 | 沿用5.4.25恢复屏障和有限子窗口同步，不恢复旧顶层窗口定时方案。 |
| `packages/live_record/lib/src/storage.dart` | 任意旧iOS容器UUID前缀替换为当前容器 | 沿用现有窄范围旧iOS默认路径修复及其回归，不引入全局前缀改写或已删除API测试。 |
| `packages/live_store/lib/src/settings/settings.dart` | 新增homeNavLabels、homeBottomBarAutoHide并登记 | 保留正式设置键、默认值及手机/桌面分别控制的语义。 |
| `packages/live_ui/lib/src/icons/platform_logo.dart` | 新增按字号缩放并裁圆角的PlatformTabLogo | 复用现有PlatformLogo；本次收藏分区补齐图标，不增加重复辅助类。 |
| `packages/live_ui/lib/src/widgets/liquid_glass_bar.dart` | 新增showLabels控制玻璃底栏文字 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `packages/live_ui/lib/src/widgets/settings_page_frame.dart` | 增加SettingsPageChrome替换页头 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `packages/live_ui/lib/src/widgets/tab_label.dart` | 新增leading装饰图标 | 设计意图已在5.4.18及后续实现覆盖；保留当前组件、行为及更完整的测试。 |
| `packages/live_record/test/storage_test.dart` | 新增三项容器路径替换纯函数测试 | 沿用现有窄范围旧iOS默认路径修复及其回归，不引入全局前缀改写或已删除API测试。 |

更换壁纸先挂载新键控组件、后终结旧组件，新增回归确认旧清理未结束时曾分配第二实例。现保留离场清理所有权，并在当前帧终结组件树后应用背景启动意图；前台也等待离场背景的有界屏障。实际清理失败时背景保持禁用，成功才解除。
