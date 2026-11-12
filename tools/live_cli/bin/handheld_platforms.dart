import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_cli/src/sites.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';

Future<void> main() async {
  final commands = StreamIterator(stdin.transform(utf8.decoder).transform(const LineSplitter()));
  MediaInput? active;
  MediaOpener? opener;
  IoLiveHttp? client;
  try {
    if (!await commands.moveNext()) return;
    final request = jsonDecode(commands.current) as Map<String, dynamic>;
    final proxy = _proxy();
    final base = client = IoLiveHttp(proxy: proxy);
    final cookies = MemoryCookieVault();
    final platform = request['platform'] as String;
    final cookie = request['account_cookie'];
    final signedPlatform = _accountDomains.containsKey(platform) && cookie is String && cookie.isNotEmpty
        ? platform
        : null;
    if (signedPlatform != null) cookies.set(signedPlatform, cookie as String);
    final http = _accountHttp(base, signedPlatform);
    final registry = SiteRegistry({
      for (final MapEntry(key: id, value: factory) in siteFactories(cookies: cookies).entries)
        if (id == SiteIds.twitch)
          id: () => TwitchSite(
            http,
            cookies: cookies,
            gqlFallbacks: [_accountHttp(Http2LiveHttp(proxy: proxy), signedPlatform)],
          )
        else
          id: () => factory(http, proxy),
    });
    final action = request['action'] as String;
    final query = request['query'] as String;
    if (action == 'catalog') {
      await _reply({
        'sites': [
          for (final site in registry.sites) {'id': site.id, 'name': site.name},
          {'id': 'iptv', 'name': 'IPTV'},
        ],
      });
    } else if (action == 'find') {
      final rooms = await _find(registry, http, platform, query).timeout(const Duration(seconds: 24));
      await _reply({'rooms': rooms});
    } else if (action == 'play') {
      final site = registry.maybeOf(platform);
      if (site == null) throw const FormatException('未识别的平台');
      final media = opener = MediaOpener(
        proxy: proxy,
        recipes: [
          if (site is BigoSite) BigoRecipeOpener(site),
          if (site is Fc2LiveSite) Fc2RecipeOpener(site),
          if (site is NiconicoSite) NiconicoRecipeOpener(site),
        ],
      );
      final selected = await _open(
        site, query, media, signedPlatform, request['quality'] as String?, request['line'] as String?,
      ).timeout(const Duration(seconds: 30));
      final input = active = selected.input;
      await _reply({
        'url': input.uri.toString(),
        'headers': input.headers,
        'proxy': input.proxyUrl,
        'lease': input.private,
        'playback': selected.options,
      });
      // The Rust player holds stdin open while it owns the relay or playback grant.
      if (input.private) await commands.moveNext();
    } else if (action == 'chat') {
      final site = registry.maybeOf(platform);
      final factory = danmakuFactories[platform];
      if (site == null || factory == null) throw const FormatException('该平台没有弹幕接口');
      await _chat(site, query, factory(http, proxy, site), commands);
    } else if (action == 'super_chat') {
      final site = registry.maybeOf(platform);
      if (site == null || !site.hasSuperChats) throw const FormatException('该平台不支持 SC');
      final cards = await site.getSuperChatMessage(roomId: query).timeout(const Duration(seconds: 12));
      final ordered = cards.toList()..sort((a, b) => b.startTime.compareTo(a.startTime));
      await _reply({'super_chats': ordered.take(100).map(_superChat).toList()});
    } else {
      throw const FormatException('未知的兼容组件请求');
    }
  } on Object catch (error) {
    await _reply({
      'error': switch (error) {
        final FormatException format => format.message,
        TimeoutException() => '平台响应超时',
        TransportFailure() || NetworkFailure() => '连接平台失败，请检查网络或代理',
        NotFound() => '找不到这个房间',
        NeedsLogin() => '这个房间需要登录，当前兼容组件使用游客模式',
        RegionBlocked() => '这个房间在当前地区不可用',
        RiskControl() || RateLimited() => '平台限制了当前请求，可稍后重试',
        StreamUnavailable() => '房间当前没有可用的游客播放线路',
        ApiChanged() => '平台接口返回了无法识别的数据',
        _ => '平台未返回可用结果（${error.runtimeType}）',
      },
    });
  } finally {
    try {
      await active?.close().timeout(const Duration(seconds: 2));
      await opener?.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Process exit also closes any remaining network handles.
    }
    client?.close();
    exit(0);
  }
}

Future<void> _reply(Map<String, Object?> result) async {
  stdout.writeln(jsonEncode(result));
  await stdout.flush();
}

FixedProxyPolicy _proxy() {
  final env = Platform.environment;
  final raw = env['HTTPS_PROXY'] ?? env['https_proxy'] ?? env['HTTP_PROXY'] ?? env['http_proxy'];
  final uri = raw == null ? null : Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'http' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return const FixedProxyPolicy();
  }
  return FixedProxyPolicy(global: HttpProxyRoute(uri.host, uri.port));
}

Future<List<Map<String, Object?>>> _find(SiteRegistry registry, LiveHttp http, String platform, String text) async {
  if (platform == 'iptv') return _iptv(http, text);
  final links = LinkParser(registry, http);
  final isLink = LinkParser.sharedHttpUrls(text).isNotEmpty;
  if (isLink) {
    final link = await links.parse(text);
    if (link == null) throw const FormatException('无法识别该直播间链接');
    final site = registry.maybeOf(link.platform);
    if (site == null) throw const FormatException('该平台已退役或不可用');
    return [_room(site, await site.getRoomDetail(roomId: link.roomId), fallbackId: link.roomId)];
  }
  if (platform == 'all') return _searchAll(registry, text);
  final site = registry.maybeOf(platform);
  if (site == null) throw const FormatException('未识别的平台');
  if (text.startsWith('@') || RegExp(r'^\d+$').hasMatch(text)) {
    final id = text.startsWith('@') ? text.substring(1).trim() : text;
    if (id.isEmpty) throw const FormatException('请输入房间号或频道 ID');
    return [_room(site, await site.getRoomDetail(roomId: id), fallbackId: id)];
  }
  final rooms = text.isEmpty ? await site.getRecommendRooms(pageSize: 24) : await site.searchRooms(text, pageSize: 24);
  return [
    for (final room in rooms.take(24))
      if (room.roomId.isNotEmpty) _room(site, room),
  ];
}

Future<List<Map<String, Object?>>> _searchAll(SiteRegistry registry, String text) async {
  if (text.isEmpty) return const [];
  final sites = registry.sites;
  final buckets = List<List<LiveRoom>>.filled(sites.length, const []);
  var next = 0;
  var completed = 0;
  var stopped = false;
  final pending = <CancelToken>{};

  Future<void> worker() async {
    while (!stopped && next < sites.length) {
      final index = next++;
      final site = sites[index];
      final cancel = CancelToken();
      pending.add(cancel);
      try {
        final rooms = await site.searchRoomsWithCancellation(text, pageSize: 12, cancel: cancel)
            .timeout(const Duration(seconds: 4));
        if (stopped) return;
        buckets[index] = rooms.where((room) => room.roomId.isNotEmpty).take(12).toList();
        completed++;
      } on Object {
        // Other platforms can still return results.
      } finally {
        cancel.cancel();
        pending.remove(cancel);
      }
    }
  }

  try {
    await Future.wait(List.generate(8, (_) => worker())).timeout(const Duration(seconds: 21));
  } on TimeoutException {
    // Keep completed platforms if some adapters are still busy.
  } finally {
    stopped = true;
    for (final cancel in pending) {
      cancel.cancel();
    }
  }
  if (completed == 0) throw const FormatException('各平台暂时没有返回搜索结果');
  return [
    for (var row = 0; row < 12; row++)
      for (var site = 0; site < sites.length; site++)
        if (row < buckets[site].length) _room(sites[site], buckets[site][row]),
  ].take(96).toList();
}

Map<String, Object?> _room(LiveSite site, LiveRoom room, {String? fallbackId}) => {
  'platform': site.id,
  'cover': room.cover,
  'nick': room.nick,
  'watching': room.watching,
  'live': room.isLiveNow,
  'id': room.roomId.isEmpty ? fallbackId : room.roomId,
  'title': room.title.isNotEmpty
      ? room.title
      : room.nick.isNotEmpty
      ? room.nick
      : site.name,
};

Future<({MediaInput input, Map<String, Object?> options})> _open(
  LiveSite site,
  String id,
  MediaOpener media,
  String? signedPlatform,
  String? qualityId,
  String? lineId,
) async {
  final room = site is BilibiliSite
      ? await site.getRoomDetailForRefresh(roomId: id)
      : await site.getRoomDetail(roomId: id);
  final qualities = await site.getPlayQualities(detail: room);
  final menu = {
    for (final quality in qualities) '${quality.selectionId}': quality.quality,
  };
  final candidates = qualityId == null
      ? qualities.take(3)
      : qualities.where((quality) => '${quality.selectionId}' == qualityId).take(1);
  for (final quality in candidates) {
    final result = await site.resolvePlayUrls(detail: room, quality: quality);
    final applied = result.appliedQuality;
    final appliedId = '${applied?.selectionId ?? result.appliedQualityData ?? quality.selectionId}';
    if (applied != null) menu.putIfAbsent(appliedId, () => applied.quality);
    final options = <String, Object?>{
      'qualities': [for (final item in menu.entries) {'id': item.key, 'label': item.value}],
      'quality': appliedId,
      'quality_label': applied?.quality ?? menu[appliedId] ?? '自动',
      'chat': danmakuFactories.containsKey(site.id),
      'super_chat': site.hasSuperChats,
      'super_chat_board': _hasSuperChatBoard(site),
    };
    if (result.inputRecipe case final recipe?) {
      if (lineId != null && lineId != 'recipe') throw const FormatException('该线路已不可用');
      options['lines'] = [{'id': 'recipe', 'label': '线路 1'}];
      options['line'] = 'recipe';
      return (input: await media.open(RecipeSource(recipe), site: site.id), options: options);
    }
    if (result.lines.isEmpty) continue;
    final occurrences = <String, int>{};
    final lines = result.lines.indexed.map((entry) {
      final (index, line) = entry;
      final key = '${line.lineId ?? ''}:${line.format?.name ?? ''}:${line.codec ?? ''}';
      final count = occurrences.update(key, (count) => count + 1, ifAbsent: () => 1);
      final label = [
        '线路 ${index + 1}',
        if (line.format != null && line.format != StreamFormat.other) line.format!.name.toUpperCase(),
        if (line.codec == 'avc') 'H.264' else if (line.codec == 'hevc') 'HEVC',
      ].join(' · ');
      return (id: '$key:$count', label: label, source: line);
    }).toList();
    final selected = lineId == null ? lines.first : lines.where((entry) => entry.id == lineId).firstOrNull;
    if (selected == null) throw const FormatException('该线路已不可用，请重新选择');
    options['lines'] = [for (final entry in lines) {'id': entry.id, 'label': entry.label}];
    options['line'] = selected.id;
    final line = _mediaLine(site, selected.source, signedPlatform);
    final input = await media.open(
      LineSource(line),
      site: site.id,
      queryPolicy: result.sourceQueryPolicies[line.url],
      variantSelector: result.sourceVariantSelectors[line.url],
      renew: line.lease?.cutsConnection == true
          ? (current) async {
              final next = await site.resolvePlayUrls(detail: room, quality: quality);
              if (next.lines.isEmpty) throw const FormatException('播放线路已失效');
              final renewed =
                  next.lines.where((line) =>
                    current.lineId != null && line.lineId == current.lineId &&
                    line.format == current.format && line.codec == current.codec
                  ).firstOrNull ?? next.lines.first;
              return _mediaLine(site, renewed, signedPlatform);
            }
          : null,
    );
    return (input: input, options: options);
  }
  throw const FormatException('房间当前没有可用的游客播放线路');
}

bool _hasSuperChatBoard(LiveSite site) => site is BilibiliSite || site is HuyaSite;

Map<String, Object?> _superChat(LiveSuperChatMessage message) {
  final time = message.startTime.toLocal();
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return {
    'id': message.messageId,
    'user': String.fromCharCodes(message.userName.runes.take(80)),
    'text': String.fromCharCodes(message.message.runes.take(400)),
    'price': superChatPriceLabel(
      message.price,
      message.unit,
      message.priceText,
      unitText: (unit, price) => switch (unit) {
        LiveGiftUnit.yuan => '$price 元',
        LiveGiftUnit.diamond => '$price 钻石',
        LiveGiftUnit.redBean => '$price 红豆',
        LiveGiftUnit.point => '$price 点',
        LiveGiftUnit.cheese => '$price 치즈',
        LiveGiftUnit.kicks => '$price Kicks',
        LiveGiftUnit.sixCoin => '$price 六币',
        _ => null,
      },
    ),
    'time': '$hour:$minute',
    'start': message.startTime.millisecondsSinceEpoch,
    'end': message.endTime.millisecondsSinceEpoch,
    'estimated': message.hasEstimatedStartTime,
    'picture': message.image.isNotEmpty,
  };
}

Future<void> _chat(
  LiveSite site,
  String id,
  DanmakuConnection connection,
  StreamIterator<String> commands,
) async {
  final ended = Completer<void>();
  final clock = Stopwatch()..start();
  var lastMessage = -80;
  final subscription = connection.events.listen((event) {
    switch (event) {
      case DanmakuReady():
        stdout.writeln('{"state":"ready"}');
      case DanmakuReconnecting():
        stdout.writeln('{"state":"reconnecting"}');
      case DanmakuReceived(message: LiveMessage(type: LiveMessageType.superChat, data: final LiveSuperChatMessage card)):
        stdout.writeln(jsonEncode({'super_chat': _superChat(card)}));
      case DanmakuReceived(:final message) when message.type == LiveMessageType.chat:
        final now = clock.elapsedMilliseconds;
        final text = message.message.isNotEmpty ? message.message : message.emotes.map((item) => item.code).join();
        if (now - lastMessage < 80 || text.trim().isEmpty) return;
        lastMessage = now;
        stdout.writeln(jsonEncode({
          'text': String.fromCharCodes(text.runes.take(140)),
          if (message.emotes.isNotEmpty)
            'emotes': [
              for (final item in message.emotes.take(12))
                if (item.code.length <= 140 && item.url.length <= 2048)
                  {'code': item.code, 'url': item.url},
            ],
        }));
      case DanmakuClosed():
        stdout.writeln('{"state":"closed"}');
        if (!ended.isCompleted) ended.complete();
      default:
        break;
    }
  });
  try {
    Future<void> join() async {
      final room = await site.getRoomDetail(roomId: id);
      if (room.danmakuData == null) throw const FormatException('该直播间没有弹幕接口');
      await connection.connect(room.danmakuData);
    }
    final stop = commands.moveNext();
    await Future.any([join().timeout(const Duration(seconds: 25)), stop, ended.future]);
    await Future.any([stop, ended.future]);
    await stdout.flush();
  } finally {
    await subscription.cancel();
    await connection.close().timeout(const Duration(seconds: 2));
  }
}

LivePlayLine _mediaLine(LiveSite site, LivePlayLine line, String? signedPlatform) {
  if (site.id != SiteIds.bilibili && site.id != signedPlatform) return line;
  // The account cookie is for platform APIs. Signed media URLs go to a CDN.
  return LivePlayLine(
    line.url,
    headers: {
      for (final entry in line.headers.entries)
        if (!_credentialHeader(entry.key)) entry.key: entry.value,
    },
    format: line.format,
    codec: line.codec,
    lineId: line.lineId,
    lease: line.lease,
    width: line.width,
    height: line.height,
  );
}

Future<List<Map<String, Object?>>> _iptv(LiveHttp http, String input) async {
  if (input.isEmpty) throw const FormatException('请输入 M3U / TXT 播放列表路径或网址');
  final uri = Uri.tryParse(input);
  final isWeb = uri?.scheme == 'http' || uri?.scheme == 'https';
  if (isWeb && uri!.path.toLowerCase().endsWith('.m3u8')) {
    return [
      {'platform': 'iptv', 'id': input, 'title': 'IPTV 直播流'},
    ];
  }
  final String text;
  if (isWeb) {
    final response = await http.open(LiveRequest(site: 'iptv', url: uri!));
    if (response.status < 200 || response.status >= 300) {
      await response.discard();
      throw FormatException('播放列表下载失败（HTTP ${response.status}）');
    }
    final bytes = <int>[];
    await for (final chunk in response.body) {
      if (bytes.length + chunk.length > 4 * 1024 * 1024) {
        throw const FormatException('播放列表超过 4 MiB');
      }
      bytes.addAll(chunk);
    }
    text = utf8.decode(bytes, allowMalformed: true);
  } else {
    final file = File(input);
    if (!await file.exists() || await file.length() > 4 * 1024 * 1024) {
      throw const FormatException('找不到播放列表或文件超过 4 MiB');
    }
    text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }
  final parsed = text.trimLeft().startsWith('#EXTM3U') ? const M3uParser().parse(text) : const TxtParser().parse(text);
  return [
    for (final entry in parsed.entries.take(500))
      {'platform': 'iptv', 'id': entry.streamUrl, 'title': entry.name, 'headers': entry.httpHeaders},
  ];
}

const _accountDomains = {
  SiteIds.bilibili: ['bilibili.com'],
  SiteIds.douyu: ['douyu.com'],
  SiteIds.huya: ['huya.com'],
  SiteIds.douyin: ['douyin.com'],
  SiteIds.kuaishou: ['kuaishou.com'],
  SiteIds.yy: ['yy.com'],
  SiteIds.twitch: ['twitch.tv'],
  SiteIds.soop: ['sooplive.co.kr', 'sooplive.com', 'afreecatv.com'],
};

bool _credentialHeader(String name) => const {'cookie', 'authorization'}.contains(name.toLowerCase());

LiveHttp _accountHttp(LiveHttp client, String? signedPlatform) =>
    signedPlatform == null ? client : _ScopedAccountHttp(client, signedPlatform);

final class _ScopedAccountHttp implements LiveHttp {
  const _ScopedAccountHttp(this.client, this.platform);

  final LiveHttp client;
  final String platform;

  LiveRequest _scope(LiveRequest request) {
    if (request.site != platform || !request.headers.keys.any(_credentialHeader)) return request;
    final host = request.url.host.toLowerCase();
    final allowed =
        request.url.scheme == 'https' &&
        _accountDomains[platform]!.any((domain) => host == domain || host.endsWith('.$domain'));
    return LiveRequest(
      site: request.site,
      url: request.url,
      method: request.method,
      headers: allowed
          ? request.headers
          : {
              for (final entry in request.headers.entries)
                if (!_credentialHeader(entry.key)) entry.key: entry.value,
            },
      body: request.body,
      followRedirects: !allowed && request.followRedirects,
      timeout: request.timeout,
      cancel: request.cancel,
    );
  }

  @override
  Future<LiveResponse> send(LiveRequest request) => client.send(_scope(request));

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => client.open(_scope(request));

  @override
  void close() => client.close();
}
