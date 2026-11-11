import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/douyin/danmaku/S14-room-information';
List<int> recorded() {
  final data = jsonDecode(File('$_root/body.json').readAsStringSync()) as Map<String, dynamic>;
  return base64Decode(data['responseBase64'] as String);
}

Future<void> flush() async {
  for (var at = 0; at < 30; at++) {
    await Future<void>.value();
  }
}

void main() {
  const args = DouyinDanmakuArgs(webRid: 'sample', roomId: '123', userId: '1234567890', cookie: '');
  test('anonymous public capture preserves actual weekly preview and separate room dynamics', () {
    final messages = DouyinDanmakuProtocol.initialInformation(recorded(), roomId: '123');
    final expected = jsonDecode(File('$_root/expected.json').readAsStringSync()) as Map<String, dynamic>;
    expect(messages, hasLength(2));
    final preview = messages.first.data! as LiveRoomInfoUpdate;
    final dynamics = messages.last.data! as LiveRoomInfoUpdate;
    expect(preview.preview?.text, expected['preview']);
    expect(preview.preview?.id, expected['id']);
    expect(dynamics.dynamics, [expected['dynamics']]);
    expect(DouyinDanmakuProtocol.initialInformation(recorded(), roomId: '456'), isEmpty);
    expect(DouyinDanmakuProtocol.initialInformation(List.filled(2097153, 0), roomId: '123'), isEmpty);
    final chat =
        (ProtoWriter()
              ..string(1, 'WebcastChatMessage')
              ..bytes(2, const []))
            .toBytes();
    expect(DouyinDanmakuProtocol.initialInformation((ProtoWriter()..bytes(1, chat)).toBytes(), roomId: '123'), isEmpty);
    final uri = DouyinDanmakuProtocol.informationSnapshot(args, now: DateTime.utc(2026, 10, 30));
    expect(uri.host, 'live.douyin.com');
    expect(uri.queryParameters['cursor'], '');
    expect(uri.queryParameters['signature'], isNull);
    expect(uri.queryParameters['a_bogus'], isNull);
  });

  test('initial metadata arrives without replaying chat; a closed connection rejects the late snapshot', () async {
    for (final closeEarly in [false, true]) {
      final http = _Http();
      final socket = _Socket();
      final connection = DouyinDanmakuConnection(
        http: http,
        connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) async =>
            socket,
      );
      final events = <DanmakuEvent>[];
      final subscription = connection.events.listen(events.add);
      await connection.connect(args);
      await flush();
      expect(connection.isConnected, isTrue);
      expect(http.request.url.queryParameters['room_id'], '123');
      if (closeEarly) await connection.close();
      http.response.complete(LiveResponse(status: 200, bytes: recorded(), url: http.request.url));
      await flush();
      final received = events.whereType<DanmakuReceived>().map((event) => event.message).toList();
      expect(received, hasLength(closeEarly ? 0 : 2));
      expect(events.whereType<DanmakuClosed>(), isEmpty);
      if (closeEarly) expect(http.request.cancel?.isCancelled, isTrue);
      await connection.close();
      await subscription.cancel();
    }
  });
}

final class _Http implements LiveHttp {
  late LiveRequest request;
  final response = Completer<LiveResponse>();
  @override
  Future<LiveResponse> send(LiveRequest request) {
    this.request = request;
    return response.future;
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();
  @override
  void close() {}
}

final class _Socket implements SocketChannel {
  final incoming = StreamController<Object?>();
  @override
  Stream<Object?> get stream => incoming.stream;
  @override
  void add(Object data) {}
  @override
  Future<void> close([int? code, String? reason]) async {}
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
}
