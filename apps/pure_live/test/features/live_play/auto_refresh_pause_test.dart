import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';

import '../multiview/multiview_support.dart';
import 'live_play_support.dart';

class _HeldUrls extends FakeSite {
  new() : super(liveRoom());
  Completer<List<String>>? held;
  final entered = Completer<void>();

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    if (held case final pending?) {
      entered.complete();
      return await pending.future;
    }
    return await super.getPlayUrls(detail: detail, quality: quality);
  }
}

void main() {
  test('issue115 automatic full refresh preserves a pause during URL lookup', () async {
    final store = await memoryStore();
    final site = _HeldUrls();
    final engine = FakeEngine();
    final session = fakeSession(engine);
    final controller = LiveRoomController(
      room: liveRoom(),
      site: site,
      session: session,
      danmaku: FakeDanmaku(),
      danmakuSupported: false,
      store: store,
      refreshInterval: Duration.zero,
    );
    try {
      await controller.start();
      expect(engine.opens, hasLength(1));
      site.held = Completer<List<String>>();
      final refresh = controller.load(preservePause: true);
      await site.entered.future;
      await session.pause();
      site.held!.complete(['https://a.example/reloaded.flv']);
      await refresh;
      expect(session.state.status, PlaybackStatus.paused);
      expect(engine.opens, hasLength(1));
      expect(controller.stage, RoomStage.playing);
    } finally {
      controller.dispose();
      await session.dispose();
      await store.close();
    }
  });
}
