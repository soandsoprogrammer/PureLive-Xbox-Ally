import 'dart:async';

import 'package:clock/clock.dart';
import 'package:live_media/live_media.dart';

/// Turns mpv's error-level log lines into confirmed source failures (the
/// diagnostic half of 3.x's `MediaKitAdapter`).
///
/// mpv reports recoverable packet and hardware-decoder trouble on the same
/// stream as fatal failures. So:
/// - only lines from the prefixes 3.x acted on count (`ffmpeg` only for
///   `tcp:` lines);
/// - [NativeDiagnostic.immediatelyTerminal] failures are reported at once;
/// - other failures wait [window]: progress of the same decoder (a frame, or
///   playing without buffering) cancels them;
/// - a line logged while a source opens is held until the open finishes and
///   dropped when the decoder it names already produced output; a decoder's
///   line waits further, until the new source is under way (G02.4: the old
///   source's half-read packets, logged while a recovery reopened, were
///   taken for the new source's and a slow open recovered again);
/// - notices that are not failures are ignored ([isActionable]);
/// - the same text is reported once per source within two seconds.
final class NativeDiagnosticGate {
  /// Creates a gate that reports to [onError].
  new({required this.onError, this.window = const Duration(milliseconds: 1200)});

  /// Receives confirmed failures.
  final void Function(PlayerException error) onError;

  /// How long a recoverable diagnostic waits for progress.
  final Duration window;

  static const _prefixes = {'file', 'vd', 'ad', 'ffmpeg/video', 'ffmpeg/audio', 'cplayer', 'stream'};

  Duration? _decoderStartupWindow;
  bool _opening = false;
  bool _closed = false;
  bool _videoReady = false;
  bool _audioReady = false;
  bool _playing = false;
  bool _buffering = false;
  int _progress = 0;
  ({String text, String? prefix})? _held;

  /// A decoder's line held from the open, waiting for the source to get
  /// under way.
  ({String text, String? prefix})? _deferred;
  Timer? _timer;
  PlayerException? _pending;
  NativeDiagnosticComponent _pendingComponent = NativeDiagnosticComponent.either;
  int _pendingProgress = 0;
  String? _lastText;
  DateTime? _lastAt;

  /// Lines logged as errors that are not failures (G02.4).
  ///
  /// FFmpeg's MediaCodec decoder logs "Both surface and native_window are
  /// NULL" whenever it is opened without a surface, which is how
  /// `mediacodec-copy` (Android's hardware decoding here) always opens it;
  /// it starts and decodes right after. Taken for a decoder failure, it
  /// restarted streams that were playing (a Bilibili room rebuffering a
  /// moment after its first frame, 2026-10-20).
  static const _notices = ['both surface and native_window are null'];

  /// Whether mpv's [prefix] and [text] are worth classifying (3.x's
  /// `_isActionableNativeLog`).
  static bool isActionable(String prefix, String text) {
    final normalized = prefix.trim().toLowerCase();
    final line = text.trimLeft().toLowerCase();
    if (_notices.any(line.contains)) return false;
    if (normalized == 'ffmpeg') return line.startsWith('tcp:');
    return _prefixes.contains(normalized);
  }

  /// A new source starts opening; everything of the previous one is dropped.
  /// [decoderStartupWindow] optionally gives a packet-joined source longer
  /// to produce its first output. Terminal errors and subsequent decoder
  /// failures retain their existing handling.
  void beginOpen({Duration? decoderStartupWindow}) {
    _decoderStartupWindow = decoderStartupWindow;
    _cancelPending();
    _opening = true;
    _videoReady = false;
    _audioReady = false;
    _playing = false;
    _buffering = true;
    _progress = 0;
    _held = null;
    _deferred = null;
    _lastText = null;
    _lastAt = null;
  }

  /// The open finished; a held line is processed now unless its decoder
  /// already produced output.
  void finishOpen() {
    _opening = false;
    final held = _held;
    _held = null;
    if (held == null) return;
    final component = _componentOf(held.prefix);
    if (_ready(component)) return;
    // Nothing of the new source decoded yet: a decoder's line cannot be
    // about it. It counts once the source is under way.
    if (component != NativeDiagnosticComponent.either && !_underWay) {
      _deferred = held;
      return;
    }
    _process(held.text, held.prefix);
  }

  bool get _underWay => _playing || _videoReady || _audioReady;

  /// The source got under way: a deferred decoder line counts from now,
  /// unless its decoder already produced output.
  void _start() {
    final deferred = _deferred;
    if (deferred == null) return;
    _deferred = null;
    if (!_ready(_componentOf(deferred.prefix))) _process(deferred.text, deferred.prefix);
  }

  /// One mpv log line.
  void log(String prefix, String level, String text) {
    if (_closed || level != 'error' || !isActionable(prefix, text)) return;
    if (_opening) {
      _held = (text: text, prefix: prefix);
      return;
    }
    _process(text, prefix);
  }

  /// A decoded video frame (or video parameters).
  void videoFrame() {
    _videoReady = true;
    _progress++;
    _cancelRecovered(NativeDiagnosticComponent.video);
    _start();
  }

  /// Decoded audio (audio parameters).
  void audioFrame() {
    _audioReady = true;
    _progress++;
    _cancelRecovered(NativeDiagnosticComponent.audio);
    _start();
  }

  /// mpv's playing and buffering flags; playing without buffering is
  /// progress of whatever is shown.
  void playback({required bool playing, required bool buffering, bool audioOnly = false}) {
    _playing = playing;
    _buffering = buffering;
    if (playing && !buffering) {
      _progress++;
      _cancelRecovered(audioOnly ? NativeDiagnosticComponent.audio : NativeDiagnosticComponent.video);
    }
    if (playing) _start();
  }

  /// Stops reporting.
  void close() {
    _closed = true;
    _deferred = null;
    _cancelPending();
  }

  void _process(String text, String? prefix) {
    final classification = NativeDiagnostic.classify(text, nativePrefix: prefix);
    final error = PlayerException(message: text, type: classification.type, code: classification.code);
    if (classification.immediatelyTerminal) {
      _report(error);
      return;
    }
    if (_timer != null) return;
    _pending = error;
    _pendingComponent = classification.component;
    _pendingProgress = _progress;
    final startup = _decoderStartupWindow;
    final delay =
        startup != null &&
            startup > window &&
            classification.component != NativeDiagnosticComponent.either &&
            !_ready(classification.component)
        ? startup
        : window;
    _timer = Timer(delay, () {
      _timer = null;
      final pending = _pending;
      _pending = null;
      if (pending == null || _closed) return;
      final recovered = _progress > _pendingProgress && _playing && (_ready(_pendingComponent) || !_buffering);
      if (recovered || (_playing && !_buffering)) return;
      _report(pending);
    });
  }

  void _report(PlayerException error) {
    if (_closed) return;
    final now = clock.now();
    final last = _lastAt;
    if (_lastText == error.message && last != null && now.difference(last) < const Duration(seconds: 2)) return;
    _lastText = error.message;
    _lastAt = now;
    onError(error);
  }

  bool _ready(NativeDiagnosticComponent component) => switch (component) {
    NativeDiagnosticComponent.video => _videoReady,
    NativeDiagnosticComponent.audio => _audioReady,
    NativeDiagnosticComponent.either => _videoReady || _audioReady,
  };

  static NativeDiagnosticComponent _componentOf(String? prefix) => switch (prefix?.trim().toLowerCase()) {
    'ad' || 'ffmpeg/audio' => NativeDiagnosticComponent.audio,
    'vd' || 'ffmpeg/video' => NativeDiagnosticComponent.video,
    _ => NativeDiagnosticComponent.either,
  };

  void _cancelRecovered(NativeDiagnosticComponent progressed) {
    if (_timer == null) return;
    if (_pendingComponent != NativeDiagnosticComponent.either && _pendingComponent != progressed) return;
    _cancelPending();
  }

  void _cancelPending() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _pendingComponent = NativeDiagnosticComponent.either;
  }
}
