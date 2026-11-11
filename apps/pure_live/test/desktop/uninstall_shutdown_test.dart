import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/app/desktop/uninstall_shutdown.dart';

void main() {
  testWidgets('issue136 uninstall acknowledges before cleanup completes and starts cleanup only once', (tester) async {
    const channel = MethodChannel('pure_live/window_startup');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async => calls.add(call.method));
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final stopped = Completer<void>();
    var exits = 0;
    final handler = WindowsUninstallHandler(() {
      exits++;
      return stopped.future;
    });
    addTearDown(handler.dispose);
    await handler.connect();
    expect(calls, ['uninstallReady']);
    Future<void> request() async {
      final reply = Completer<void>();
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('shutdownForUninstall')),
        (_) => reply.complete(),
      );
      await reply.future;
    }

    await request();
    expect(stopped.isCompleted, isFalse);
    expect(exits, 1);
    await request();
    expect(exits, 1, reason: 'repeated native messages cannot dispose recordings twice');
    stopped.complete();
    await tester.pump();
    await request();
    expect(exits, 1);
  });
}
