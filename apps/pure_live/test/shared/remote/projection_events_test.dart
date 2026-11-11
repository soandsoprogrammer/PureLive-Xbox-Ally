import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android projection-stop events retain track identity and exclude unrelated native events', () async {
    const name = 'FlutterWebRTC.Event';
    const codec = StandardMethodCodec();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final listening = Completer<void>();
    messenger.setMockMethodCallHandler(const MethodChannel(name), (call) async {
      if (call.method == 'listen' && !listening.isCompleted) listening.complete();
      return null;
    });
    final received = <String>[];
    final completed = Completer<void>();
    final subscription = ScreenCaptureEvents.stopped.listen((track) {
      received.add(track);
      if (received.length == 2) completed.complete();
    });
    try {
      await listening.future;
      for (final event in [
        {'event': 'onLogData', 'data': 'unrelated'},
        {'event': 'onScreenCaptureStopped', 'trackId': 12},
        {'event': 'onScreenCaptureStopped', 'trackId': 'old-capture'},
        {'event': 'onScreenCaptureStopped', 'trackId': 'current-capture'},
      ]) {
        await messenger.handlePlatformMessage(name, codec.encodeSuccessEnvelope(event), (_) {});
      }
      await completed.future;
      expect(received, ['old-capture', 'current-capture']);
    } finally {
      await subscription.cancel();
      messenger.setMockMethodCallHandler(const MethodChannel(name), null);
    }
  });
}
