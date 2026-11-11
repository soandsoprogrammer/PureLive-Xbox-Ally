import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while any video view asks (F.1a). One count for the
/// app, as media_kit's own keep-on counted: a view that lets go never turns
/// the screen off under another one that still plays.
abstract final class ScreenWake {
  static int _holders = 0;
  static int _generation = 0;
  static bool _observing = false;
  static bool _queued = false;
  static bool _syncing = false;
  static Timer? _refresh;
  static final _lifecycle = _ScreenWakeLifecycle();

  /// Turns keep-screen-on on or off (wakelock_plus); tests replace it.
  static Future<void> Function({required bool enabled}) apply = _plugin;

  static Future<void> _plugin({required bool enabled}) async {
    await WakelockPlus.toggle(enable: enabled);
    if (enabled && !await WakelockPlus.enabled) {
      // A stale iOS idle-timer lock can suppress another enable. Clear
      // that stale request before restoring the lock the views still own.
      await WakelockPlus.disable();
      await WakelockPlus.enable();
    }
  }

  /// Whether the screen is kept on now.
  static bool get held => _holders > 0;

  /// One more view wants the screen on.
  static void hold() {
    if (_holders++ != 0) return;
    WidgetsBinding.instance.addObserver(_lifecycle);
    _observing = true;
    // The OS can release a screen lock without changing playback state.
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_visible) _sync();
    });
    _sync();
  }

  /// A view no longer wants it.
  static void release() {
    if (_holders == 0) return;
    if (--_holders != 0) return;
    _refresh?.cancel();
    _refresh = null;
    WidgetsBinding.instance.removeObserver(_lifecycle);
    _observing = false;
    _sync();
  }

  static bool get _visible => switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached => false,
    _ => true,
  };

  static void _sync() {
    _queued = true;
    if (_syncing) return;
    _syncing = true;
    unawaited(_flush(_generation));
  }

  static Future<void> _flush(int generation) async {
    // Serialize native writes, and read the latest demand only when a
    // write begins. A slow enable must finish before the final disable.
    while (_queued && generation == _generation) {
      _queued = false;
      try {
        await apply(enabled: held && _visible);
      } on Object {
        developer.log('Screen keep-on request failed', name: 'screen_wake');
        // A visible holder retries at the next refresh or resume.
      }
    }
    if (generation == _generation) _syncing = false;
  }

  /// Forgets every holder (tests).
  @visibleForTesting
  static void reset() {
    _generation++;
    _refresh?.cancel();
    _refresh = null;
    if (_observing) WidgetsBinding.instance.removeObserver(_lifecycle);
    _observing = false;
    _queued = false;
    _syncing = false;
    _holders = 0;
    apply = _plugin;
  }
}

final class _ScreenWakeLifecycle with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => ScreenWake._sync();
}
