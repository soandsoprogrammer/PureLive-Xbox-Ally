// These regressions use only the pre-Y02.2 public API, so they can also
// demonstrate the behavioral failures against the unmodified baseline.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/features/version/update_feed.dart';

final class _Http implements LiveHttp {
  new(this.respond);

  final Future<Object?> Function(LiveRequest request) respond;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final value = await respond(request);
    return LiveResponse(status: value == null ? 404 : 200, bytes: utf8.encode(jsonEncode(value)), url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

bool _origin(LiveRequest request) => request.url.host == 'raw.githubusercontent.com';
bool _mirror(LiveRequest request) => request.url.host == 'cdn.gh-proxy.org';
Map<String, Object?> _version(String version, [int build = 6000]) => {'version': version, 'build_number': build};

void main() {
  test('Y02.2: a fast stale version does not cancel the slower newer source', () async {
    final slower = Completer<Object?>();
    final http = _Http((request) async {
      if (_origin(request)) return _version('9.0.0');
      if (_mirror(request)) return await slower.future;
      return null;
    });
    final pending = UpdateFeed(http, githubOrigin: false).latest();
    await pumpEventQueue();
    slower.complete(_version('9.1.0'));
    expect((await pending)?.version, '9.1.0');
    expect(http.requests.every((request) => request.cancel!.isCancelled), isTrue);
  });

  test('Y02.2: a fast malformed identity does not defeat a valid JSON source', () async {
    final slower = Completer<Object?>();
    final http = _Http((request) async {
      if (_origin(request)) return {'version': '9.0.0'};
      if (_mirror(request)) return await slower.future;
      return null;
    });
    final pending = UpdateFeed(http, githubOrigin: false).latest();
    // Attach before completing the source: baseline throws on the first map.
    final result = pending.then<Object?>((value) => value, onError: (Object error) => error);
    await pumpEventQueue();
    slower.complete(_version('9.0.0'));
    expect(await result, isA<UpdateInfo>().having((info) => info.version, 'version', '9.0.0'));
  });

  test('Y02.2: same version selects the higher build, regardless of response order', () async {
    for (final higherFirst in [false, true]) {
      final slower = Completer<Object?>();
      final http = _Http((request) async {
        if (_origin(request)) return _version('9.0.0', higherFirst ? 6001 : 6000);
        if (_mirror(request)) return await slower.future;
        return null;
      });
      final pending = UpdateFeed(http, githubOrigin: false).latest();
      await pumpEventQueue();
      slower.complete(_version('9.0.0', higherFirst ? 6000 : 6001));
      expect((await pending)?.buildNumber, 6001);
    }
  });

  test('a higher version with a lower installer build cannot hide a valid upgrade source', () async {
    final http = _Http((request) async {
      if (_origin(request)) return _version('99.0.0', 1);
      if (_mirror(request)) return _version('9.0.0');
      return null;
    });
    expect((await UpdateFeed(http, githubOrigin: false).latest())?.version, '9.0.0');
  });

  test('origin-only checks never ask mirrors and reject malformed version numbers', () async {
    final http = _Http((_) async => _version('not-a-version'));
    expect(await UpdateFeed(http, githubOrigin: true).latest(), isNull);
    expect(http.requests, hasLength(1));
    expect(http.requests.single.url.host, 'raw.githubusercontent.com');
  });

  testWidgets('the selection deadline returns the best answer and cancels a hanging source', (tester) async {
    final http = _Http((request) async {
      if (_origin(request)) return _version('9.0.0');
      await request.cancel!.whenCancelled;
      return _version('99.0.0');
    });
    final pending = UpdateFeed(http, githubOrigin: false).latest(timeout: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect((await pending)?.version, '9.0.0');
    expect(http.requests.every((request) => request.cancel!.isCancelled), isTrue);
  });
}
