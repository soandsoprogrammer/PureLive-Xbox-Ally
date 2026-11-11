import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/shared/rooms/auto_room_switch.dart';

import '../multiview/multiview_support.dart';

void main() {
  for (final cancel in ['pause', 'disable', 'manual room', 'suspend', 'dispose']) {
    testWidgets('issue115 $cancel cancels confirmations without opening another room', (tester) async {
      final store = (await tester.runAsync(() async {
        final store = await memoryStore();
        await store.settings.set(Settings.autoSwitchLiveFollows, true);
        await store.follows.add(pickRoom('a'));
        await store.follows.add(pickRoom('b'));
        return store;
      }))!;
      final switched = <String>[];
      var refreshes = 0;
      final automatic =
          AutoRoomSwitch(
              store: store,
              siteOf: (_) => RoomsSite(),
              maySwitch: () => true,
              onSwitch: (room) => switched.add(room.roomId),
              onRefresh: () async {
                refreshes++;
              },
            )
            ..setRoom(pickRoom('a'))
            ..update(
              room: pickRoom('a'),
              playback: const PlaybackState(status: PlaybackStatus.error),
              resolving: false,
              unavailable: false,
            );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(refreshes, 1);
      switch (cancel) {
        case 'pause':
          automatic.update(
            room: pickRoom('a'),
            playback: const PlaybackState(status: PlaybackStatus.paused),
            resolving: false,
            unavailable: false,
          );
        case 'disable':
          await tester.runAsync(() => store.settings.set(Settings.autoSwitchLiveFollows, false));
        case 'manual room':
          automatic.setRoom(pickRoom('manual'));
        case 'suspend':
          automatic.suspend(value: true);
        case 'dispose':
          automatic.dispose();
      }
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(refreshes, 1);
      expect(switched, isEmpty);
      if (cancel != 'dispose') automatic.dispose();
      await tester.runAsync(store.close);
    });
  }

  testWidgets('issue115 refreshes the current room twice with grace before switching', (tester) async {
    final store = (await tester.runAsync(() async {
      final store = await memoryStore();
      await store.settings.set(Settings.autoSwitchLiveFollows, true);
      await store.follows.add(pickRoom('a'));
      await store.follows.add(pickRoom('b'));
      return store;
    }))!;
    final switched = <String>[];
    var refreshes = 0;
    final automatic =
        AutoRoomSwitch(
            store: store,
            siteOf: (_) => RoomsSite(),
            maySwitch: () => true,
            onSwitch: (room) => switched.add(room.roomId),
            onRefresh: () async {
              refreshes++;
            },
          )
          ..setRoom(pickRoom('a'))
          ..update(
            room: pickRoom('a'),
            playback: const PlaybackState(status: PlaybackStatus.error),
            resolving: false,
            unavailable: false,
          );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(refreshes, 1);
    expect(switched, isEmpty);
    await tester.pump(const Duration(seconds: 19));
    expect(refreshes, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(refreshes, 2);
    expect(switched, isEmpty);
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();
    expect(switched, ['b']);
    automatic.dispose();
    await tester.runAsync(store.close);
  });
}
