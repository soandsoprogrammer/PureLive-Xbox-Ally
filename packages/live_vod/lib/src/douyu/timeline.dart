import 'dart:async';

import 'package:live_net/live_net.dart';
import 'package:live_vod/src/douyu/models.dart';
import 'package:live_vod/src/models.dart';

/// Loads one position-based comment page at a time, ahead of playback. Seeks
/// fence stale responses; memory is bounded independently of video length.
final class DouyuVodTimeline {
  /// [fetch] uses the selected video's id; [clear] removes old flying comments.
  new({required this.fetch, required this.emit, required this.clear});

  /// Fetches one server page.
  final Future<DouyuVodDanmakuChunk> Function(Duration start, CancelToken cancel) fetch;

  /// Delivers comments when the playback clock crosses their timestamp.
  final void Function(VodDanmaku message) emit;

  /// Removes comments after a seek or video change.
  final void Function() clear;

  final List<VodDanmaku> _pending = [];
  CancelToken? _cancel;
  Duration? _next = Duration.zero;
  Duration _position = Duration.zero;
  Duration? _last;
  Duration? _retryAfter;
  bool _loading = false;
  bool _disposed = false;
  bool _running = false;
  int _generation = 0;

  /// Explicit seeking clears the old frame immediately, including paused seeks.
  void seek(Duration position) {
    if (_disposed) return;
    _generation++;
    _cancel?.cancel();
    _loading = false;
    _pending.clear();
    _position = position;
    _last = position;
    _next = position;
    _retryAfter = null;
    clear();
    _prefetch();
  }

  /// Advances from the engine's clock. Pause/buffering never emits comments.
  void update(Duration position, {required bool playing}) {
    if (_disposed) return;
    final previous = _last;
    _running = playing;
    _position = position;
    if (previous != null && (position < previous || position - previous > const Duration(seconds: 3))) {
      seek(position);
    } else {
      _last = position;
      if (playing) _deliver();
    }
    _prefetch();
  }

  void _deliver() {
    var count = 0;
    while (_pending.isNotEmpty && _pending.first.progress <= _position) {
      final message = _pending.removeAt(0);
      // A slow response must not flood the current frame with old comments.
      if (_position - message.progress <= const Duration(seconds: 2) && count++ < 40) emit(message);
    }
  }

  void _prefetch() {
    final cursor = _next;
    if (_disposed ||
        _loading ||
        cursor == null ||
        _pending.length >= 1500 ||
        cursor > _position + const Duration(seconds: 20) ||
        (_retryAfter != null && _position < _retryAfter!)) {
      return;
    }
    final generation = _generation;
    final cancel = _cancel = CancelToken();
    _loading = true;
    unawaited(() async {
      var success = false;
      try {
        final chunk = await fetch(cursor, cancel);
        if (_disposed || generation != _generation) return;
        _next = chunk.blocked ? null : chunk.next;
        final seen = <String>{for (final item in _pending) '${item.progress.inMilliseconds}:${item.id}:${item.text}'};
        for (final item in chunk.messages) {
          if (item.progress < _position - const Duration(seconds: 2)) continue;
          if (seen.add('${item.progress.inMilliseconds}:${item.id}:${item.text}')) _pending.add(item);
          if (_pending.length >= 2000) break;
        }
        _pending.sort((a, b) => a.progress.compareTo(b.progress));
        if (_running) _deliver();
        success = true;
      } on Object {
        if (!_disposed && generation == _generation) _retryAfter = _position + const Duration(seconds: 10);
      } finally {
        if (!_disposed && generation == _generation) {
          _loading = false;
          if (success) _prefetch();
        }
      }
    }());
  }

  /// Releases pending network work. Late completions cannot emit.
  void dispose() {
    _disposed = true;
    _generation++;
    _cancel?.cancel();
    _pending.clear();
  }
}
