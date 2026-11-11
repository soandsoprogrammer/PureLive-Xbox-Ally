import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';

/// Emits one safe summary per terminal failure, resetting after recovery.
/// Exception messages, arbitrary codes and request data never enter this log.
final class PlaybackFailureDiagnostics {
  /// Creates the failure transition filter.
  new();

  Object? _last;
  bool _failed = false;

  static const _codes = {
    'no_source',
    'source_open_timeout',
    'source_open',
    'live_source_completed',
    'buffering_stall_timeout',
    'unexpected_pause_timeout',
    'video_frame_stall_timeout',
    'playback_stall_timeout',
    'network_lost',
    'lifecycle',
    'transport',
    'source_runtime',
    'native_diagnostic',
    'video_output',
    'audio_video_output',
    'video_video_output',
    'decoder_init',
    'audio_decoder_init',
    'video_decoder_init',
    'decoder_runtime',
    'audio_decoder_runtime',
    'video_decoder_runtime',
  };

  /// A summary when the session enters error, otherwise null.
  String? update(PlaybackState state) {
    if (state.status != PlaybackStatus.error) {
      _failed = false;
      _last = null;
      return null;
    }
    if (_failed && identical(_last, state.error)) return null;
    _failed = true;
    _last = state.error;
    final error = state.error;
    final type = error is PlayerException ? error.type.name : 'unknown';
    final code = error is PlayerException && _codes.contains(error.code) ? error.code : 'unknown';
    final video = state.aspectRatio == null ? 'none' : '${state.videoWidth}x${state.videoHeight}';
    return 'type=$type code=$code decoder=${state.decoder.name} audioOnly=${state.audioOnly} video=$video';
  }
}
