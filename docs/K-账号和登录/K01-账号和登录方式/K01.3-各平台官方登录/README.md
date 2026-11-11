# K01.3 各平台官方登录：在应用里打开平台自己的登录页，登录后自动保存

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：用户 2026-10-16：“增加功能，看每个平台增加类似哔哩哔哩这种官方登录的功能”
- 相关：K01.1（账号和登录，哔哩哔哩扫码和网页登录）；A12.1、A12.2（账号页和 Cookie 页）；O03.1（应用内浏览器）

## 用户看到的

- 斗鱼、虎牙、抖音、快手、YY、网易CC、Twitch、SOOP 的账号页（设置 → 平台显示与授权 → 平台账号 → 点平台）最上面多了一个“用××官方登录”按钮，下面一行说明。
- 点进去是平台自己的登录页（应用内浏览器），用平台 App 扫码、短信验证码或密码登录：
  - 一出现登录凭据（各平台的登录 Cookie）就自动回到账号页，按粘贴 Cookie 的规则保存：能在线核验的（抖音）先问平台是谁登录的，没登录的不存；斗鱼的 LTP0、dy_did 自动填进续期一栏。
  - 没自动回来时（例如网易CC 没有可靠的标志 Cookie）点右上角“已登录，保存”。
- 每次打开前清掉应用内浏览器里这个平台的旧 Cookie，退出过的账号不会被直接带回来。
- 没有应用内浏览器的设备（Linux、没装 WebView2 的 Windows）不显示这个按钮，仍可粘贴 Cookie；哔哩哔哩保持原来的扫码和网页登录。

## 各平台的登录页（2026-10-16 在 K90 的应用内浏览器里逐个打开看过）

| 平台 | 登录页 | 方式 | 自动识别登录的 Cookie |
|---|---|---|---|
| 斗鱼 | `passport.douyu.com/h5/loginActivity`（手机版） | 手机号加密码、短信（“手机快捷登录”）、昵称登录 | `acf_auth`、`dy_auth` |
| 虎牙 | `www.huya.com`（电脑版，整页缩放） | 点右上角“登录”：扫码、密码、短信、微信、QQ、微博 | `udb_biztoken`、`yyuid` |
| 抖音 | `live.douyin.com`（电脑版，整页缩放） | 点右上角“登录”：验证码、密码 | `sessionid` |
| 快手 | `passport.kuaishou.com/pc/account/login/?sid=kuaishou.live.web`（电脑版，整页缩放） | 验证码、密码（表单直接显示） | `kuaishou.live.web_st`、`userId` |
| YY | `aq.yy.com`（YY 安全中心） | 账号密码（页面小，可以放大） | `udb_biztoken`、`yyuid` |
| 网易CC | `cc.163.com`（电脑版，整页缩放） | 点“登录”：短信、邮箱密码 | 没有，用“已登录，保存” |
| Twitch | `www.twitch.tv/login` | 账号密码（国内网络要代理才能打开） | `auth-token` |
| SOOP | `login.sooplive.co.kr/afreeca/login.php` | ID 密码、第三方 | `AuthTicket` |

为什么这样选：

- 手机上自己扫不了自己屏幕上的二维码，所以优先用有短信、密码的手机版登录页（斗鱼、YY、Twitch、SOOP）。
- 虎牙、快手的手机网页只引导下载 App，没有登录，所以用电脑版。`www.yy.com` 拒绝应用内浏览器（436），所以 YY 走安全中心。
- 电脑版网页虽然用了电脑浏览器的名字，仍按手机宽度排版，登录按钮跑到屏幕外。现在加载后把页面按 1280 宽排版、整页缩放进屏幕，仍可以两指放大。
- 试过用脚本自动点“登录”，抖音、虎牙、网易CC 都不认脚本的点击（手指点可以），所以改成提示“点页面右上角的登录”。

## 代码

- `apps/pure_live/lib/features/account/platform_web_login.dart`：`platformWebLogins`（各平台的登录页、读 Cookie 的地址、标志 Cookie、是否电脑版）、`PlatformWebLoginView`（每个页面加载和每 1.5 秒检查一次 Cookie）、`desktopFitScript`、`clearWebCookies`、`siteDomain`。
- `cookie_editor.dart` 的 `onWebLogin`：按钮、取回的 Cookie 填进输入框后走原来的保存。`platform_cookie_view.dart`、`douyu_cookie_view.dart` 接上。

## 测试

- `test/features/account/platform_web_login_test.dart`：每个有账号入口的平台（哔哩哔哩除外）都有官方登录页、地址是 https、读 Cookie 的地址同站；标志 Cookie 的判断；清 Cookie 用整站域名；没有浏览器时不显示。
- `test/features/account/account_page_test.dart`：快手取回即存、离开不存；抖音先核验（没登录的不存、登录的显示名字）；斗鱼取回的 LTP0、dy_did 填进续期；哔哩哔哩没有这个按钮；没有浏览器时没有按钮。

## 没验证的

- 真正登录一遍：要各平台的真实账号，维护者这边没有，需要用户在 K90 上用自己的账号走一次（登录后看账号页的状态、进对应平台的直播间看画质和弹幕身份）。
