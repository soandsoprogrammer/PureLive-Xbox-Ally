import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/src/buffering_probe.dart';

void main() {
  test('one fixed-property snapshot keeps its deadline despite repeated flags', () {
    fakeAsync((async) {
      final reads = <String>[];
      final lines = <String>[];
      final probe = NativeBufferingProbe(
        read: (name) async {
          reads.add(name);
          return name == 'core-idle' ? 'yes' : '0';
        },
        report: lines.add,
      )..update(buffering: true);
      async.elapse(const Duration(seconds: 2));
      probe.update(buffering: true);
      async.elapse(const Duration(seconds: 1));
      expect(reads, NativeBufferingProbe.properties);
      expect(lines.single, contains('core-idle=yes'));
      expect(lines.single, contains('time-pos=0.0'));
      probe.update(buffering: true);
      async.elapse(const Duration(seconds: 20));
      expect(lines, hasLength(1));
      probe.close();
    });
  });

  test('unavailable and malformed values cannot leak through a diagnostic', () {
    fakeAsync((async) {
      final lines = <String>[];
      final pending = Completer<String>();
      final probe = NativeBufferingProbe(
        read: (name) async => switch (name) {
          'time-pos' => await pending.future,
          'pause' => throw StateError('private failure'),
          'eof-reached' => 'NaN',
          'video-params/w' => 'Infinity',
          'video-params/h' => '1e50',
          'track-list/count' => '',
          'vo' => 'gpu',
          'vid' => 'auto',
          _ => 'https://example.invalid/private?token=not-a-real-token\nextra',
        },
        report: lines.add,
      )..update(buffering: true);
      async.elapse(const Duration(seconds: 4));
      expect(lines, hasLength(1));
      expect(lines.single, isNot(contains('private')));
      expect(lines.single, isNot(contains('token')));
      expect(lines.single, isNot(contains('\n')));
      expect(lines.single, contains('time-pos=?/timeout'));
      expect(lines.single, contains('pause=?/error'));
      expect(lines.single, contains('eof-reached=?/invalid'));
      expect(lines.single, contains('track-list/count=?/unavailable'));
      expect(lines.single, contains('vo=gpu'));
      expect(lines.single, contains('vid=auto'));
      pending.complete('123');
      async.flushMicrotasks();
      expect(lines, hasLength(1));
      probe.close();
    });
  });

  test('unbuffering, stopping, source replacement and disposal invalidate pending reads', () {
    for (final end in ['unbuffer', 'reset', 'close']) {
      fakeAsync((async) {
        final pending = Completer<String>();
        final lines = <String>[];
        final probe = NativeBufferingProbe(read: (_) => pending.future, report: lines.add)..update(buffering: true);
        async.elapse(const Duration(seconds: 3));
        switch (end) {
          case 'unbuffer':
            probe.update(buffering: false);
          case 'reset':
            probe.reset();
          case 'close':
            probe.close();
        }
        pending.complete('1');
        async.elapse(const Duration(seconds: 1));
        expect(lines, isEmpty, reason: end);
        probe.close();
      });
    }
  });
}
