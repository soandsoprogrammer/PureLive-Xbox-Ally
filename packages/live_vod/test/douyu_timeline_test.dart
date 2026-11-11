import 'dart:async';

import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

Future<void> flush() async {
  for (var at = 0; at < 20; at++) {
    await Future<void>.value();
  }
}

void main() {
  test('comments follow media time, pause and seek; stale network pages cannot replay', () async {
    final requests = <Duration>[];
    final responses = <Completer<DouyuVodDanmakuChunk>>[];
    final emitted = <String>[];
    var clears = 0;
    final timeline = DouyuVodTimeline(
      fetch: (start, cancel) {
        requests.add(start);
        final response = Completer<DouyuVodDanmakuChunk>();
        responses.add(response);
        return response.future;
      },
      emit: (message) => emitted.add(message.text),
      clear: () => clears++,
    )..update(Duration.zero, playing: true);
    responses.first.complete(
      const DouyuVodDanmakuChunk(
        messages: [
          VodDanmaku(progress: Duration(seconds: 1), text: 'one'),
          VodDanmaku(progress: Duration(seconds: 2), text: 'two'),
        ],
        next: Duration(seconds: 60),
      ),
    );
    await flush();
    timeline.update(const Duration(seconds: 1), playing: true);
    expect(emitted, ['one']);
    timeline.update(const Duration(seconds: 2), playing: false);
    expect(emitted, ['one']);
    timeline.update(const Duration(seconds: 2), playing: true);
    expect(emitted, ['one', 'two']);
    timeline.seek(const Duration(seconds: 120));
    expect(requests.last, const Duration(seconds: 120));
    timeline.seek(const Duration(seconds: 300));
    responses[1].complete(
      const DouyuVodDanmakuChunk(
        messages: [VodDanmaku(progress: Duration(seconds: 300), text: 'stale')],
        next: null,
      ),
    );
    responses[2].complete(
      const DouyuVodDanmakuChunk(
        messages: [VodDanmaku(progress: Duration(seconds: 301), text: 'current')],
        next: null,
      ),
    );
    await flush();
    timeline.update(const Duration(seconds: 301), playing: true);
    expect(emitted, ['one', 'two', 'current']);
    expect(clears, 2);
    timeline
      ..seek(const Duration(seconds: 500))
      ..dispose();
    responses.last.complete(
      const DouyuVodDanmakuChunk(
        messages: [VodDanmaku(progress: Duration(seconds: 500), text: 'disposed')],
        next: null,
      ),
    );
    await flush();
    expect(emitted, ['one', 'two', 'current']);
  });

  test('a failed comment endpoint retries after media advances, without affecting video', () async {
    var requests = 0;
    final timeline = DouyuVodTimeline(
      fetch: (start, cancel) async {
        requests++;
        throw StateError('offline comments');
      },
      emit: (_) => fail('no comments'),
      clear: () {},
    )..update(Duration.zero, playing: true);
    await flush();
    for (var second = 1; second < 10; second++) {
      timeline.update(Duration(seconds: second), playing: true);
      await flush();
    }
    expect(requests, 1);
    timeline.update(const Duration(seconds: 10), playing: true);
    await flush();
    expect(requests, 2);
    timeline.dispose();
  });
}
