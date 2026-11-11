import 'dart:async';
import 'dart:developer';

import 'package:live_player/live_player.dart';

/// A cosmetic video yields its entire session to foreground playback.
/// Requests coalesce while cleanup runs; old opens and loops never restart it.
final class TvWallpaperPlayback {
  /// Owns sessions from [createSession], reporting replacements to the view.
  new({
    required this.createSession,
    required this.request,
    required this.onSessionChanged,
    this.releaseTimeout = const Duration(seconds: 6),
  });

  /// Creates a fresh session only when the background is allowed to play.
  final PlaybackSession Function() createSession;

  /// The local background's playback request.
  final PlaybackRequest Function() request;

  /// Attaches or removes the view; cleanup does not wait for a first frame.
  final void Function(PlaybackSession?) onSessionChanged;

  /// Upper bound for releasing this optional background's resources.
  final Duration releaseTimeout;

  PlaybackSession? _session;
  StreamSubscription<PlaybackState>? _states;
  PlaybackSession? _looping;
  bool _held = true;
  bool _closed = false;
  bool _disabled = false;
  int _revision = 0;
  Future<void>? _pending;
  Future<void>? _retirement;

  /// The view's current owner; null while held or releasing.
  PlaybackSession? get session => _session;

  /// Applies the latest intent, waiting only for bounded resource retirement.
  Future<void> setHeld({required bool held}) {
    _held = held;
    _revision++;
    return _synchronize();
  }

  /// Detaches immediately and releases once, including an unfinished open.
  Future<void> close() {
    _closed = true;
    _held = true;
    _revision++;
    return _synchronize();
  }

  /// Retires an unmounted view while retaining its actual native ownership.
  /// The layer bounds foreground waits but keeps replacements held until done.
  Future<void> waitForResourceRelease() async {
    await close();
    if (_retirement case final cleanup?) await cleanup;
  }

  Future<void> _synchronize() {
    if (_pending case final pending?) return pending;
    final done = Completer<void>();
    _pending = done.future;
    unawaited(_drain(done));
    return done.future;
  }

  Future<void> _drain(Completer<void> done) async {
    try {
      var applied = -1;
      while (applied != _revision) {
        applied = _revision;
        await _reconcile();
      }
    } on Object {
      _disabled = true;
      log('Wallpaper playback unavailable', name: 'TvWallpaper');
    } finally {
      _pending = null;
      done.complete();
    }
  }

  Future<void> _reconcile() async {
    if (_held || _closed || _disabled) {
      final previous = _session;
      if (previous == null) return;
      _session = null;
      _looping = null;
      _states?.cancel().ignore();
      _states = null;
      _notify(null);
      // Detaching fences callbacks; native release must not wait for listeners.
      final retirement = previous.waitForResourceRelease();
      _retirement = retirement;
      try {
        await retirement.timeout(releaseTimeout);
        if (identical(_retirement, retirement)) _retirement = null;
      } on Object {
        // Do not create more native players if cleanup cannot prove retirement.
        _disabled = true;
        log('Wallpaper resource retirement unavailable', name: 'TvWallpaper');
      }
      return;
    }
    if (_session != null) return;
    final current = createSession();
    _session = current;
    _states = current.states.listen((state) {
      if (state.status == PlaybackStatus.completed && _owns(current) && !identical(_looping, current)) {
        unawaited(_loop(current));
      }
    });
    _notify(current);
    unawaited(_open(current));
  }

  void _notify(PlaybackSession? value) {
    try {
      onSessionChanged(value);
    } on Object {
      log('Wallpaper view update unavailable', name: 'TvWallpaper');
    }
  }

  bool _owns(PlaybackSession value) => !_closed && !_held && !_disabled && identical(_session, value);

  Future<void> _open(PlaybackSession current) async {
    if (!_owns(current)) return;
    try {
      await current.open(request());
    } on Object {
      if (_owns(current)) log('Wallpaper media unavailable', name: 'TvWallpaper');
    }
  }

  Future<void> _loop(PlaybackSession current) async {
    _looping = current;
    try {
      await current.seek(Duration.zero);
      if (_owns(current)) await current.resume();
    } on Object {
      if (_owns(current)) log('Wallpaper loop unavailable', name: 'TvWallpaper');
    } finally {
      if (identical(_looping, current)) _looping = null;
    }
  }
}
