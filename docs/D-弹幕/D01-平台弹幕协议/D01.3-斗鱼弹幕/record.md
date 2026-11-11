# D01.3 弹幕：斗鱼

- 日期：2026-09-29
- 目标：`packages/live_danmaku/lib/src/sites/douyu.dart`（`DouyuStt` 文本格式、`DouyuDanmakuProtocol` 编解码、`DouyuDanmakuConnection` 连接）
- 参数：`live_core` 的 `DouyuDanmakuArgs`（真实房间号，E01.2 由 `betard` 的 `room.room_id` 得到，靓号和别名已换成真实房间号），地址是 `DouyuApi.danmakuServer`
- 样本：
  - `fixtures/douyu/danmaku/S13-live`：真实录制（2026-09-27，房间 9999，约 30 s，185 帧：2 帧发出、183 帧收到），来自归档。收到的包里有 147 条 `chatmsg`、125 条 `dgb`、265 条 `uenter`，以及 `loginres`、`pingreq`、`ranklist`、`oni`、`configscreen` 等；没有醒目留言，也没有别的房间的聊天；
  - `fixtures/douyu/danmaku/S14-synthetic`：本模块补的合成帧（`cases.json`，17 组），覆盖录制里没有的醒目留言、语音醒目留言、过滤开关、别的房间、带转义的文字、坏包和截断；
  - 两个目录的 `expected.json` 都由 `fixtures/douyu/danmaku/legacy_expected.dart` 生成：它把 v3 `DouyuDanmaku` 的解码代码原样搬进独立程序，只把日志换成标准错误输出、回调换成列表，模型删到只剩字段。运行：`dart run fixtures/douyu/danmaku/legacy_expected.dart`（仓库根目录）。
- 参考：
  - v3：`legacy/lib/core/danmaku/douyu_danmaku.dart`、`core/common/web_socket_util.dart`、`core/site/douyu/douyu_site.dart`（`getDanmaku`）、`common/services/settings/danmaku_settings_controller.dart`（过滤开关）、测试 `test/douyu_danmaku_protocol_test.dart`（7 个用例）；
  - 归档 v4（`archive/v4`，6ba709135）的 `packages/live_danmaku/lib/src/sites/douyu.dart`、`codec/stt.dart` 和规格 `spec/sites/douyu.md` 第 7 节、回归条目 REG-DOUYU-017～021；
  - pure_live_TV `e1cca224` 的 `lib/platforms/douyu/douyu_danmaku.dart`（见“上游核对”）。

## 做法

- **连接用 D01.1 的 WebSocket 运行时**，平台只写四样，都照 v3：
  - 地址：只有 `wss://danmuproxy.douyu.com:8506` 一个，不带请求头和子协议，匿名；
  - 打开即就绪（v3 在 `onReady` 里先 `markConnected`、报 `onReady`，再发加入包），随后发 `type@=loginreq/roomid@=<房间号>/` 和 `type@=joingroup/rid@=<房间号>/gid@=-9999/`；每次重连都重新发；
  - 心跳：每 45 s 发 `type@=mrkl/`；
  - 其余用 `DanmakuSocketPolicy` 的默认值，也就是 v3 `WebScoketUtils` 的默认值：无消息 135 s（max(3 × 45 s, 90 s)）换连接，握手超时 10 s，连续失败 8 次放弃。只有一个地址，所以重连间隔依次是 2、3、4、5、6、6、6、6 s。没有加入计时器（v3 没有）。
- **协议照 v3 的 `DouyuDanmaku`**，写成纯函数，不做 I/O：
  - 包：`长度(4) 长度(4) 类型(2) 加密(1) 保留(1) 包体 \0`，小端，长度 = 8 + 包体 + 1；客户端类型 689。用 D01.1 的 `BinaryWriter` 写；
  - 切包：按每个包自己的长度逐个切开（REG-DOUYU-017），长度小于 9 或越界时停止，丢掉每个包的最后一个字节，不看类型字段；
  - 消息：`chatmsg` 是聊天，`comm_chatmsg` 是醒目留言，`voice_trlt` 是语音醒目留言，`dgb` 是礼物，`oni` 是贵宾数（2026-10-28 起按在线数上报，见文末），`newblackres` 是禁言提示；其他包（`uenter`、`loginres` 等）忽略，和 v3 一样；
  - 聊天：`rid` 不为空且与房间不同就丢（REG-DOUYU-020），`txt` 为空就丢；字段 `nn`、`uid`、`txt`、`col`（v3 的 6 色表，其余白色）、`cst`（大于 10¹¹ 按毫秒，否则按秒）、`cid`（消息 id 为 `douyu:<cid>`）、`level`（用户等级）、`bnn`/`bl`（粉丝牌和牌子等级；没有牌子时等级留空，D07.3）；
  - 醒目留言：`now` 毫秒开始、`cet` 秒、`cprice` 分，嵌套的 `chatmsg{nn, txt, ic}`，头像 `https://apic.douyucdn.cn/upload/<ic>_small.jpg`，配色 `#c1c1ff`/`#292a60`；语音醒目留言取 `list` 的第一项：`acptime`、`etime`（秒）、`realPrice`（分）、`content`、`un`，头像 `https://` + `uat` 的第二项，配色 `#ffffff`/`#246488`。两者的用户名和文字都是 `SUPER_CHAT_MESSAGE`，数据放在 `LiveSuperChatMessage` 里；
  - 一个包解析失败（例如时间戳超出 `DateTime` 的范围）只丢这一个包，同一帧里后面的照常（REG-DOUYU-021）。
- **“疑似机器人”过滤照 v3**：没有 `dms` 且 `if` 不是 `1` 的聊天，只在设置打开时丢弃（REG-DOUYU-018、019）。设置由构造参数 `filterSuspectedAutomatedMessages` 的读取函数给出，每遇到一条疑似的聊天读一次，改设置不用重连；不传就是关闭。
- **STT 解码改成按层解析**（审查问题 1）：每个值只反转义一次，当作文字；只有协议里确实嵌套的字段（醒目留言的 `chatmsg`、语音醒目留言的 `list` 和 `uat`）再解析一层。对正常的数据，结果和 v3 的递归解析相同（录制的 147 条聊天逐字段一致）。
- **颜色**：斗鱼只用固定的 6 色表，不经过 `LiveMessageColor.numberToColor`，E05.1 对数字颜色的修正不涉及本平台。

## 与 v3 的对照

对照方式：同一份帧分别给新代码和 v3 的解码代码（`legacy_expected.dart`），逐条比较消息的全部字段（类型、用户名、用户 id、文字、颜色、消息 id、发送时间、等级和粉丝牌字段、是否本地、醒目留言的全部字段）。

| 样本 | 结果 |
|---|---|
| S13-live 发出的帧 | `loginreq`、`joingroup`、心跳与 v3 的 `serializeDouyu` 逐字节相同，也与录下的两帧发出帧相同 |
| S13-live 收到的 183 帧（过滤关闭） | 153 条消息：147 条聊天，顺序、所在的帧和全部字段一致（100 条白色，其余 6 种颜色都有；3 条没有 `cst`；`level`、`bnn`、`bl` 按 3.x 13f22bb58 填入，见差异 7）；另有 6 条 `oni` 贵宾数（2026-10-28 起按在线数上报，见文末） |
| S13-live（过滤打开） | 与 v3 一样 153 条全部保留（147 条聊天和 6 条贵宾数）：录到的聊天都带 `dms` 或 `if=1`，读取函数一次都没被调用 |
| S13-live 换成别的房间号 | 全部丢弃（每条 `chatmsg` 都带 `rid`） |
| S14 移植 v3 的 7 个用例（一帧多包、别的房间、默认保留、打开过滤后丢弃、改设置即时生效、空文字、聊天和醒目留言同帧） | 一致 |
| S14 颜色、秒和毫秒时间戳、缺字段、醒目留言、不完整的醒目留言、坏包、截断、长度小于 9、其他类型 | 一致 |
| S14 开箱通知 | v3 得到一条 0 元、时长 0 的醒目留言；新代码没有（差异 3） |
| S14 语音醒目留言 | 除头像外一致：v3 为空，新代码为 `https://` + `uat` 第二项（差异 2） |
| S14 带 `@A`、`@S`、`//`、`@=` 的文字 | v3 把 `@Alice 你好` 变成 `@lice 你好`、`@Sakura` 变成 `/akura`、链接变成 `[https:, t.cn/x]`、`a@=b` 变成 `{a: b}`；新代码保持原文（差异 1） |

测试里把这三处差异写成对 v3 输出的变换：先断言 v3 的输出确实如上，再断言新代码等于变换后的结果，其余用例要求完全相等。

## 审查发现的 v3 问题

位置相对 `legacy/lib/`。

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 聊天文字和昵称里有 `@A`、`@S`、`//`、`@=` 时显示错：`@Alice` 变 `@lice`、`@Sakura` 变 `/akura`，贴的链接变成 `[https:, …]`，`a@=b` 变成 `{a: b}` | `core/danmaku/douyu_danmaku.dart:118、267-295` | `sttToJObject` 对每个值递归：反转义后再按内容猜它是列表、字典还是文字，叶子又反转义一次。于是普通文字被反转义两次，含 `//`、`@=` 的文字被当成结构 | `DouyuStt` 按层解析，值只反转义一次；嵌套字段由协议按位置再解一层 |
| 2 | 语音醒目留言的头像永远是空的 | `core/danmaku/douyu_danmaku.dart:188-189` | 同上：`uat` 是字符串列表，标准编码是 `a/b/`，不含 `//`，递归解析只会得到一个字符串，`avatars is List` 永远不成立（上游原来的 `scData["uat"][1]` 取到的是字符串的第二个字符） | 按 STT 列表解析 `uat`，取第二项。录制里没有语音醒目留言，列表的编码规则取自同一录制里的 `ail`、`oni.list`、`ranklist.list` |
| 3 | 开箱通知当成 0 元醒目留言：醒目留言栏闪一下 | `core/danmaku/douyu_danmaku.dart:159-178` | `comm_chatmsg` 也用于开箱通知（归档规格 §7.4 记录了 2026-09-27 录到的 `btype@=pandora`、`cprice@=0`、`cet@=0`、`txt@=-`），v3 只检查字段是否存在 | 价格或时长不大于 0 的不是醒目留言（归档 v4 同样处理） |
| 4 | 包长按 UTF-16 码元算 | `core/danmaku/douyu_danmaku.dart:222-223` | `body.length` 是字符串长度，包体却是 UTF-8 | 按 UTF-8 字节数。v3 只发 ASCII 的包（房间号是数字），线上没有影响 |
| 5 | 收到文本帧会在 socket 回调里抛类型错误 | `core/danmaku/douyu_danmaku.dart:66` | `decodeMessage` 的参数是 `List<int>`，回调传进来的是 `dynamic` | 文本帧忽略。斗鱼只发二进制帧，线上没有影响 |

另外，归档的录制工具漏脱敏了三个字段：`configscreen.userName`（观众昵称）、`ranklist` 三个榜单里的 `icon` 和 `uenter.dceicon`（头像路径，其中 `avatar/004/05/68/52_avatar` 这种路径直接含有真实的用户 id）。已换成同形、同长度的合成值（包长不变），并记进 `meta.json` 的脱敏记录。这些包都不参与解码，期望值不受影响。

## 与 v3 的有意差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 文字按层解析，不再改动聊天和醒目留言的文字、昵称 | 问题 1。正常数据的结果与 v3 相同。v3 还会把整个包体含 `//` 的包当成列表跳过，按层解析不会；斗鱼的编码不产生这种包，录制的 563 个包里也没有 |
| 2 | 语音醒目留言显示头像 | 问题 2。头像地址的拼法（`https://` + `uat[1]`）沿用 v3 代码的本意 |
| 3 | 价格或时长为 0 的 `comm_chatmsg` 不是醒目留言 | 问题 3 |
| 4 | 包长按 UTF-8 字节数 | 问题 4 |
| 5 | 文本帧忽略 | 问题 5 |
| 6 | 回调换成事件，`connect` 只接受 `DouyuDanmakuArgs`（其他类型抛 `ArgumentError`） | D01.1 的统一接口；v3 接受任何参数并调用 `toString()` |
| 7 | 聊天没有粉丝牌时 `fansLevel` 留空，用户等级为 0 时也留空（3.x 13f22bb58 原样写 `bl` 和 `level`）；`oni` 只收本房间（3.x 不检查 `rid`），空数字不显示；`newblackres` 变成一条禁言提示 | D07.3 的规则“没有粉丝牌不填等级”；本房间检查和空行省略是 4.x 的收紧 |
| 8 | `oni` 的 `vn` 报成在线数（`LiveMessageType.online`、`onlineViewers`），不再报“贵宾”聊天行；非数字也不报 | 用户 2026-10-28 要求把贵宾数显示在热度、已开播那一栏（标签“贵宾”），见 D-070、D01.34 |

保持 v3 行为、没有顺手改的地方：

- **打开即就绪**，不等 `loginres`；没有加入计时器；服务端的 `pingreq` 不回应，只按间隔发 `mrkl`。
- **只检查聊天的 `rid`**，醒目留言不检查（v3 如此，也没有录到别的房间的醒目留言）。
- **`cst=0` 仍得到 1970 年的发送时间**，会被 D01.1 的去重闸门当作过期消息丢掉。归档 v4 把不大于 0 的当作没有时间；录制里没有这种值，先按 v3。
- **每个包的最后一个字节都丢掉**，不检查它是不是 `\0`；服务端包的类型字段（690）不检查。
- **不显示礼物（`dgb`）、进场（`uenter`）和榜单**：v3 没有显示。归档 v4 解了礼物，D01.1 已决定不搬。（国内平台完善 起礼物按附录 B 的同类做法以 `gift` 上报、界面暂不显示，见 E01.2 末尾。）
- **每次重连都报一次 `DanmakuReady`**，一轮失败只报一次重连（D01.1 的运行时，和 v3 一样）。

## 回归条目的覆盖

归档规格的 REG-DOUYU-017～021（E01.2 留给 D01 的部分）都有测试：

- 017 一帧多包：`bodies` 按包长切分；录制里的多包帧和 S14 的同帧用例；
- 018 过滤默认关闭：不传读取函数就是关闭，S14 的“默认保留”用例；
- 019 保留开关：构造参数 `filterSuspectedAutomatedMessages`，改设置不重连就生效（连接测试）；
- 020 别的房间的聊天丢弃：S14 用例、连接测试、录制换房间号；
- 021 单包出错不影响同帧其他包：S14 的坏时间戳用例。

## 登记方式

应用（I01.1）建 `DanmakuRegistry` 时：

```dart
SiteIds.douyu: () => DouyuDanmakuConnection(
  proxy: proxyPolicy,
  filterSuspectedAutomatedMessages: () => danmakuSettings.filterDouyuSuspectedAutomatedMessages,
),
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `proxy` | 否（默认直连） | `live_net` 的 `ProxyPolicy`，每次握手按平台 id `douyu` 取路线；v3 的弹幕走应用的代理设置 |
| `filterSuspectedAutomatedMessages` | 否（默认关闭） | 读 v3 的设置 `filterDouyuSuspectedAutomatedMessages`（默认 false）；每条疑似的聊天读一次 |
| `connector` | 否 | 只给测试替换握手 |

不需要 HTTP 客户端、Cookie 或账号：斗鱼弹幕是匿名连接，房间号已经在 `DouyuDanmakuArgs` 里。

## 放到其他模块的部分

| 内容 | 去向 |
|---|---|
| 设置 `filterDouyuSuspectedAutomatedMessages` 的存储、备份和恢复（缺省为关闭） | J02.1 |
| 屏蔽词页里的“过滤斗鱼疑似机器人弹幕”开关 | M13 |
| 连接状态的提示文字、醒目留言栏、弹幕列表 | M13（D01.1 的原因表） |
| 斗鱼表情（`assets/emo/json/douyu.json`，解析在 D01.1 的 `DanmakuEmoji`） | A01.1 |
| 平台表的登记 | I01.1 |

## 上游核对

pure_live_TV `e1cca224` 的斗鱼弹幕是更早的版本：只解每帧的第一个包（REG-DOUYU-017 的问题又回来了）、`if != 1` 的聊天一律丢弃（开关被去掉，018、019）、不检查 `rid`（020）、整帧只有一个 `try`（021），醒目留言直接 `int.parse`、头像取字符串下标。只有提示文字换成了多语言键（D01.1 已记录）。没有可采用的修复。

## 测试

`douyu_test.dart` 49 个用例：

| 分组 | 用例 | 内容 |
|---|---|---|
| 协议 | 9 | 加入包和心跳与 v3、录制逐字节相同；UTF-8 包长；切包（多包、截断、长度小于 9、末字节）；STT 的转义、按层解析、重复键、列表；颜色表；疑似机器人的判定；聊天的用户等级和粉丝牌；贵宾数（2026-10-28 起为在线数）；禁言提示 |
| 录制帧（S13）对照 v3 | 4 | 183 帧逐条对照 153 条消息；录制的聊天都带用户等级和粉丝牌；打开过滤后保留的消息；换房间号全部丢弃 |
| 合成帧（S14）对照 v3 | 18 | 17 组各一个用例（3 组按上面的差异变换），另有一个检查每组都有 v3 输出 |
| 连接 | 13 | 地址、无请求头、打开即就绪、加入包；策略（45 s、135 s、无加入计时器、8 次）；45 s 的心跳计时器和手动心跳；回放整段录制得到 v3 的 153 条；设置每条读取、不重连；别的房间和文本帧；断线后 2 s 重连、重新加入、再次就绪；退避 2、3、4、5、6、6、6、6 s 后放弃；`close` 之后没有事件和心跳；换房间关掉旧连接；参数类型；平台表登记；本地 WebSocket 服务器端到端回放 |


## 2026-10-24 PR #28 接续审查

贡献保留在原提交；新实现与审查发现按 A08.16、D01.33 登记。补齐等级/粉丝牌/通知的同时，修正低对比度与其他房间禁言通知，保留录制和迁移工程资料。本轮随 5.4.10 发布，真实账号取流故障仍由 E01.9 跟踪。

## 2026-10-28 贵宾数改为在线数（D01.34）

用户要求不再把 `oni` 的贵宾数显示成弹幕里的“贵宾”聊天行，改为显示在直播间的热度、已开播那一栏，标签“贵宾”，数据仍从弹幕 ws 取。解码改为报 `LiveMessageType.online`、`LiveAudienceUpdate(kind: onlineViewers)`；应用已有的观众栏和详情页直接显示，斗鱼通过 `AudienceFigure.label` 覆盖成“贵宾”。`oun` 仍不上报。S13 的 6 条 `oni` 在测试里按此变换；协议、录制、合成和连接用例同步。GitHub Actions 的定向检查和完整门禁全过（run 40696443904）。
