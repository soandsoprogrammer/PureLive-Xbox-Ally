import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';

/// Exits through the desktop save/recording cleanup path, including tray mode.
class WindowsUninstallHandler {
  /// The native helper has already checked the installed executable's path.
  new(this.exit);

  /// Saves state and destroys this process's window.
  final Future<void> Function() exit;

  static const _channel = MethodChannel('pure_live/window_startup');
  Future<void>? _exiting;

  /// Attaches after desktop initialization, so early native requests can wait.
  Future<void> connect() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'shutdownForUninstall') throw MissingPluginException();
      // The helper waits for process exit. Reply before destroying its engine.
      unawaited(
        _exiting ??= Future<void>.sync(exit).catchError((Object error, StackTrace stack) {
          log('Uninstall shutdown failed', name: 'Desktop', error: error, stackTrace: stack);
        }),
      );
    });
    await _channel.invokeMethod<void>('uninstallReady');
  }

  /// Removes the process-local listener.
  void dispose() => _channel.setMethodCallHandler(null);
}
