# J04.2 应用运行时的定时 WebDAV 备份

- 状态：以登记表为准
- 类型：功能
- 来源：V01.9（D-058）
- 相关：J04 WebDAV、J03 备份格式、A12.7 设置界面

## 做什么

在应用运行时，按用户设置的间隔把备份上传到当前 WebDAV 服务器的 `purelive` 文件夹（可改），保留最近 N 份自动备份，成功后弹应用内通知。

不做的：Android WorkManager 后台、自动下载恢复、修改手动上传行为。

## 设计

### 设置

`packages/live_store/lib/src/settings/settings.dart`，`section: 'backup'`，随备份同步：

| 键 | 默认 | 范围 |
|---|---|---|
| `webdavAutoBackupEnabled` | `false` | — |
| `webdavAutoBackupHours` | `24` | 1..168 |
| `webdavAutoBackupScope` | `'all'` | `all` / `follows` |
| `webdavAutoBackupFolder` | `'purelive'` | 安全相对路径 |
| `webdavAutoBackupKeep` | `7` | 1..100 |
| `webdavAutoBackupIncludeAccounts` | `false` | — |

### 文件名和保留

- 全部：`purelive_auto_YYYY-MM-DDTHH_MM_SS.txt`
- 仅关注：`purelive_favorites_auto_YYYY-MM-DDTHH_MM_SS.txt`
- 保留只匹配严格正则 `^purelive(?:_favorites)?_auto_<时间>\.txt$`，按文件名时间从新到旧保留 N 份，手动备份不匹配。

### 目录

`WebDavClient.ensureFolder` 从服务器根目录逐层 `MKCOL`，接受 `405`/`409`（已存在/父目录已建），最后 `PROPFIND` depth 0 确认。远程文件夹是设置里的相对路径，不跟随 WebDAV 页当前浏览目录。

### 调度

- `WebDavAutoBackupService.runIfDue()`：读设置和 meta，判断到期，创建目录、导出、PUT、写 meta、清理旧文件。
- `WebDavAutoBackupScheduler`：`AppStartup` 只在主窗口启动；启动、回前台、设置变化时检查；运行中每 15 分钟检查一次；单飞；`paused`/`detached` 时停表。
- 失败退避：15 分钟、30 分钟、1 小时、2 小时、4 小时、6 小时，最大不超过配置间隔。
- meta：`webdav.auto.lastSuccess`、`lastAttempt`、`failures`、`lastTarget`。

### 通知

成功：`webdav_auto_backup_success`，每次自动上传后弹应用内通知。
失败：`webdav_auto_backup_failed`，本次运行第一次失败弹一次，之后只写日志；不自动恢复。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_store/lib/src/settings/settings.dart` | 6 个设置 |
| `apps/pure_live/lib/shared/backup/backup_files.dart` | `autoBackupFileName`、`isAutoBackupFile` |
| `apps/pure_live/lib/shared/backup/backup_data.dart` | `exportBackup(includeSensitiveData:)` |
| `apps/pure_live/lib/features/web_dav/web_dav_client.dart` | `_send(accept:)`、`ensureFolder` |
| `apps/pure_live/lib/features/web_dav/web_dav_auto_backup.dart` | 目录解析、到期/退避、上传、保留、meta |
| `apps/pure_live/lib/features/web_dav/web_dav_auto_backup_scheduler.dart` | 前台定时、生命周期、通知 |
| `apps/pure_live/lib/app/startup.dart` | 主窗口启动和释放 |

## 测试

- `apps/pure_live/test/features/web_dav/web_dav_auto_backup_test.dart`
- `apps/pure_live/test/features/web_dav/web_dav_auto_backup_scheduler_test.dart`
- `apps/pure_live/test/features/web_dav/web_dav_page_test.dart`（对话框和 FakeDav MKCOL）
- `packages/live_store/test/settings_defaults_test.dart`

## 真机/桌面验证

1. 本机临时 WebDAV，目录设 `backup/purelive`，间隔 1 小时，启用；首次立即上传，逐层建目录，弹成功通知。
2. 手动“备份到当前目录”仍上传到当前目录，自动文件不受影响。
3. 预置多份自动文件和一份手动文件，上传后只删最旧的自动文件。
4. 密码错误：本次运行第一次失败弹一次原因，之后只日志；修正后恢复。
5. 退到后台不上传；回前台补跑。
6. Windows 第二窗口只出现一次 PUT。


## 5.4.15 发布后验证状态

已随PR #50合并PR #51并发布5.4.15；四项旧代码失败回归修正，相关服务和设置55项及完整all/14通过。混合类型按时间保留、仅清理直接子自动文件、隐藏窗口暂停已验证；真实供应商目录创建、上传、通知和清理仍待现场验证。

后续：在配置好的真实WebDAV供应商上验证目录创建、上传成功与失败通知、保留清理；不把本地模拟服务代替真实服务器验收。

历史审查中“尚未取得旧库例外”的时间点已结束，本次D-059已获单独授权；最终证据与范围见[本版验证记录](../../../Y-发布和运营/Y01-版本签名和发布/Y01.26-5.4.15全平台发布/verify.md)。
