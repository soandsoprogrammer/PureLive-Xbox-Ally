import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/shared/remote/native_remote_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pure_live/app');

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test('text and key commands require a live app-owned native dialog', () async {
    expect(await NativeRemoteInput.insertText(-1, 'no dialog'), isFalse);
    expect(await NativeRemoteInput.command('ok'), isFalse);
    expect(NativeRemoteInput.inputId, isNull);
  });

  test('native input status contains an opaque generation and never the old text', () async {
    final entered = Completer<void>();
    final answer = Completer<String?>();
    final commands = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'inputText') {
        entered.complete();
        return await answer.future;
      }
      commands.add(call);
      return true;
    });
    final pending = NativeRemoteInput.prompt({'title': 'Input', 'text': 'private-existing-text'});
    await entered.future;
    final id = NativeRemoteInput.inputId!;
    expect(id, lessThan(0));
    expect(await NativeRemoteInput.insertText(id - 1, 'stale'), isFalse);
    expect(await NativeRemoteInput.insertText(id, 'new text'), isTrue);
    expect(commands.single.method, 'remoteInputText');
    expect(commands.single.arguments, {'id': -id, 'text': 'new text'});
    answer.complete('new text');
    expect(await pending, 'new text');
    expect(NativeRemoteInput.inputId, isNull);
    expect(await NativeRemoteInput.insertText(id, 'late text'), isFalse);
  });
}
