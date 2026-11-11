import 'dart:async';

/// One bounded native-state snapshot for a stalled buffering episode. Only
/// fixed boolean/numeric properties are read: no source, header or native log.
final class NativeBufferingProbe {
  /// Creates a probe independent of build mode and playback recovery policy.
  new({required this.read, required this.report});

  /// Reads one native property, without changing the player.
  final Future<String> Function(String property) read;

  /// Receives a line containing only the fixed keys and sanitized values.
  final void Function(String line) report;

  /// Non-identifying native state useful before a buffering watchdog fires.
  static const properties = [
    'core-idle',
    'idle-active',
    'paused-for-cache',
    'pause',
    'eof-reached',
    'time-pos',
    'demuxer-cache-duration',
    'video-params/w',
    'video-params/h',
    'audio-params/samplerate',
    'audio-params/channel-count',
    'decoder-frame-drop-count',
    'track-list/count',
    'vo',
    'vid',
    'aid',
  ];

  Timer? _timer;
  int _generation = 0;
  bool _buffering = false;
  bool _reported = false;
  bool _closed = false;

  /// Keeps the first deadline even if the engine repeats its buffering flag.
  void update({required bool buffering}) {
    if (_closed) return;
    if (!buffering) {
      reset();
      return;
    }
    _buffering = true;
    if (_timer != null || _reported) return;
    final generation = _generation;
    _timer = Timer(const Duration(seconds: 3), () async {
      _timer = null;
      _reported = true;
      final values = await Future.wait(properties.map(_value));
      if (!_closed && _buffering && generation == _generation) {
        report(
          'mpv-buffering ${[for (var i = 0; i < properties.length; i++) '${properties[i]}=${values[i]}'].join(' ')}',
        );
      }
    });
  }

  Future<String> _value(String property) async {
    try {
      final value = (await read(property).timeout(const Duration(seconds: 1))).trim();
      if (value.isEmpty) return '?/unavailable';
      if (value == 'yes' || value == 'no') return value;
      if ((property == 'vid' || property == 'aid') && value == 'auto') return value;
      if (property == 'vo' && const {'null', 'gpu', 'gpu-next', 'libmpv', 'mediacodec_embed'}.contains(value)) {
        return value;
      }
      if (value.length > 32) return '?/invalid';
      final number = double.tryParse(value);
      return number != null && number.isFinite && number.abs() < 1e12 ? number.toString() : '?/invalid';
    } on TimeoutException {
      return '?/timeout';
    } on Object {
      return '?/error';
    }
  }

  /// Invalidates even an in-flight snapshot before a stop or another source.
  void reset() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _buffering = false;
    _reported = false;
  }

  /// Stops sampling permanently.
  void close() {
    reset();
    _closed = true;
  }
}
