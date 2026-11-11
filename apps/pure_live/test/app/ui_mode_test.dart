import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/app/ui_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pure_live/app');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TvDevice.debugTelevision = null;
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    TvDevice.debugTelevision = null;
    debugDefaultTargetPlatformOverride = null;
  });

  for (final failure in [true, false]) {
    test('issue 131: ${failure ? 'failed' : 'negative'} startup detection recovers and updates auto mode', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        if (calls == 1) {
          if (failure) throw PlatformException(code: 'service_not_ready');
          return false;
        }
        return true;
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(televisionDeviceProvider, (_, _) {});
      addTearDown(subscription.close);
      expect(await TvDevice.detect(), isFalse);
      if (failure) expect(TvDevice.debugTelevision, isNull, reason: 'an exception is not hardware evidence');
      expect(await TvDevice.detect(), isTrue);
      expect(container.read(televisionDeviceProvider), isTrue);
      expect(UiMode.auto.showsTv(television: TvDevice.isTelevision), isTrue);
      expect(
        UiMode.phone.showsTv(television: TvDevice.isTelevision),
        isFalse,
        reason: 'an explicit phone interface still wins',
      );
      expect(await TvDevice.detect(), isTrue);
      expect(calls, 2, reason: 'confirmed TV hardware does not regress on later wakeups');
    });
  }

  test('concurrent TV probes share one native call and retry a null response', () async {
    final answer = Completer<bool?>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return await answer.future;
    });
    final first = TvDevice.detect();
    final second = TvDevice.detect();
    answer.complete(null);
    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(calls, 1);
    expect(TvDevice.debugTelevision, isNull);
    expect(await TvDevice.detect(), isFalse);
    expect(calls, 2);
  });
}
