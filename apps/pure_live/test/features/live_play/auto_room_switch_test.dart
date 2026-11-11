import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/shared/rooms/auto_room_switch.dart';

import '../multiview/multiview_support.dart';

class _Site extends RoomsSite {
  final List<String> asked = [];
  final Map<String, Completer<LiveRoom>> held = {};

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    asked.add(roomId);
    if (held[roomId] case final gate?) return await gate.future;
    return await super.getRoomDetail(roomId: roomId);
  }
}

Future<LiveStore> _store(
  WidgetTester tester, {
  bool enabled = true,
  List<String> rooms = const ['a', 'b', 'c'],
}) async => (await tester.runAsync(() async {
  final store = await memoryStore();
  await store.settings.set(Settings.autoSwitchLiveFollows, enabled);
  for (final id in rooms) {
    await store.follows.add(pickRoom(id));
  }
  return store;
}))!;

void _ended(AutoRoomSwitch automatic, String id) => automatic.update(
  room: pickRoom(id, status: LiveStatus.offline),
  playback: const PlaybackState(),
  resolving: false,
  unavailable: false,
);

Future<void> _tick(WidgetTester tester, [int seconds = 1]) async {
  await tester.pump(Duration(seconds: seconds));
  await tester.pump();
}

void main() {
  testWidgets('suspending a lookup does not blacklist an untried room on return', (tester) async {
    final store = await _store(tester, rooms: ['a', 'b']);
    final gate = Completer<LiveRoom>();
    final site = _Site()..held['b'] = gate;
    final switched = <LiveRoom>[];
    final automatic = AutoRoomSwitch(store: store, siteOf: (_) => site, onSwitch: switched.add, maySwitch: () => true)
      ..setRoom(pickRoom('a'));
    _ended(automatic, 'a');
    await _tick(tester);
    automatic.suspend(value: true);
    gate.complete(pickRoom('b'));
    await _tick(tester);
    expect(switched, isEmpty);
    site.held.clear();
    automatic.suspend(value: false);
    await _tick(tester);
    expect(switched.map((room) => room.roomId), ['b']);
    automatic.dispose();
    await tester.runAsync(store.close);
  });

  testWidgets('default off does not query or replace an ended room', (tester) async {
    final store = await _store(tester, enabled: false);
    final site = _Site();
    final switched = <LiveRoom>[];
    final automatic = AutoRoomSwitch(store: store, siteOf: (_) => site, onSwitch: switched.add, maySwitch: () => true)
      ..setRoom(pickRoom('a'));
    _ended(automatic, 'a');
    await _tick(tester, 60);
    expect(site.asked, isEmpty);
    expect(switched, isEmpty);
    automatic.dispose();
    await tester.runAsync(store.close);
  });

  testWidgets('fresh status skips offline candidates and preserves follow order', (tester) async {
    final store = await _store(tester);
    final site = _Site()..offline.add('b');
    final switched = <LiveRoom>[];
    final automatic = AutoRoomSwitch(store: store, siteOf: (_) => site, onSwitch: switched.add, maySwitch: () => true)
      ..setRoom(pickRoom('a'));
    _ended(automatic, 'a');
    await _tick(tester);
    expect(site.asked, ['b', 'c']);
    expect(switched.map((r) => r.roomId), ['c']);
    automatic.dispose();
    await tester.runAsync(store.close);
  });

  for (final state in [
    const PlaybackState(status: PlaybackStatus.opening),
    const PlaybackState(status: PlaybackStatus.buffering, recovery: 2),
    const PlaybackState(status: PlaybackStatus.paused),
    const PlaybackState(status: PlaybackStatus.stopped),
    const PlaybackState(status: PlaybackStatus.completed, onDemand: true),
    const PlaybackState(
      status: PlaybackStatus.error,
      error: PlayerException(message: 'offline', type: PlayerErrorType.network, code: networkLostCode),
    ),
  ]) {
    testWidgets('does not interrupt ${state.status.name} ${state.recovery} ${state.error}', (tester) async {
      final store = await _store(tester);
      final site = _Site();
      final switched = <LiveRoom>[];
      final automatic = AutoRoomSwitch(store: store, siteOf: (_) => site, onSwitch: switched.add, maySwitch: () => true)
        ..setRoom(pickRoom('a'))
        ..update(room: pickRoom('a'), playback: state, resolving: false, unavailable: false);
      await _tick(tester, 60);
      expect(site.asked, isEmpty);
      expect(switched, isEmpty);
      automatic.dispose();
      await tester.runAsync(store.close);
    });
  }

  testWidgets('recovery exhausted switches but a round never retries failed rooms', (tester) async {
    final store = await _store(tester, rooms: ['a', 'b']);
    final site = _Site();
    final switched = <String>[];
    late final AutoRoomSwitch automatic;
    automatic = AutoRoomSwitch(
      store: store,
      siteOf: (_) => site,
      onSwitch: (room) {
        switched.add(room.roomId);
        automatic.setRoom(room, automatic: true);
      },
      maySwitch: () => true,
    )..setRoom(pickRoom('a'));
    void failed(String id) => automatic.update(
      room: pickRoom(id),
      playback: const PlaybackState(status: PlaybackStatus.error),
      resolving: false,
      unavailable: false,
    );
    failed('a');
    await _tick(tester);
    expect(switched, ['b']);
    failed('b');
    await _tick(tester);
    expect(automatic.exhausted, isTrue);
    for (var i = 0; i < 3; i++) {
      failed('b');
      await _tick(tester, 60);
    }
    expect(switched, ['b']);
    expect(site.asked, ['b']);
    automatic.dispose();
    await tester.runAsync(store.close);
  });

  for (final cancel in ['manual room', 'pause', 'disable', 'dispose', 'suspend', 'unfollow']) {
    testWidgets('$cancel invalidates a late candidate lookup', (tester) async {
      final store = await _store(tester, rooms: ['a', 'b']);
      final gate = Completer<LiveRoom>();
      final site = _Site()..held['b'] = gate;
      final switched = <LiveRoom>[];
      final automatic = AutoRoomSwitch(store: store, siteOf: (_) => site, onSwitch: switched.add, maySwitch: () => true)
        ..setRoom(pickRoom('a'));
      _ended(automatic, 'a');
      await _tick(tester);
      expect(site.asked, ['b']);
      switch (cancel) {
        case 'manual room':
          automatic.setRoom(pickRoom('manual'));
        case 'pause':
          automatic.update(
            room: pickRoom('a'),
            playback: const PlaybackState(status: PlaybackStatus.paused),
            resolving: false,
            unavailable: false,
          );
        case 'disable':
          await tester.runAsync(() => store.settings.set(Settings.autoSwitchLiveFollows, false));
        case 'dispose':
          automatic.dispose();
        case 'suspend':
          automatic.suspend(value: true);
        case 'unfollow':
          await tester.runAsync(() => store.follows.remove(pickRoom('b')));
      }
      gate.complete(pickRoom('b'));
      await _tick(tester);
      expect(switched, isEmpty);
      if (cancel != 'dispose') automatic.dispose();
      await tester.runAsync(store.close);
    });
  }

  testWidgets('simultaneous cells reserve different targets and skip occupied rooms', (tester) async {
    final store = await _store(tester, rooms: ['a', 'b', 'busy', 'c', 'd']);
    final site = _Site();
    final group = AutoRoomSwitchGroup();
    final occupied = AutoRoomSwitch(
      store: store,
      siteOf: (_) => site,
      onSwitch: (_) {},
      maySwitch: () => true,
      group: group,
    )..setRoom(pickRoom('busy'));
    final targets = <String>[];
    final automatic = <AutoRoomSwitch>[];
    for (final id in ['a', 'b']) {
      late final AutoRoomSwitch cell;
      cell = AutoRoomSwitch(
        store: store,
        siteOf: (_) => site,
        group: group,
        maySwitch: () => true,
        onSwitch: (room) {
          targets.add(room.roomId);
          cell.setRoom(room, automatic: true);
        },
      )..setRoom(pickRoom(id));
      automatic.add(cell);
      _ended(cell, id);
    }
    await _tick(tester);
    expect(targets.toSet(), {'c', 'd'});
    expect(targets, hasLength(2));
    expect(site.asked, isNot(contains('busy')));
    for (final cell in [...automatic, occupied]) {
      cell.dispose();
    }
    await tester.runAsync(store.close);
  });

  testWidgets('lookup timeout exhausts once and its eventual response is ignored', (tester) async {
    final store = await _store(tester);
    final gate = Completer<LiveRoom>();
    final site = _Site()..held['b'] = gate;
    final switched = <LiveRoom>[];
    final automatic = AutoRoomSwitch(store: store, siteOf: (_) => site, onSwitch: switched.add, maySwitch: () => true)
      ..setRoom(pickRoom('a'));
    _ended(automatic, 'a');
    await _tick(tester);
    await _tick(tester, 10);
    expect(automatic.exhausted, isTrue);
    gate.complete(pickRoom('b'));
    await _tick(tester, 60);
    expect(switched, isEmpty);
    expect(site.asked, ['b']);
    automatic.dispose();
    await tester.runAsync(store.close);
  });
}
