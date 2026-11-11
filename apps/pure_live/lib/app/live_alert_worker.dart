import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/platforms.dart';
import 'package:pure_live/features/favorite/follow_refresher.dart';
import 'package:pure_live/features/favorite/live_alert_watch.dart';
import 'package:pure_live/platform/live_alert_channel.dart';
import 'package:pure_live/platform/secret_cipher.dart';

// The background check of "开播提醒" (O01.2, in
// docs/O-Android系统集成/O01-通知和前台服务): `LiveAlertWorker.kt` starts this on an engine of its own
// when WorkManager runs it, and ends the engine on `done` (or after its
// time limit).

/// The worker's entry: one [runLiveAlertCheck] over the platforms without
/// cookies or proxy (a store in memory), then `done` with the number of
/// notifications posted.
@pragma('vm:entry-point')
Future<void> liveAlertWorkerMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const worker = MethodChannel('pure_live/live_alert_worker');
  var posted = 0;
  LiveStore? store;
  try {
    store = await LiveStore.memory(cipher: NativeChannelCipher());
    final proxy = SettingsProxyPolicy(store.settings);
    final http = IoLiveHttp(proxy: proxy);
    final sites = buildSiteRegistry(
      PlatformDeps(http: http, proxy: proxy, cookies: StoreCookieVault(store.secrets), store: store),
    );
    const alerts = LiveAlertChannel();
    final started = await runLiveAlertCheck(
      file: liveAlertWatchFile(),
      refresher: FollowRefresher(sites: sites),
      post: (room, watch) =>
          alerts.postArguments(liveAlertArgumentsOf(room, content: watch.contentOf(room), texts: watch.texts)),
    );
    posted = started.length;
  } on Object catch (error, stack) {
    log('Live alert check failed', name: 'LiveAlerts', error: error, stackTrace: stack);
  } finally {
    await store?.close();
    try {
      await worker.invokeMethod<void>('done', posted);
    } on Object {
      // The engine is going anyway.
    }
  }
}
