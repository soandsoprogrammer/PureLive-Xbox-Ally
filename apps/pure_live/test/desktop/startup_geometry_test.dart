import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/desktop/startup_window.dart';

import '../support.dart';

void main() {
  late LiveStore store;
  setUp(() async => store = await LiveStore.memory(cipher: FakeCipher()));
  tearDown(() => store.close());

  test('fixed 720P ignores a previous maximized 4K window', () async {
    await store.settings.set(Settings.rememberWindowGeometry, false);
    await store.meta.set('window.maximized', '1');
    await rememberNormalWindowSize(store, const Size(3840, 2160));
    expect(await startupWindowGeometry(store, primary: true), (size: const Size(1280, 720), maximized: false));
    expect(store.settings.get(Settings.windowWidth), 1280, reason: 'observations cannot overwrite the fixed preset');
    expect(store.settings.get(Settings.windowHeight), 720);
  });

  test('default memory restores normal size and maximize without changing preset', () async {
    await rememberNormalWindowSize(store, const Size(1600, 900));
    await store.meta.set('window.maximized', '1');
    expect(await startupWindowGeometry(store, primary: true), (size: const Size(1600, 900), maximized: true));
    expect(await startupWindowGeometry(store, primary: false), (size: const Size(1280, 720), maximized: false));
    await store.settings.set(Settings.rememberWindowGeometry, false);
    expect(await startupWindowGeometry(store, primary: true), (size: const Size(1280, 720), maximized: false));
    await store.settings.set(Settings.rememberWindowGeometry, true);
    expect(await startupWindowGeometry(store, primary: true), (size: const Size(1600, 900), maximized: true));
  });

  test('legacy or corrupt remembered dimensions fall back safely to the preset', () async {
    await store.settings.setAll({Settings.windowWidth: 1440.0, Settings.windowHeight: 900.0});
    for (final value in ['', 'NaN,720', 'Infinity,720', '-1,900', '1280,0', '1280', 'a,b']) {
      await store.meta.set(windowNormalSizeKey, value);
      expect((await startupWindowGeometry(store, primary: true)).size, const Size(1440, 900), reason: value);
    }
    await rememberNormalWindowSize(store, const Size(double.nan, 720));
    expect((await startupWindowGeometry(store, primary: true)).size, const Size(1440, 900));
  });
}
