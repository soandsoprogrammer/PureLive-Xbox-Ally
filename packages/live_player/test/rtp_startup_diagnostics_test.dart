import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_player/src/mpv_input.dart';

void main() {
  final rtp = Uri.parse('rtp://127.0.0.1:49817');
  const packet = 'non-existing PPS 0 referenced';

  test('RTP can receive its first video after the ordinary diagnostic window', () {
    fakeAsync((async) {
      final errors = <PlayerException>[];
      final gate = NativeDiagnosticGate(onError: errors.add)
        ..beginOpen(decoderStartupWindow: mpvDecoderStartupWindow(rtp))
        ..finishOpen()
        ..playback(playing: true, buffering: true)
        ..audioFrame()
        ..log('ffmpeg/video', 'error', packet);
      async.elapse(const Duration(seconds: 2));
      expect(errors, isEmpty);
      async.elapse(const Duration(seconds: 1));
      gate
        ..videoFrame()
        ..playback(playing: true, buffering: false);
      async.elapse(const Duration(seconds: 3));
      expect(errors, isEmpty);
      gate.close();
    });
  });

  test('repeated startup logs cannot extend the bounded wait for missing video', () {
    fakeAsync((async) {
      final errors = <PlayerException>[];
      final gate = NativeDiagnosticGate(onError: errors.add)
        ..beginOpen(decoderStartupWindow: mpvDecoderStartupWindow(rtp))
        ..finishOpen()
        ..playback(playing: true, buffering: true)
        ..audioFrame();
      for (var index = 0; index < 4; index++) {
        gate.log('ffmpeg/video', 'error', packet);
        async.elapse(const Duration(seconds: 1));
      }
      expect(errors, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(errors.single.code, 'video_decoder_runtime');
      gate.close();
    });
  });

  test('a failure after first video retains the ordinary runtime window', () {
    fakeAsync((async) {
      final errors = <PlayerException>[];
      final gate = NativeDiagnosticGate(onError: errors.add)
        ..beginOpen(decoderStartupWindow: mpvDecoderStartupWindow(rtp))
        ..finishOpen()
        ..videoFrame()
        ..playback(playing: false, buffering: true)
        ..log('ffmpeg/video', 'error', packet);
      async.elapse(const Duration(seconds: 2));
      expect(errors.single.code, 'video_decoder_runtime');
      gate.close();
    });
  });

  test('terminal input and decoder failures are still immediate during RTP startup', () {
    fakeAsync((async) {
      final errors = <PlayerException>[];
      final gate = NativeDiagnosticGate(onError: errors.add)
        ..beginOpen(decoderStartupWindow: mpvDecoderStartupWindow(rtp))
        ..finishOpen()
        ..log('vd', 'error', 'unsupported codec');
      expect(errors.single.code, 'video_decoder_init');
      gate
        ..beginOpen(decoderStartupWindow: mpvDecoderStartupWindow(rtp))
        ..finishOpen()
        ..log('stream', 'error', 'Server returned 404 Not Found');
      expect(errors.last.code, 'source_open');
      expect(errors, hasLength(2));
      gate.close();
    });
  });

  test('switching to other protocols clears the RTP startup policy', () {
    for (final address in [
      'https://fixture.invalid/a.m3u8',
      'http://127.0.0.1:49815/a.mp4',
      'rtsp://fixture.invalid/a',
      'udp://127.0.0.1:49817',
      'file:///tmp/a.ts',
    ]) {
      fakeAsync((async) {
        final errors = <PlayerException>[];
        final gate = NativeDiagnosticGate(onError: errors.add)
          ..beginOpen(decoderStartupWindow: mpvDecoderStartupWindow(rtp))
          ..finishOpen()
          ..playback(playing: true, buffering: true)
          ..log('ffmpeg/video', 'error', packet);
        final next = Uri.parse(address);
        expect(mpvDecoderStartupWindow(next), isNull);
        gate
          ..beginOpen(decoderStartupWindow: mpvDecoderStartupWindow(next))
          ..finishOpen()
          ..playback(playing: true, buffering: true)
          ..log('ffmpeg/video', 'error', packet);
        async.elapse(const Duration(seconds: 2));
        expect(errors.single.code, 'video_decoder_runtime');
        gate.close();
      });
    }
  });

  test('a new source drops the previous RTP pending diagnostic', () {
    fakeAsync((async) {
      final errors = <PlayerException>[];
      final gate = NativeDiagnosticGate(onError: errors.add)
        ..beginOpen(decoderStartupWindow: mpvDecoderStartupWindow(rtp))
        ..finishOpen()
        ..playback(playing: true, buffering: true)
        ..log('ffmpeg/video', 'error', packet);
      async.elapse(const Duration(seconds: 2));
      gate
        ..beginOpen()
        ..finishOpen();
      async.elapse(const Duration(seconds: 6));
      expect(errors, isEmpty);
      gate.close();
    });
  });
}
