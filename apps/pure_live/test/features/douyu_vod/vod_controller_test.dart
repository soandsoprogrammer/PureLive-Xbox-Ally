import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/features/douyu_vod/vod_controller.dart';
import 'package:pure_live/features/douyu_vod/vod_progress.dart';

import '../live_play/live_play_support.dart';
import 'vod_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DouyuVodSigner signer;
  setUpAll(() => signer = testSigner());

  test('resume and rendition switch preserve position, volume and restore pause intent', () async {
    var stored = '[]';
    final progress = DouyuVodProgressStore(read: () async => stored, write: (value) async => stored = value);
    await progress.save(firstVideo, const Duration(seconds: 93));
    final engine = FakeEngine();
    final controller = DouyuVodController(
      source: FakeVodSource(signer),
      session: fakeSession(engine),
      progress: progress,
      initialVolume: 0.4,
    );
    await controller.open(firstVideo.id);
    expect(controller.error, isNull);
    expect(engine.opens.single.start, const Duration(seconds: 93));
    expect(controller.session.state.onDemand, isTrue);
    expect(controller.qualityId, 'high', reason: 'unavailable super tier must never be selected');
    engine.emit(const EnginePosition(Duration(seconds: 93)));
    await pumpEventQueue();
    engine.emit(const EnginePosition(Duration(seconds: 150)));
    await pumpEventQueue();
    await controller.session.setVolume(0.27);
    await controller.session.pause();
    final opened = Completer<void>();
    final release = Completer<void>();
    engine.onOpen = (_) async {
      opened.complete();
      await release.future;
    };
    final changing = controller.selectQuality('normal');
    await opened.future;
    await pumpEventQueue();
    expect(controller.session.state.status, PlaybackStatus.opening);
    release.complete();
    await changing;
    expect(engine.opens.last.start, const Duration(seconds: 150));
    expect(controller.session.state.status, PlaybackStatus.paused);
    expect(controller.session.state.volume, 0.27);
    expect(controller.qualityId, 'normal');
    expect(controller.error, isNull);
    controller.dispose();
    await pumpEventQueue();
    final history = await progress.list();
    expect(history.single.position, const Duration(seconds: 150));
    expect(stored, isNot(contains('cdn.example')));
    expect(stored, isNot(contains('sign')));
  });

  test('old nonzero clock events cannot acknowledge a pending seek or corrupt exit history', () async {
    var stored = '[]';
    final progress = DouyuVodProgressStore(read: () async => stored, write: (value) async => stored = value);
    final engine = FakeEngine();
    final controller = DouyuVodController(
      source: FakeVodSource(signer),
      session: fakeSession(engine),
      progress: progress,
    );
    await controller.open(firstVideo.id);
    engine.emit(const EnginePosition(Duration(seconds: 12)));
    await pumpEventQueue();
    await controller.seek(const Duration(minutes: 20));
    engine.emit(const EnginePosition(Duration(seconds: 13)));
    await pumpEventQueue();
    expect(controller.position, const Duration(minutes: 20));
    await controller.record();
    expect((await progress.list()).single.position, const Duration(minutes: 20));
    engine.emit(const EnginePosition(Duration(minutes: 20, milliseconds: 100)));
    await pumpEventQueue();
    engine.emit(const EnginePosition(Duration(minutes: 20, seconds: 5)));
    await pumpEventQueue();
    expect(controller.position, const Duration(minutes: 20, seconds: 5));
    controller.dispose();
    await pumpEventQueue();
  });

  test('replaced and disposed details cannot open media or replace the selected video', () async {
    final source = FakeVodSource(signer);
    final response = source.details[firstVideo.id] = Completer<DouyuVodDetail>();
    final engine = FakeEngine();
    final controller = DouyuVodController(
      source: source,
      session: fakeSession(engine),
      progress: DouyuVodProgressStore(read: () async => null, write: (_) async {}),
    );
    final first = controller.open(firstVideo.id);
    await pumpEventQueue();
    await controller.open(secondVideo.id);
    response.complete(DouyuVodDetail(video: firstVideo, signer: signer));
    await first;
    expect(controller.video?.id, secondVideo.id);
    expect(engine.opens, hasLength(1));
    expect(engine.opens.single.uri.path, contains(secondVideo.id));
    final delayed = source.details[firstVideo.id] = Completer<DouyuVodDetail>();
    final pending = controller.open(firstVideo.id);
    await pumpEventQueue();
    controller.dispose();
    delayed.complete(DouyuVodDetail(video: firstVideo, signer: signer));
    await pending;
    expect(engine.opens, hasLength(1));
  });

  test('history serializes concurrent writes, bounds entries, clears and never stores signed input', () async {
    var stored = '[]';
    final progress = DouyuVodProgressStore(read: () async => stored, write: (value) async => stored = value);
    await Future.wait([
      for (var index = 0; index < 205; index++)
        progress.save(
          DouyuVodVideo(id: 'Replay${index.toString().padLeft(10, '0')}', title: '录像$index'),
          Duration(seconds: index),
        ),
    ]);
    expect(await progress.list(), hasLength(200));
    expect(((jsonDecode(stored) as List).first as Map<String, dynamic>)['id'], 'Replay0000000204');
    await progress.save(firstVideo, const Duration(seconds: 999), completed: true);
    expect((await progress.list()).first.position, Duration.zero);
    await progress.clear();
    expect(await progress.list(), isEmpty);
    stored = '{broken';
    expect(await progress.list(), isEmpty);
  });
}
