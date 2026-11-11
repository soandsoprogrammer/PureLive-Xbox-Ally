import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';

import '../support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LiveStore store;
  late DesktopShell shell;
  setUp(() async {
    store = await LiveStore.memory(cipher: FakeCipher());
    shell = DesktopShell.testListener(store);
    DesktopWindow.minimized.value = false;
  });
  tearDown(() async {
    await shell.dispose();
    await store.close();
    DesktopWindow.minimized.value = false;
    DesktopWindow.maximized.value = false;
  });

  test('normal restore clears minimization', () {
    shell.onWindowMinimize();
    expect(DesktopWindow.minimized.value, isTrue);
    shell.onWindowRestore();
    expect(DesktopWindow.minimized.value, isFalse);
  });
  for (final event in ['maximize', 'unmaximize', 'focus']) {
    test('$event after native minimize restores presentation visibility', () {
      shell
        ..onWindowMaximize()
        ..onWindowMinimize();
      expect(DesktopWindow.minimized.value, isTrue);
      switch (event) {
        case 'maximize':
          shell.onWindowMaximize();
        case 'unmaximize':
          shell.onWindowUnmaximize();
        case 'focus':
          shell.onWindowFocus();
      }
      expect(
        DesktopWindow.minimized.value,
        isFalse,
        reason: 'native maximize and focus need not emit a separate restore',
      );
    });
  }
  test('blur alone does not pretend a minimized window has restored', () {
    shell
      ..onWindowMinimize()
      ..onWindowBlur();
    expect(DesktopWindow.minimized.value, isTrue);
  });
}
