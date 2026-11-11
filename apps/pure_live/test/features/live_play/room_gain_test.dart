import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/shared/rooms/room_gain.dart';

import '../multiview/multiview_support.dart';
import 'live_play_support.dart';

void main() {
  test('issue108 signed room gains override global and reset independently of volume', () async {
    final store = await memoryStore();
    try {
      final a = pickRoom('a');
      final b = pickRoom('b');
      await store.settings.set(Settings.volumeBoostDb, 6);
      expect(RoomGain.effective(store.settings, a), 6);
      await RoomGain.save(store.settings, a, -9);
      expect(RoomGain.effective(store.settings, a), -9);
      expect(RoomGain.effective(store.settings, b), 6);
      expect(store.settings.get(Settings.roomVolumes), isEmpty);
      await RoomGain.save(store.settings, a, 0);
      expect(RoomGain.effective(store.settings, a), 0, reason: 'zero is a real override');
      await RoomGain.save(store.settings, a, null);
      expect(RoomGain.effective(store.settings, a), 6);
      expect(RoomGain.overrideOf(store.settings, a), isNull);
    } finally {
      await store.close();
    }
  });
  test('issue108 multi-view reuse and live changes apply only the matching room gain', () async {
    final store = await memoryStore();
    final engines = <FakeEngine>[];
    final controller = multiviewController(store, RoomsSite(), engines: engines);
    try {
      await store.settings.set(Settings.volumeBoostDb, 3);
      await RoomGain.save(store.settings, pickRoom('a'), -6);
      await controller.start();
      await controller.assign(0, pickRoom('a'));
      expect(engines.single.opens.last.volumeGainDb, -6);
      await RoomGain.save(store.settings, pickRoom('a'), 9);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(engines.single.gains.last, 9);
      await controller.assign(0, pickRoom('b'));
      expect(engines.single.opens.last.volumeGainDb, 3);
      await RoomGain.save(store.settings, pickRoom('a'), -12);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(engines.single.gains.last, 3);
    } finally {
      controller.dispose();
      await store.close();
    }
  });
}
