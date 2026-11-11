import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

// Sanitized shapes from the official 2026-10-30 anonymous web responses.
// All ids/text/media URLs here are synthetic; no credentials or expiring URLs.
String envelope(Map<String, Object?> data) => jsonEncode({'error': 0, 'data': data});

void main() {
  test('search tabs and author replay groups retain their distinct paging units', () {
    final page = DouyuVodApi.parseSearch(
      envelope({
        'relateVideotape': [
          {
            'hashId': 'Replay0000000001',
            'title': '直播 &amp; 回看',
            'owner': '测试主播',
            'upId': 'Author0001',
            'duration': '120:00',
            'type': 1,
          },
        ],
        'relateVideo': [],
        'total': 10000,
      }),
      page: 1,
      limit: 20,
      replay: true,
    );
    expect(page.hasMore, isTrue);
    expect(page.videos.single.replay, isTrue);
    expect(page.videos.single.duration, const Duration(hours: 2));
    expect(page.videos.single.title, '直播 & 回看');
    final author = DouyuVodApi.parseAuthor(
      envelope({
        'count': 2,
        'list': [
          {
            'show_id': 1234,
            'video_list': [
              {'hash_id': 'Replay0000000001', 'video_duration': 7200, 'author': '测试主播'},
              {'hash_id': 'Replay0000000002', 'video_str_duration': '00:20:00', 'up_id': ''},
            ],
          },
        ],
      }),
      page: 1,
      limit: 1,
      replay: true,
      authorId: 'Author0001',
    );
    expect(author.videos, hasLength(2));
    expect(author.total, 2);
    expect(author.hasMore, isTrue, reason: 'one session with two segments is only the first server page');
    expect(author.videos.last.authorId, 'Author0001');
    expect(author.videos.last.duration, const Duration(minutes: 20));
    final finalPage = DouyuVodApi.parseAuthor(
      envelope({
        'count': 2,
        'list': [
          {
            'video_list': [
              {'hash_id': 'Replay0000000003'},
            ],
          },
        ],
      }),
      page: 2,
      limit: 1,
      replay: true,
      authorId: 'Author0001',
    );
    expect(finalPage.hasMore, isFalse);
    final uploads = DouyuVodApi.parseAuthor(
      envelope({
        'count': 1,
        'videos': [
          {'hash_id': 'Upload0000000001', 'video_duration': '12.5'},
        ],
      }),
      page: 1,
      limit: 10,
      replay: false,
      authorId: 'Author0001',
    );
    expect(uploads.videos.single.replay, isFalse);
    expect(uploads.videos.single.duration, const Duration(milliseconds: 12500));
  });

  test('quality permissions and timeline millisecond cursors are never guessed', () {
    final qualities = DouyuVodApi.parseQualities(
      envelope({
        'thumb_video': {
          'super': {'name': '超清', 'level': 3, 'has_pms': 0, 'url': 'https://cdn.example/restricted.m3u8'},
          'high': {'name': '高清', 'level': 2, 'has_pms': 1, 'url': 'https://cdn.example/high.m3u8'},
          'normal': {'name': '标清', 'level': 1, 'now_free': 1, 'url': 'https://cdn.example/normal.m3u8'},
          'bad': {'level': 4, 'has_pms': 1, 'url': 'file:///private/video.mp4'},
        },
      }),
    );
    expect(qualities.where((item) => item.playable).map((item) => item.id), ['high', 'normal']);
    expect(qualities.first.url, isEmpty);
    final comments = DouyuVodApi.parseDanmaku(
      envelope({
        'end_time': 53990,
        'list': [
          {'tl': 1200, 'ctt': '第二条', 'mid': 'two', 'ct': 1},
          {'tl': 990, 'ctt': '第一条', 'mid': 'one'},
          {'tl': -1, 'ctt': 'invalid'},
        ],
      }),
      start: Duration.zero,
    );
    expect(comments.messages.map((item) => item.progress.inMilliseconds), [990, 1200]);
    expect(comments.messages.last.color, 0xff0000);
    expect(comments.next, const Duration(milliseconds: 53990));
    expect(
      DouyuVodApi.parseDanmaku(
        envelope({'end_time': 53990, 'list': []}),
        start: const Duration(milliseconds: 53990),
      ).next,
      isNull,
    );
    expect(
      DouyuVodApi.parseDanmaku(
        envelope({'end_time': -1, 'list': [], 'forbidden_type': 1}),
        start: Duration.zero,
      ).blocked,
      isTrue,
    );
    expect(
      () => DouyuVodApi.parseSearch(envelope({'list': []}), page: 1, limit: 20, replay: true),
      throwsA(isA<ApiChanged>()),
    );
  });

  test('official recommendation links only; current endpoints receive exact tabs/pages/cursor', () async {
    final home = DouyuVodApi.parseHome(
      '<a href="https://v.douyu.com/show/Replay0000000001" aria-label="预告片"> '
      '<img src="https://img.example/cover.jpg"></a><a href="https://evil.example/show/Replay0000000002">注入</a>',
    );
    expect(home.videos.single.id, 'Replay0000000001');
    expect(DouyuVodApi.idFromText('https://v.douyu.com.evil.example/show/Replay0000000001'), isNull);
    final http = _Http();
    final api = DouyuVodApi(http);
    http.body = envelope({'relateVideo': [], 'total': 0});
    await api.search('主播', replay: false, page: 2, limit: 5);
    expect(http.last.url.queryParameters, {
      'kw': '主播',
      'page': '2',
      'pageSize': '5',
      'tabType': '0',
      'filterType': '0',
    });
    http.body = envelope({'list': [], 'count': 0});
    await api.author('Author0001', page: 3);
    expect(http.last.url.path, '/wgapi/vod/center/authorShowVideoList');
    expect(http.last.url.queryParameters['page'], '3');
    http.body = envelope({'list': [], 'end_time': -1});
    await api.danmaku('Replay0000000001', const Duration(seconds: 123));
    expect(http.last.url.queryParameters['start_time'], '123000');
    http.status = 403;
    await expectLater(api.home(), throwsA(isA<RiskControl>()));
  });
}

final class _Http implements LiveHttp {
  late LiveRequest last;
  String body = '';
  int status = 200;
  @override
  Future<LiveResponse> send(LiveRequest request) async {
    last = request;
    return LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();
  @override
  void close() {}
}
