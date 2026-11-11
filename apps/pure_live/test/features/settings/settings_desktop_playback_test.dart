import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';

import 'settings_harness.dart';

void main() {
  testWidgets('desktop minimize pause is visible, defaults off, and saves its own key', (tester) async {
    final h = await pumpSettings(tester, arguments: 'video', height: 2400);
    expect(h.settings.get(Settings.desktopPauseWhenMinimized), isFalse);
    final row = settingsRow('desktop_pause_when_minimized');
    await tapSettings(tester, row);
    expect(h.settings.get(Settings.desktopPauseWhenMinimized), isTrue);
    expect(h.settings.get(Settings.enableBackgroundPlay), isFalse);
    await tapSettings(tester, row);
    expect(h.settings.get(Settings.desktopPauseWhenMinimized), isFalse);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}));

  testWidgets('phone background playback remains separate and has no desktop minimize row', (tester) async {
    await pumpSettings(tester, arguments: 'video', height: 2400);
    expect(settingsRow('desktop_pause_when_minimized'), findsNothing);
    expect(settingsRow('background_play'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
}
