import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _play({
  int delivered = 10000,
  bool transcoded = true,
  String key = 'live_9adj_SUHXosG_228lj_bluray',
  String host = 'https://cdn.bilivideo.com',
}) => {
  'playurl_info': {
    'playurl': {
      'stream': [
        {
          'protocol_name': 'http_hls',
          'format': [
            {
              'format_name': 'fmp4',
              'codec': [
                {
                  'codec_name': 'avc',
                  'current_qn': delivered,
                  'accept_qn': [10000, if (transcoded) 250],
                  'base_url': '/live-bvc/123456/$key/index.m3u8?',
                  'url_info': [
                    {'host': host, 'extra': 'expires=2000003600&sign=fixture&cdn=original'},
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  },
};

LivePlayUrlResolution _resolve(Map<String, dynamic> data, {bool enabled = true, int requested = 10000}) =>
    BilibiliApi.resolution(
      data,
      requestedQn: requested,
      roomId: '5050',
      issuedAt: DateTime.fromMillisecondsSinceEpoch(2000000000000, isUtc: true),
      cookie: 'fixture=synthetic',
      preferRaw: enabled,
    );

void main() {
  test('issue137 opt-in Raw candidates retain opaque keys, query and official fallback', () {
    final result = _resolve(_play());
    expect(result.lines, hasLength(4));
    final raw = result.lines.take(3);
    expect(raw.map((line) => Uri.parse(line.url).host), [
      'cdn.bilivideo.com',
      'd1--cn-gotcha204.bilivideo.com',
      'd1--cn-gotcha204b.bilivideo.com',
    ]);
    for (final line in raw) {
      expect(Uri.parse(line.url).path, '/live-bvc/123456/live_9adj_SUHXosG_228lj/index.m3u8');
      expect(Uri.parse(line.url).query, 'expires=2000003600&sign=fixture&cdn=original');
      expect(line.headers, result.lines.last.headers);
      expect(line.lease, same(result.lines.last.lease));
      expect(line.codec, isNull, reason: 'a transcode codec does not identify the original stream codec');
      expect(line.lineId, startsWith('raw|'));
    }
    expect(result.lines.last.url, contains('_bluray/index.m3u8?'));
    expect(result.lines.last.codec, 'avc');
    expect(result.appliedQualityData, 10000);
  });

  test('disabled, untranscoded, downgraded, lower-tier and unknown paths stay official', () {
    for (final result in [
      _resolve(_play(), enabled: false),
      _resolve(_play(transcoded: false)),
      _resolve(_play(delivered: 250)),
      _resolve(_play(), requested: 250),
      _resolve(_play(key: 'live_opaque_unchanged')),
      _resolve(_play(key: 'live_bluray_inside_opaque')),
      _resolve(_play(host: 'https://not-bilivideo.com')),
    ]) {
      expect(result.lines, hasLength(1));
      expect(result.lines.single.lineId, isNot(startsWith('raw|')));
    }
  });

  test('documented markers are stripped only from the end, including FLV', () {
    for (final marker in ['bluray', 'prohevc', '4k']) {
      final data = _play(key: 'live_123_opaque_$marker');
      final play = (data['playurl_info'] as Map)['playurl'] as Map;
      final stream = (play['stream'] as List).single as Map;
      stream['protocol_name'] = 'http_stream';
      final format = (stream['format'] as List).single as Map;
      format['format_name'] = 'flv';
      ((format['codec'] as List).single as Map)['base_url'] = '/live-bvc/123/live_123_opaque_$marker.flv?';
      final result = _resolve(data);
      expect(Uri.parse(result.lines.first.url).path, '/live-bvc/123/live_123_opaque.flv');
      expect(result.lines.last.url, contains('_$marker.flv?'));
      expect(result.lines.first.format, StreamFormat.flv);
    }
  });

  test('index HLS Raw candidates remain reachable when the API advertises FLV and TS first', () {
    final data = _play();
    final play = (data['playurl_info'] as Map)['playurl'] as Map;
    final stream = (play['stream'] as List).single as Map;
    final fmp4 = (stream['format'] as List).single as Map;
    final codec = ((fmp4['codec'] as List).single as Map).cast<String, dynamic>();
    play['stream'] = [
      {
        'protocol_name': 'http_stream',
        'format': [
          {
            'format_name': 'flv',
            'codec': [
              {...codec, 'base_url': '/live-bvc/123456/live_9adj_SUHXosG_228lj_bluray.flv?'},
            ],
          },
        ],
      },
      {
        'protocol_name': 'http_hls',
        'format': [
          {
            'format_name': 'ts',
            'codec': [
              {...codec, 'base_url': '/live-bvc/123456/live_9adj_SUHXosG_228lj_bluray.m3u8?'},
            ],
          },
          fmp4,
        ],
      },
    ];
    final result = _resolve(data);
    final raw = result.lines.where((line) => line.lineId!.startsWith('raw|')).toList();
    expect(Uri.parse(raw.first.url).path, endsWith('/index.m3u8'));
    for (final host in ['d1--cn-gotcha204.bilivideo.com', 'd1--cn-gotcha204b.bilivideo.com']) {
      expect(
        raw.any((line) => Uri.parse(line.url).host == host && Uri.parse(line.url).path.endsWith('/index.m3u8')),
        isTrue,
      );
    }
    expect(raw.length, lessThanOrEqualTo(6));
    expect(
      raw.map((line) => line.lineId).toSet(),
      hasLength(raw.length),
      reason: 'a failed index variant must not preempt a different FLV or TS candidate',
    );
    expect(result.lines.last.lineId, isNot(startsWith('raw|')));
  });

  test('renewed CDN directory and signature keep Raw failure identities stable', () {
    final first = _resolve(_play());
    final changed = _play();
    final play = (changed['playurl_info'] as Map)['playurl'] as Map;
    final stream = (play['stream'] as List).single as Map;
    final format = (stream['format'] as List).single as Map;
    final codec = (format['codec'] as List).single as Map;
    codec['base_url'] = '/live-bvc/654321/live_9adj_SUHXosG_228lj_bluray/index.m3u8?';
    ((codec['url_info'] as List).single as Map)['extra'] = 'expires=2000004600&sign=renewed';
    final next = _resolve(changed);
    expect(next.lines.first.url, isNot(first.lines.first.url));
    expect(
      next.lines.map((line) => line.lineId),
      first.lines.map((line) => line.lineId),
      reason: 'refreshing failed candidates must not prevent fallback to official lines',
    );
  });
}
