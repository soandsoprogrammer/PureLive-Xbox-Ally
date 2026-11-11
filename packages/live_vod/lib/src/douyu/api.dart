import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/src/douyu/models.dart';
import 'package:live_vod/src/douyu/sign.dart';
import 'package:live_vod/src/douyu/source.dart';
import 'package:live_vod/src/models.dart';

const _site = 'douyu';
final _videoId = RegExp(r'^[A-Za-z0-9]{8,64}$');
final _authorId = RegExp(r'^[A-Za-z0-9]{1,64}$');

/// Official Douyu videos and replay catalogs, with the app's normal transport,
/// proxy policy, optional existing Douyu login and cancellation. No JS runtime.
final class DouyuVodApi implements DouyuVodSource {
  /// Creates the API; the anonymous device id is random per client instance.
  new(this.http, {this._cookies, DateTime Function()? now, String? did})
    : _now = now ?? DateTime.now,
      _did = did ?? List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  /// App-owned HTTP transport, never closed by this API wrapper.
  final LiveHttp http;
  final CookieVault? _cookies;
  final DateTime Function() _now;
  final String _did;

  /// Same browser UA throughout the video page and signing request.
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

  Map<String, String> get _headers => {
    'user-agent': userAgent,
    'referer': 'https://v.douyu.com/',
    if ((_cookies?.cookieFor(_site) ?? '').isNotEmpty)
      'cookie': _cookies!.cookieFor(_site)!.replaceAll(RegExp(r'[\r\n\u0000]'), ''),
  };

  /// Extracts a hash id from an official video URL or a bare video id.
  static String? idFromText(String text) {
    final value = text.trim();
    if (_videoId.hasMatch(value)) return value;
    for (final url in LinkParser.sharedHttpUrls(value)) {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host != 'v.douyu.com' || uri.pathSegments.length != 2 || uri.pathSegments[0] != 'show') {
        continue;
      }
      if (_videoId.hasMatch(uri.pathSegments[1])) return uri.pathSegments[1];
    }
    return null;
  }

  /// Public homepage recommendations, read from server-rendered video cards.
  @override
  Future<DouyuVodPage> home({CancelToken? cancel}) async =>
      parseHome((await _get(Uri.https('v.douyu.com', '/'), cancel)).text);

  /// Current web search. Explicit tab 3 means replay, tab 0 ordinary video.
  @override
  Future<DouyuVodPage> search(
    String keyword, {
    bool replay = true,
    int page = 1,
    int limit = 20,
    CancelToken? cancel,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty || query.length > 120) throw const FormatException('Invalid video search');
    _page(page, limit);
    final response = await _get(
      Uri.https('www.douyu.com', '/japi/search/api/searchVideo', {
        'kw': query,
        'page': '$page',
        'pageSize': '$limit',
        'tabType': replay ? '3' : '0',
        'filterType': '0',
      }),
      cancel,
    );
    return parseSearch(response.text, page: page, limit: limit, replay: replay);
  }

  /// An author's replay sessions or uploaded videos, with real server paging.
  @override
  Future<DouyuVodPage> author(
    String id, {
    bool replay = true,
    int page = 1,
    int limit = 10,
    CancelToken? cancel,
  }) async {
    if (!_authorId.hasMatch(id)) throw const FormatException('Invalid author id');
    _page(page, limit);
    final path = replay ? '/wgapi/vod/center/authorShowVideoList' : '/wgapi/vod/center/getAuthorVideosByNew';
    final response = await _get(
      Uri.https('v.douyu.com', path, {
        'up_id': id,
        'page': '$page',
        'limit': '$limit',
        if (!replay) ...{'cid2': '0', 'tag2': '0'},
      }),
      cancel,
    );
    return parseAuthor(response.text, page: page, limit: limit, replay: replay, authorId: id);
  }

  /// Full metadata and the current day's signing data from the official page.
  @override
  Future<DouyuVodDetail> detail(String id, {CancelToken? cancel}) async {
    if (!_videoId.hasMatch(id)) throw const FormatException('Invalid video id');
    return parseDetail((await _get(Uri.https('v.douyu.com', '/show/$id'), cancel)).text, id: id);
  }

  /// Every official segment of the current replay session, in platform order.
  @override
  Future<List<DouyuVodVideo>> replaySegments(DouyuVodVideo video, {CancelToken? cancel}) async {
    if (!_videoId.hasMatch(video.id) || !_authorId.hasMatch(video.authorId)) return const [];
    final response = await _get(
      Uri.https('v.douyu.com', '/wgapi/vod/center/getShowReplayList', {'vid': video.id, 'up_id': video.authorId}),
      cancel,
    );
    final data = _data(response.text);
    return _videos(_list(data['list']), replay: true, authorId: video.authorId);
  }

  /// Fresh signed media URLs. Expired URLs are renewed by signing again.
  @override
  Future<List<DouyuVodQuality>> qualities(DouyuVodDetail detail, {CancelToken? cancel}) async {
    final fields = detail.signer.form(
      pointId: detail.video.pointId,
      videoId: detail.video.id,
      did: _did,
      seconds: _now().millisecondsSinceEpoch ~/ 1000,
    );
    final response = await _send(
      LiveRequest.form(
        site: _site,
        url: Uri.https('v.douyu.com', '/wgapi/vodnc/front/stream/getStreamUrlWeb'),
        fields: fields,
        headers: _headers,
        cancel: cancel,
      ),
    );
    return parseQualities(response.text);
  }

  /// A bounded batch of timeline comments beginning at [start].
  @override
  Future<DouyuVodDanmakuChunk> danmaku(String id, Duration start, {CancelToken? cancel}) async {
    if (!_videoId.hasMatch(id) || start < Duration.zero) throw const FormatException('Invalid danmaku cursor');
    final response = await _get(
      Uri.https('v.douyu.com', '/wgapi/vod/center/getBarrageList', {
        'vid': id,
        'start_time': '${start.inMilliseconds}',
        'end_time': '-1',
      }),
      cancel,
    );
    return parseDanmaku(response.text, start: start);
  }

  Future<LiveResponse> _get(Uri uri, CancelToken? cancel) =>
      _send(LiveRequest(site: _site, url: uri, headers: _headers, cancel: cancel));

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      final response = await http.send(request);
      if (response.status == 404) throw const NotFound(_site, 'Video resource not found');
      if (response.status == 401) throw const NeedsLogin(_site, 'Video resource needs login');
      if (response.status == 403 || response.status == 429) {
        throw const RiskControl(_site, detail: 'Video request refused');
      }
      if (!response.isSuccess) throw NetworkFailure(_site, 'Video HTTP ${response.status}');
      if (response.bytes.length > 8388608) throw const ApiChanged(_site, 'Video response size');
      return response;
    } on TransportFailure catch (error) {
      throw NetworkFailure(_site, error.toString());
    }
  }

  static void _page(int page, int limit) {
    if (page < 1 || limit < 1 || limit > 50) throw const FormatException('Invalid video page');
  }

  /// Parses official server-rendered recommendation cards without executing JS.
  static DouyuVodPage parseHome(String html) {
    final document = HtmlElement.parseFragment(html);
    final videos = <String, DouyuVodVideo>{};
    for (final link in document.queryAll((element) => element.tag == 'a')) {
      final id = idFromText(link.attributes['href'] ?? '');
      if (id == null || videos.containsKey(id)) continue;
      final title = (link.attributes['aria-label'] ?? link.attributes['title'] ?? link.text).trim();
      if (title.isEmpty) continue;
      final image = link.query((element) => element.tag == 'img');
      videos[id] = DouyuVodVideo(id: id, title: title, cover: normalizeImageUrl(image?.attributes['src']));
      if (videos.length >= 100) break;
    }
    if (videos.isEmpty && !html.contains('暂无')) throw const ApiChanged(_site, 'Recommendation video cards missing');
    return DouyuVodPage(videos: List.unmodifiable(videos.values), hasMore: false, total: videos.length);
  }

  /// Parses web search's separate replay and video result arrays.
  static DouyuVodPage parseSearch(String body, {required int page, required int limit, required bool replay}) {
    final data = _data(body);
    final key = replay ? 'relateVideotape' : 'relateVideo';
    if (data[key] is! List) throw const ApiChanged(_site, 'Video search result shape');
    final items = _list(data[key]);
    final total = jsonInt(data['total']) ?? 0;
    return DouyuVodPage(
      videos: _videos(items, replay: replay),
      total: total,
      hasMore: items.isNotEmpty && (total > 0 ? page * limit < total : items.length >= limit),
    );
  }

  /// Parses author session groups and ordinary upload pages.
  static DouyuVodPage parseAuthor(
    String body, {
    required int page,
    required int limit,
    required bool replay,
    required String authorId,
  }) {
    final data = _data(body);
    final raw = replay ? data['list'] : data['videos'];
    if (raw is! List) throw const ApiChanged(_site, 'Author video list shape');
    final items = _list(raw);
    final videos = replay ? [for (final session in items) ..._list(session['video_list'])] : items;
    final total = jsonInt(data['count']) ?? 0;
    return DouyuVodPage(
      videos: _videos(videos, replay: replay, authorId: authorId),
      total: total,
      hasMore: items.isNotEmpty && (total > 0 ? page * limit < total : items.length >= limit),
    );
  }

  /// Reads the ROOM JSON object and allowed signing data from a video page.
  static DouyuVodDetail parseDetail(String html, {required String id}) {
    final marker = html.indexOf(r'window.$DATA');
    if (marker < 0) throw const ApiChanged(_site, 'Video page metadata missing');
    final roomMarker = RegExp(r'\bROOM\s*:\s*').firstMatch(html.substring(marker));
    if (roomMarker == null || roomMarker.start > 1024) throw const ApiChanged(_site, 'Video ROOM metadata missing');
    final room = _embeddedObject(html, marker + roomMarker.end);
    if (room['vid'] != id || jsonInt(room['point_id']) == null) {
      throw const ApiChanged(_site, 'Video identity mismatch');
    }
    final document = HtmlElement.parseFragment(html);
    final source = document
        .queryAll((element) => element.tag == 'script')
        .map((element) => element.text)
        .where((text) => text.contains('function ub98484234'))
        .firstOrNull;
    if (source == null) throw const ApiChanged(_site, 'Video signing data missing');
    return DouyuVodDetail(video: DouyuVodVideo.fromJson(room), signer: DouyuVodSigner.fromScript(source));
  }

  /// Parses permissions and quality labels without substituting paid tiers.
  static List<DouyuVodQuality> parseQualities(String body) {
    final values = _data(body)['thumb_video'];
    if (values is! Map) throw const ApiChanged(_site, 'Video qualities missing');
    final result = <DouyuVodQuality>[];
    for (final entry in values.entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      final url = jsonString(raw['url']) ?? '';
      final uri = Uri.tryParse(url);
      final valid =
          uri != null && uri.userInfo.isEmpty && uri.host.isNotEmpty && {'http', 'https'}.contains(uri.scheme);
      result.add(
        DouyuVodQuality(
          id: '${entry.key}',
          label: jsonString(raw['name']) ?? '${entry.key}',
          level: jsonInt(raw['level']) ?? 0,
          url: valid ? url : '',
          playable: valid && (jsonInt(raw['has_pms']) == 1 || jsonInt(raw['now_free']) == 1),
        ),
      );
    }
    result.sort((a, b) => b.level.compareTo(a.level));
    return List.unmodifiable(result);
  }

  /// Parses actual millisecond timestamps, text and explicit server pagination.
  static DouyuVodDanmakuChunk parseDanmaku(String body, {required Duration start}) {
    final data = _data(body);
    final next = jsonInt(data['end_time']) ?? -1;
    final messages = <VodDanmaku>[];
    for (final item in _list(data['list']).take(1000)) {
      final position = jsonInt(item['tl']);
      final text = jsonString(item['ctt'])?.trim() ?? '';
      if (position == null || position < 0 || text.isEmpty || text.length > 8192) continue;
      final color = switch (jsonInt(item['ct'])) {
        1 => 0xff0000,
        2 => 0x1e87f0,
        3 => 0x7ac84b,
        4 => 0xff7f00,
        5 => 0x9b39f4,
        6 => 0xff69b4,
        _ => 0xffffff,
      };
      messages.add(
        VodDanmaku(
          progress: Duration(milliseconds: position),
          text: text,
          id: jsonString(item['mid']) ?? '',
          color: color,
        ),
      );
    }
    messages.sort((a, b) => a.progress.compareTo(b.progress));
    return DouyuVodDanmakuChunk(
      messages: List.unmodifiable(messages),
      next: next > start.inMilliseconds ? Duration(milliseconds: next) : null,
      blocked: (jsonInt(data['forbidden_type']) ?? 0) != 0,
    );
  }

  static Map<String, dynamic> _data(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final code = jsonInt(decoded['error'] ?? decoded['code']);
      if (code == 401 || code == -401) throw const NeedsLogin(_site, 'Video endpoint requires login');
      if (code != 0) throw ApiChanged(_site, 'Video endpoint error $code');
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) throw const FormatException();
      return data;
    } on FormatException {
      throw const ApiChanged(_site, 'Video response shape');
    }
  }

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is Map<String, dynamic>) item,
        ]
      : const [];

  static List<DouyuVodVideo> _videos(List<Map<String, dynamic>> items, {required bool replay, String authorId = ''}) {
    final unique = <String, DouyuVodVideo>{};
    for (final item in items.take(500)) {
      final video = DouyuVodVideo.fromJson({
        ...item,
        if ((jsonString(item['up_id']) ?? jsonString(item['upId']) ?? '').isEmpty && authorId.isNotEmpty)
          'up_id': authorId,
      }, replay: replay);
      if (_videoId.hasMatch(video.id)) unique[video.id] = video;
    }
    return List.unmodifiable(unique.values);
  }

  static Map<String, dynamic> _embeddedObject(String html, int start) {
    var from = start;
    while (from < html.length && html[from].trim().isEmpty) {
      from++;
    }
    if (from >= html.length || html[from] != '{') throw const ApiChanged(_site, 'Video metadata object');
    var quoted = false;
    var escaped = false;
    var depth = 0;
    for (var at = from; at < html.length && at - from < 2097152; at++) {
      final char = html[at];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (quoted && char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        quoted = !quoted;
        continue;
      }
      if (quoted) continue;
      if (char == '{') depth++;
      if (char == '}' && --depth == 0) {
        try {
          final value = jsonDecode(html.substring(from, at + 1));
          if (value is Map<String, dynamic>) return value;
        } on FormatException {
          break;
        }
        break;
      }
    }
    throw const ApiChanged(_site, 'Video metadata JSON');
  }
}
