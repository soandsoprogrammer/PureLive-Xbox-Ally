import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';

import '../../support.dart';
import '../live_play/live_play_support.dart';
import 'multiview_support.dart';

class _HeldSite extends RoomsSite {
  final Map<String, Completer<LiveRoom>> held = {};
  final List<String> asked = [];

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    asked.add(roomId);
    if (held[roomId] case final gate?) return await gate.future;
    return await super.getRoomDetail(roomId: roomId);
  }
}

Future<LiveStore> _store(WidgetTester tester) async => (await tester.runAsync(() async {
  final store = await memoryStore();
  await store.settings.set(Settings.autoSwitchLiveFollows, true);
  for (final id in ['a', 'b', 'c', 'd']) {
    await store.follows.add(pickRoom(id));
  }
  return store;
}))!;

Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<void> _confirmTwice(WidgetTester tester) async {
  for (var i = 0; i < 43; i++) {
    await _tick(tester);
  }
}

void main() {
  setUpAll(loadStrings);

  testWidgets('automatic replacement preserves cell identity, volume, mute and sound focus', (tester) async {
    final store = await _store(tester);
    final site = RoomsSite()..offline.add('a');
    final controller = multiviewController(store, site);
    await controller.start();
    await controller.assign(1, pickRoom('c'));
    await controller.assign(0, pickRoom('a'));
    await controller.setVolume(0, 0.6);
    controller.toggleMuteAll();
    final id = controller.cells[0].id;
    final layout = controller.layout;
    expect(controller.audioIndex, 1);
    await _confirmTwice(tester);
    expect(controller.cells[0].room!.roomId, 'b');
    expect(controller.cells[0].stage, CellStage.playing);
    expect(controller.cells[0].id, id);
    expect(controller.cells[0].volume, 0.6);
    expect(controller.cells[0].playback.volume, 0);
    expect(controller.cells[1].playback.volume, 0);
    expect(controller.allMuted, isTrue);
    expect(controller.audioIndex, 1);
    expect(controller.layout, layout);
    controller.dispose();
    await tester.runAsync(store.close);
  });

  testWidgets('simultaneous offline cells choose distinct followed rooms', (tester) async {
    final store = await _store(tester);
    final site = RoomsSite()..offline.addAll(['a', 'b']);
    final controller = multiviewController(store, site);
    await controller.start();
    await controller.assign(0, pickRoom('a'));
    await controller.assign(1, pickRoom('b'));
    await _confirmTwice(tester);
    expect(controller.cells.take(2).map((cell) => cell.room!.roomId).toSet(), {'c', 'd'});
    expect(controller.cells.take(2).every((cell) => cell.playing), isTrue);
    controller.dispose();
    await tester.runAsync(store.close);
  });

  testWidgets('removing a cell invalidates its pending lookup and permits later reuse', (tester) async {
    final store = await _store(tester);
    final gate = Completer<LiveRoom>();
    final site = _HeldSite()
      ..offline.add('a')
      ..held['b'] = gate;
    final controller = multiviewController(store, site);
    await controller.start();
    await controller.assign(0, pickRoom('a'));
    await _confirmTwice(tester);
    expect(site.asked, contains('b'));
    await controller.remove(0);
    gate.complete(pickRoom('b'));
    await _tick(tester);
    expect(controller.cells[0].stage, CellStage.empty);
    await controller.assign(0, pickRoom('c'));
    expect(controller.cells[0].room!.roomId, 'c');
    expect(controller.cells[0].playing, isTrue);
    controller.dispose();
    await tester.runAsync(store.close);
  });

  testWidgets('periodic confirmation detects an ended stream without a player error', (tester) async {
    final store = await _store(tester);
    final site = RoomsSite();
    final engines = <FakeEngine>[];
    final controller = multiviewController(store, site, engines: engines);
    await controller.start();
    await controller.assign(0, pickRoom('a'));
    final session = controller.cells[0].session;
    site.offline.add('a');
    for (var i = 0; i < 104; i++) {
      for (final engine in engines) {
        engine.advance();
      }
      await _tick(tester);
    }
    expect(controller.cells[0].room!.roomId, 'b');
    expect(controller.cells[0].session, same(session));
    controller.dispose();
    await tester.runAsync(store.close);
  });
}
