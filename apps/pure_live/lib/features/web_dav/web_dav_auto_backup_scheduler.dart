import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/web_dav/web_dav_auto_backup.dart';
import 'package:pure_live/features/web_dav/web_dav_config_dialog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Runs [WebDavAutoBackupService] while the app is in use (J04.2, V01.9):
/// once at start, every [checkInterval], after returning to the foreground
/// and after any of its settings change. Background execution is not used.
final class WebDavAutoBackupScheduler {
  /// Creates the scheduler; [toast] is replaceable for tests.
  new(
    this._settings,
    this._service, {
    void Function(String message)? toast,
    this.checkInterval = const Duration(minutes: 15),
    Timer Function(Duration duration, void Function(Timer timer))? timer,
    this.observeLifecycle = true,
  }) : _toast = toast ?? AppNavigator.toast,
       _timerFactory = timer ?? Timer.periodic;

  final SettingsStore _settings;
  final WebDavAutoBackupService _service;
  final void Function(String message) _toast;

  /// How often a check runs while the app is in use.
  final Duration checkInterval;

  final Timer Function(Duration duration, void Function(Timer timer)) _timerFactory;

  /// Whether the scheduler follows the app's foreground state.
  final bool observeLifecycle;

  static const Set<String> _keys = {
    'webdavAutoBackupEnabled',
    'webdavAutoBackupHours',
    'webdavAutoBackupScope',
    'webdavAutoBackupFolder',
    'webdavAutoBackupKeep',
    'webdavAutoBackupIncludeAccounts',
  };

  Timer? _timer;
  StreamSubscription<Setting<Object>>? _changes;
  AppLifecycleListener? _lifecycle;
  Future<void>? _checking;
  bool _started = false;
  bool _paused = false;
  bool _disposed = false;
  bool _failureToastShown = false;

  /// Whether the periodic check is on (tests read it).
  bool get timerActive => _timer?.isActive ?? false;

  /// Starts the check once.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _changes = _settings.changes.listen((setting) {
      if (!_keys.contains(setting.key)) return;
      _syncTimer();
      unawaited(checkNow());
    });
    if (observeLifecycle) {
      _paused = switch (WidgetsBinding.instance.lifecycleState) {
        AppLifecycleState.paused || AppLifecycleState.detached || AppLifecycleState.hidden => true,
        _ => false,
      };
      _lifecycle = AppLifecycleListener(
        onStateChange: (state) {
          if (state == AppLifecycleState.paused ||
              state == AppLifecycleState.detached ||
              state == AppLifecycleState.hidden) {
            pause();
          } else if (state == AppLifecycleState.resumed) {
            resume();
          }
        },
      );
    }
    _syncTimer();
    unawaited(checkNow());
  }

  /// Pauses while the app is in the background.
  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Checks once after the app returns.
  void resume() {
    if (!_started || _disposed || !_paused) return;
    _paused = false;
    _syncTimer();
    unawaited(checkNow());
  }

  /// One check; a second call while one runs returns the same future.
  Future<void> checkNow() {
    if (_disposed || _paused || !_settings.get(Settings.webdavAutoBackupEnabled)) {
      return Future<void>.value();
    }
    if (_checking case final running?) return running;
    late final Future<void> check;
    check = _run().whenComplete(() {
      if (identical(_checking, check)) _checking = null;
    });
    _checking = check;
    return check;
  }

  Future<void> _run() async {
    try {
      final result = await _service.runIfDue();
      if (result.fileName case final name?) {
        _toast(i18n('webdav_auto_backup_success', args: {'name': name}));
      } else if (result.error case final error?) {
        if (!_failureToastShown) {
          _failureToastShown = true;
          _toast(i18n('webdav_auto_backup_failed', args: {'reason': webDavFailureText(error)}));
        }
      }
    } on Object catch (error, stack) {
      log('WebDAV auto backup scheduler failed', name: 'WebDav', error: error, stackTrace: stack);
      if (!_failureToastShown) {
        _failureToastShown = true;
        _toast(i18n('webdav_auto_backup_failed', args: {'reason': webDavFailureText(error)}));
      }
    }
  }

  void _syncTimer() {
    final on = !_disposed && !_paused && _settings.get(Settings.webdavAutoBackupEnabled);
    if (on && _timer == null) {
      _timer = _timerFactory(checkInterval, (_) => unawaited(checkNow()));
    } else if (!on && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  /// Stops the check.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_changes?.cancel());
    _changes = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
