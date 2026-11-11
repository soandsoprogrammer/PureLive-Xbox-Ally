import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';

import 'support/fake_engine.dart';

PlaybackRequest request(String host) => PlaybackRequest(
  site: 'fixture',
  plan: PlaybackPlan.of(LivePlayUrlResolution.lines([LivePlayLine('https://$host.example/live.flv')])),
);

const timings = SessionTimings(
  sourceOpen: Duration(seconds: 1),
  engineRelease: Duration(seconds: 1),
  liveRetryDelays: [],
);

void main() {
  test('A17.24: bounded disposal and confirmed resource retirement are distinct', () {
    fakeAsync((async) {
      final pending = Completer<void>();
      final engine = FakeEngine()..onDispose = () => pending.future;
      final session = PlaybackSession(engine: () async => engine, opener: MediaOpener(), timings: timings);
      unawaited(session.open(request('a')));
      async.flushMicrotasks();
      var disposed = false;
      var released = false;
      unawaited(session.dispose().then((_) => disposed = true));
      unawaited(session.waitForResourceRelease().then((_) => released = true));
      async.elapse(const Duration(seconds: 2));
      expect(disposed, isTrue);
      expect(released, isFalse);
      pending.complete();
      async.flushMicrotasks();
      expect(released, isTrue);
    });
  });

  test('A17.24: confirmed retirement waits for a late native creation', () {
    fakeAsync((async) {
      final pending = Completer<PlayerEngine>();
      final session = PlaybackSession(engine: () => pending.future, opener: MediaOpener(), timings: timings);
      unawaited(session.open(request('a')));
      async.flushMicrotasks();
      var released = false;
      unawaited(session.waitForResourceRelease().then((_) => released = true));
      async.elapse(const Duration(seconds: 2));
      expect(released, isFalse);
      final late = FakeEngine();
      pending.complete(late);
      async.flushMicrotasks();
      expect(late.disposed, isTrue);
      expect(released, isTrue);
    });
  });

  test('A17.24: failed native cleanup cannot prove resources released', () {
    fakeAsync((async) {
      final engine = FakeEngine()..onDispose = () async => throw StateError('controlled cleanup failure');
      final session = PlaybackSession(engine: () async => engine, opener: MediaOpener(), timings: timings);
      unawaited(session.open(request('a')));
      async.flushMicrotasks();
      Object? failure;
      unawaited(
        session.waitForResourceRelease().then<void>(
          (_) {},
          onError: (Object error) {
            failure = error;
          },
        ),
      );
      async.elapse(const Duration(seconds: 2));
      expect(failure, isA<StateError>());
    });
  });
  test('G02.13: a timed-out factory does not poison retry and its late player is retired', () {
    fakeAsync((async) {
      final pending = Completer<PlayerEngine>();
      final working = FakeEngine();
      var calls = 0;
      final session = PlaybackSession(
        opener: MediaOpener(),
        timings: timings,
        engine: () => ++calls == 1 ? pending.future : Future.value(working),
      );
      unawaited(session.open(request('a')));
      async.elapse(const Duration(seconds: 2));
      expect(session.state.status, PlaybackStatus.error);
      unawaited(session.retry());
      async.flushMicrotasks();
      expect(calls, 2);
      expect(session.engine, same(working));
      expect(session.state.status, PlaybackStatus.playing);
      final late = FakeEngine();
      pending.complete(late);
      async.flushMicrotasks();
      expect(late.disposed, isTrue);
      expect(session.engine, same(working));
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.13: hung factories share the retirement allocation limit and late release frees a slot', () {
    fakeAsync((async) {
      final pending = [Completer<PlayerEngine>(), Completer<PlayerEngine>()];
      final working = FakeEngine();
      var calls = 0;
      final session = PlaybackSession(
        opener: MediaOpener(),
        timings: timings,
        engine: () {
          final index = calls++;
          return index < 2 ? pending[index].future : Future.value(working);
        },
      );
      for (var i = 0; i < 5; i++) {
        unawaited(i == 0 ? session.open(request('a')) : session.retry());
        async.elapse(const Duration(seconds: 2));
      }
      expect(calls, 2);
      expect((session.state.error! as PlayerException).code, 'engine_release_pending');
      final late = FakeEngine();
      pending.first.complete(late);
      async.flushMicrotasks();
      expect(late.disposed, isTrue);
      unawaited(session.retry());
      async.flushMicrotasks();
      expect(calls, 3);
      expect(session.engine, same(working));
      pending.last.complete(FakeEngine());
      async.flushMicrotasks();
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.13: a room opened during stop uses a fresh engine before the old stop replies', () {
    fakeAsync((async) {
      final pending = Completer<void>();
      final engines = <FakeEngine>[];
      final session = PlaybackSession(
        opener: MediaOpener(),
        timings: timings,
        engine: () async {
          final e = FakeEngine();
          engines.add(e);
          return e;
        },
      );
      unawaited(session.open(request('a')));
      async.flushMicrotasks();
      engines.first.onStop = () => pending.future;
      engines.first.onDispose = () => pending.future;
      unawaited(session.stop());
      async.flushMicrotasks();
      unawaited(session.open(request('b')));
      async.flushMicrotasks();
      expect(engines, hasLength(2));
      expect(session.engine, same(engines.last));
      expect(session.state.status, PlaybackStatus.playing);
      pending.complete();
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 2));
      expect(session.engine, same(engines.last));
      expect(engines.last.disposed, isFalse);
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.13: stop completes at its deadline and the next room never reuses its hung engine', () {
    fakeAsync((async) {
      final pending = Completer<void>();
      final engines = <FakeEngine>[];
      final session = PlaybackSession(
        opener: MediaOpener(),
        timings: timings,
        engine: () async {
          final e = FakeEngine();
          engines.add(e);
          return e;
        },
      );
      unawaited(session.open(request('a')));
      async.flushMicrotasks();
      engines.first.onStop = () => pending.future;
      engines.first.onDispose = () => pending.future;
      var stopped = false;
      unawaited(session.stop().then((_) => stopped = true));
      async.elapse(const Duration(seconds: 2));
      expect(stopped, isTrue);
      expect(session.engine, isNull);
      unawaited(session.open(request('b')));
      async.flushMicrotasks();
      expect(engines, hasLength(2));
      expect(session.state.status, PlaybackStatus.playing);
      pending.complete();
      async.flushMicrotasks();
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.13: dispose is bounded while a factory is hung and owns its eventual player exactly once', () {
    fakeAsync((async) {
      final pending = Completer<PlayerEngine>();
      final session = PlaybackSession(opener: MediaOpener(), timings: timings, engine: () => pending.future);
      unawaited(session.open(request('a')));
      async.flushMicrotasks();
      var done = false;
      final closing = session.dispose();
      unawaited(closing.then((_) => done = true));
      async.elapse(const Duration(seconds: 2));
      expect(done, isTrue);
      expect(session.dispose(), same(closing));
      final late = FakeEngine();
      pending.complete(late);
      async.flushMicrotasks();
      expect(late.disposed, isTrue);
      expect(late.opens, isEmpty);
    });
  });

  test('G02.13: dispose bypasses a hung stop and retires the engine once', () {
    fakeAsync((async) {
      final pending = Completer<void>();
      final engine = FakeEngine()
        ..onStop = (() => pending.future)
        ..onDispose = (() => pending.future);
      final session = PlaybackSession(opener: MediaOpener(), timings: timings, engine: () async => engine);
      unawaited(session.open(request('a')));
      async.flushMicrotasks();
      var done = false;
      final closing = session.dispose();
      unawaited(closing.then((_) => done = true));
      async.elapse(const Duration(seconds: 2));
      expect(done, isTrue);
      expect(engine.disposed, isTrue);
      expect(session.dispose(), same(closing));
      pending.complete();
      async.flushMicrotasks();
    });
  });
}
