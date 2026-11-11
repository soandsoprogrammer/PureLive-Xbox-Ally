import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/src/mpv_input.dart';

void main() {
  for (final address in [
    'rtp://239.255.54.15:49816',
    'rtp://127.0.0.1:49817',
    'rtp://239.255.54.15:49816?localaddr=127.0.0.1&buffer_size=8388608',
    'rtp://[ff15::5415]:49816?source=fixture%20only',
  ]) {
    test('MPEG-TS over RTP retains its protocol, endpoint and options: $address', () async {
      final events = <String>[];
      await openMpvMediaInput(
        Uri.parse(address),
        configure: (key, value) async {
          events.add('$key=$value');
        },
        open: (input) async {
          events.add(input);
        },
      );
      expect(events, ['demuxer-lavf-format=mpegts', address]);
    });
  }

  for (final address in [
    'https://fixture.invalid/live.m3u8?source=fixture%20only',
    'http://127.0.0.1:49815/fixture.mp4',
    'rtsp://fixture.invalid:8554/live',
    'udp://239.255.54.15:49816',
    'file:///tmp/purelive-fixture.ts',
    'data:application/octet-stream;base64,AA==',
  ]) {
    test('a reused engine clears the RTP container override before $address', () async {
      var format = '';
      final opened = <String>[];
      Future<void> configure(String key, String value) async {
        format = value;
      }

      await openMpvMediaInput(
        Uri.parse('rtp://127.0.0.1:49817'),
        configure: configure,
        open: (input) async {
          expect(format, 'mpegts');
          opened.add(input);
        },
      );
      await openMpvMediaInput(
        Uri.parse(address),
        configure: configure,
        open: (input) async {
          expect(format, isEmpty);
          opened.add(input);
        },
      );
      expect(opened.last, address);
    });
  }

  test('configuration completes before the media opens', () async {
    final configured = Completer<void>();
    var opened = false;
    final result = openMpvMediaInput(
      Uri.parse('rtp://127.0.0.1:49817'),
      configure: (_, _) => configured.future,
      open: (_) async {
        opened = true;
      },
    );
    expect(opened, isFalse);
    configured.complete();
    await result;
    expect(opened, isTrue);
  });

  test('a failed container configuration prevents opening the source', () async {
    var opened = false;
    await expectLater(
      openMpvMediaInput(
        Uri.parse('rtp://127.0.0.1:49817'),
        configure: (_, _) async {
          throw StateError('fixture configuration failed');
        },
        open: (_) async {
          opened = true;
        },
      ),
      throwsStateError,
    );
    expect(opened, isFalse);
  });
}
