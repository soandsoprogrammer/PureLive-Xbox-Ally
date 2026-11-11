import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_playback.dart';

final class _Engine implements PlayerEngine {
  final _events = StreamController<EngineEvent>.broadcast(sync: true);
  Completer<void>? stopGate;
  Completer<void>? disposeGate;
  Completer<void>? openGate;
  Completer<void>? seekGate;
  int opens = 0;
  int plays = 0;
  int seeks = 0;
  bool disposed = false;
  @override
  bool get reportsFrames => false;
  @override
  Stream<EngineEvent> get events => _events.stream;
  void complete() => _events.add(const EngineCompleted());
  @override
  Future<void> open(EngineMedia media) async {
    opens++;
    await openGate?.future;
    if (!disposed) _events.add(const EnginePlaying(playing: true));
  }

  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {
    await stopGate?.future;
  }

  @override
  Future<void> seek(Duration position) async {
    seeks++;
    await seekGate?.future;
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setAudioOnly({required bool enabled}) async {}
  @override
  Future<void> dispose() async {
    await disposeGate?.future;
    disposed = true;
    await _events.close();
  }
}

PlaybackRequest _request() => PlaybackRequest(
  site: 'wallpaper',
  volume: 0,
  plan: PlaybackPlan.of(
    LivePlayUrlResolution.lines(const [LivePlayLine('file:///generated/background.mp4')]),
    onDemand: true,
  ),
);
Future<void> _settle() => Future<void>.delayed(const Duration(seconds: 1));

void main() {
  test('holds coalesce during retirement; no new decoder before cleanup', () async {
    final engines = <_Engine>[];
    final visible = <PlaybackSession?>[];
    final player = TvWallpaperPlayback(
      createSession: () {
        final engine = _Engine();
        engines.add(engine);
        return PlaybackSession(engine: () async => engine, opener: MediaOpener());
      },
      request: _request,
      onSessionChanged: visible.add,
    );
    await player.setHeld(held: false);
    await _settle();
    expect(engines.single.opens, 1);
    engines.single.disposeGate = Completer<void>();
    final holding = player.setHeld(held: true);
    unawaited(player.setHeld(held: false));
    unawaited(player.setHeld(held: true));
    unawaited(player.setHeld(held: false));
    await _settle();
    expect(engines, hasLength(1));
    expect(player.session, isNull);
    engines.first.disposeGate!.complete();
    await holding;
    await _settle();
    expect(engines.first.disposed, isTrue);
    expect(engines, hasLength(2));
    expect(visible.last, same(player.session));
    await player.close();
  });

  test('a late completed-loop seek cannot play a held old wallpaper', () async {
    final engines = <_Engine>[];
    final player = TvWallpaperPlayback(
      createSession: () {
        final engine = _Engine();
        engines.add(engine);
        return PlaybackSession(engine: () async => engine, opener: MediaOpener());
      },
      request: _request,
      onSessionChanged: (_) {},
    );
    await player.setHeld(held: false);
    await _settle();
    final old = engines.single
      ..seekGate = Completer<void>()
      ..complete();
    await _settle();
    expect(old.seeks, 1);
    await player.setHeld(held: true);
    await player.setHeld(held: false);
    await _settle();
    final plays = old.plays;
    old.seekGate!.complete();
    await _settle();
    expect(old.plays, plays);
    expect(engines, hasLength(2));
    await player.close();
  });

  test('closing during open never adopts its late completion', () async {
    final engine = _Engine()..openGate = Completer<void>();
    final visible = <PlaybackSession?>[];
    final player = TvWallpaperPlayback(
      createSession: () => PlaybackSession(engine: () async => engine, opener: MediaOpener()),
      request: _request,
      onSessionChanged: visible.add,
    );
    await player.setHeld(held: false);
    await _settle();
    await player.close();
    engine.openGate!.complete();
    await _settle();
    expect(engine.disposed, isTrue);
    expect(player.session, isNull);
    expect(visible.last, isNull);
  });

  test('failed retirement disables cosmetic reallocation', () async {
    final engines = <_Engine>[];
    final player = TvWallpaperPlayback(
      createSession: () {
        final engine = _Engine();
        engines.add(engine);
        return PlaybackSession(engine: () async => engine, opener: MediaOpener());
      },
      request: _request,
      onSessionChanged: (_) {},
      releaseTimeout: const Duration(seconds: 1),
    );
    await player.setHeld(held: false);
    await _settle();
    engines.single.disposeGate = Completer<void>();
    await player.setHeld(held: true);
    await player.setHeld(held: false);
    expect(engines, hasLength(1));
    expect(player.session, isNull);
    engines.single.disposeGate!.complete();
    await _settle();
    await player.close();
  });

  test('unmounted resource wait survives bounded close grace until actual release', () async {
    final engine = _Engine();
    final player = TvWallpaperPlayback(
      createSession: () => PlaybackSession(engine: () async => engine, opener: MediaOpener()),
      request: _request,
      onSessionChanged: (_) {},
      releaseTimeout: const Duration(seconds: 1),
    );
    await player.setHeld(held: false);
    await _settle();
    engine.disposeGate = Completer<void>();
    var released = false;
    final retiring = player.waitForResourceRelease().then((_) => released = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(released, isFalse);
    expect(player.session, isNull);
    engine.disposeGate!.complete();
    await retiring;
    expect(engine.disposed, isTrue);
  });

  testWidgets('an older replaced room keeps the background held after its page exits', (tester) async {
    unawaited(TvWallpaperVideo.hold());
    await tester.pump();
    final oldRoom = Completer<void>();
    TvWallpaperVideo.trackCleanup(oldRoom.future);
    await tester.pump();
    TvWallpaperVideo.release();
    await tester.pump(const Duration(seconds: 7));
    expect(TvWallpaperVideo.holds.value, 1);
    oldRoom.complete();
    await tester.pump();
    expect(TvWallpaperVideo.holds.value, 0);
  });

  testWidgets('foreground timeout keeps the background held until real cleanup ends', (tester) async {
    unawaited(TvWallpaperVideo.hold());
    await tester.pump();
    final cleanup = Completer<void>();
    unawaited(TvWallpaperVideo.releaseAfter(cleanup.future));
    await tester.pump(const Duration(seconds: 13));
    expect(TvWallpaperVideo.holds.value, 1);
    cleanup.complete();
    await tester.pump();
    expect(TvWallpaperVideo.holds.value, 0);
  });
}
