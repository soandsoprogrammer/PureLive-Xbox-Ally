import 'dart:async';

import 'package:live_core/src/sites/weibo/weibo_streams.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _base = 'https://plwb00.live.weibo.com/alicdn/5000000000000000_wb720avc.flv';

List<int> _flv({int codec = 7}) {
  final payload = [0x10 | codec, 0, 0, 0, 0, 1, 0x64, 0, 0x1f, 0xff, 0xe1, 0, 1, 0x67];
  return [
    70,
    76,
    86,
    1,
    5,
    0,
    0,
    0,
    9,
    0,
    0,
    0,
    0,
    9,
    0,
    0,
    payload.length,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    ...payload,
    0,
    0,
    0,
    payload.length + 11,
  ];
}

final class _Http implements LiveHttp {
  new(this.answer);
  final Future<LiveStreamedResponse> Function(LiveRequest) answer;
  final requests = <LiveRequest>[];
  bool closed = false;
  @override
  Future<LiveStreamedResponse> open(LiveRequest request) {
    requests.add(request);
    return answer(request);
  }

  @override
  Future<LiveResponse> send(LiveRequest request) => throw UnsupportedError('stream only');
  @override
  void close() {
    closed = true;
  }
}

void main() {
  test('canonical candidates stay on the same unsigned public broadcast', () {
    final candidates = WeiboStreams.candidates([_base, _base]);
    expect(candidates.map((p) => p.id), ['weibo-source', 'weibo-1080-avc', 'weibo-480-avc']);
    expect(candidates.map((p) => p.url.path), [
      '/alicdn/5000000000000000.flv',
      '/alicdn/5000000000000000_wb1080avc.flv',
      '/alicdn/5000000000000000_wb480avc.flv',
    ]);
    for (final bad in [
      '$_base?signature=fixture',
      '$_base#x',
      _base.replaceFirst('https:', 'http:'),
      _base.replaceFirst('plwb00.live.weibo.com', 'plwb00.live.weibo.com.evil.test'),
      _base.replaceFirst('plwb00.live.weibo.com', 'viewer@plwb00.live.weibo.com'),
      _base.replaceFirst('/alicdn/', '/other/'),
      _base.replaceFirst('.flv', '.m3u8'),
    ]) {
      expect(WeiboStreams.candidates([bad]), isEmpty, reason: bad);
    }
  });

  test('FLV codec parsing waits for complete bounded sequence headers', () {
    expect(WeiboStreams.codecFromFlv(_flv()), 'avc');
    expect(WeiboStreams.codecFromFlv(_flv(codec: 12)), 'hevc');
    expect(WeiboStreams.codecFromFlv(_flv(codec: 2)), isNull);
    for (var end = 0; end < _flv().length - 4; end++) {
      expect(WeiboStreams.codecFromFlv(_flv().take(end).toList()), isNull, reason: '$end');
    }
    final huge = _flv()..setRange(14, 17, [255, 255, 255]);
    expect(WeiboStreams.codecFromFlv(huge), isNull);
    expect(WeiboStreams.codecFromFlv(List.filled(100, 0)), isNull);
  });

  test('successful fragmented probe closes only its stream, never shared transport', () async {
    var cancelled = false;
    final bytes = _flv();
    final body = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final http = _Http((r) async {
      scheduleMicrotask(() {
        body
          ..add(bytes.sublist(0, 8))
          ..add(bytes.sublist(8));
      });
      return LiveStreamedResponse(status: 200, body: body.stream, url: r.url);
    });
    final parent = CancelToken();
    expect(await WeiboStreams.probe(http, Uri.parse(_base), cancel: parent), 'avc');
    expect(cancelled, isTrue);
    expect(http.requests.single.cancel!.isCancelled, isTrue);
    expect(identical(http.requests.single.cancel, parent), isFalse);
    expect(parent.isCancelled, isFalse);
    expect(http.closed, isFalse);
    await body.close();
  });

  test('oversized responses and HTTP errors close without treating HTML as media', () async {
    for (final status in [200, 403, 404, 302]) {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final http = _Http((r) async {
        scheduleMicrotask(() => body.add(List.filled(WeiboStreams.prefixLimit * 2, 60)));
        return LiveStreamedResponse(status: status, body: body.stream, url: r.url);
      });
      expect(await WeiboStreams.probe(http, Uri.parse(_base)), isNull);
      expect(cancelled, isTrue);
      await body.close();
    }
  });

  test('parent cancellation also discards a response whose headers arrive late', () async {
    final pending = Completer<LiveStreamedResponse>();
    final http = _Http((r) => pending.future);
    final parent = CancelToken();
    final result = WeiboStreams.probe(http, Uri.parse(_base), cancel: parent);
    final expectation = expectLater(
      result,
      throwsA(isA<TransportFailure>().having((e) => e.reason, 'reason', TransportReason.cancelled)),
    );
    parent.cancel();
    var discarded = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        discarded = true;
      },
    );
    pending.complete(LiveStreamedResponse(status: 200, body: body.stream, url: Uri.parse(_base)));
    await expectation;
    expect(discarded, isTrue);
    expect(http.closed, isFalse);
    await body.close();
  });

  test('a silent live response reaches the whole-probe timeout and is cancelled', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final http = _Http((r) async => LiveStreamedResponse(status: 200, body: body.stream, url: r.url));
    expect(await WeiboStreams.probe(http, Uri.parse(_base)), isNull);
    expect(cancelled, isTrue);
    expect(http.closed, isFalse);
    await body.close();
  });
}
