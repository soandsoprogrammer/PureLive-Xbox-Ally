import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/i18n/i18n.dart';

/// One row of the playback information panel.
final class PlaybackInfoRow {
  /// Creates a row.
  const new({required this.id, required this.label, required this.value, this.multiline = false});

  /// Stable key part (`playback-info-<id>`).
  final String id;

  /// The name on the left.
  final String label;

  /// The value on the right; “—” when unknown.
  final String value;

  /// Whether the value may wrap to two lines (the encoder and the host).
  final bool multiline;
}

/// What the playback information panel shows: the nine rows, the player
/// versions under them, and the full codec descriptions kept for copying.
final class PlaybackInfo {
  /// Creates the snapshot.
  const new({required this.rows, this.playerCore, this.videoCodec, this.audioCodec});

  /// The nine rows, in display order.
  final List<PlaybackInfoRow> rows;

  /// `mpv … · FFmpeg …`; null when neither is known.
  final String? playerCore;

  /// `video-codec`, for the copied text.
  final String? videoCodec;

  /// `audio-codec`, for the copied text.
  final String? audioCodec;

  /// The text the panel's copy action puts on the clipboard. It contains
  /// only these rows, the versions and the codec descriptions: no stream
  /// address, query, Cookie or request header.
  String get copyText => [
    for (final row in rows) '${row.label}: ${row.value}',
    if (playerCore != null) '${i18n('player_kernel')}: $playerCore',
    if (videoCodec != null) '${i18n('playback_info_video_codec_detail')}: $videoCodec',
    if (audioCodec != null) '${i18n('playback_info_audio_codec_detail')}: $audioCodec',
  ].join('\n');
}

/// Builds the panel's rows from the session's [state] and one [stats]
/// snapshot. [downloadBytesPerSecond] stands in for the snapshot's own value
/// (the panel shows a short average); when null the snapshot's value is used.
PlaybackInfo playbackInfoOf({
  required PlaybackState state,
  required PlaybackStats? stats,
  double? downloadBytesPerSecond,
}) {
  final download = downloadBytesPerSecond ?? stats?.downloadBytesPerSecond;
  return PlaybackInfo(
    rows: [
      PlaybackInfoRow(
        id: 'resolution',
        label: i18n('playback_info_resolution'),
        value: formatPlaybackSize(stats?.width, stats?.height),
      ),
      PlaybackInfoRow(
        id: 'frame-rate',
        label: i18n('playback_info_frame_rate'),
        value: formatPlaybackFps(state.frameRate),
      ),
      PlaybackInfoRow(id: 'codec', label: i18n('playback_info_codec'), value: formatPlaybackCodec(stats?.videoFormat)),
      PlaybackInfoRow(
        id: 'encoder',
        label: i18n('playback_info_encoder'),
        value: formatPlaybackEncoder(stats?.encoder),
        multiline: true,
      ),
      PlaybackInfoRow(
        id: 'audio',
        label: i18n('playback_info_audio'),
        value: formatPlaybackAudio(stats),
        multiline: true,
      ),
      PlaybackInfoRow(
        id: 'frames',
        label: i18n('playback_info_frames'),
        value: formatPlaybackFrames(stats?.droppedFrames, stats?.decodedFrames),
      ),
      PlaybackInfoRow(
        id: 'buffer',
        label: i18n('playback_info_buffer'),
        value: formatPlaybackBuffer(stats?.bufferSeconds),
      ),
      PlaybackInfoRow(id: 'download', label: i18n('playback_info_download'), value: formatPlaybackDownload(download)),
      PlaybackInfoRow(
        id: 'host',
        label: i18n('playback_info_host'),
        value: formatPlaybackHost(state.line),
        multiline: true,
      ),
    ],
    playerCore: formatPlaybackPlayerCore(stats),
    videoCodec: _text(stats?.videoCodec),
    audioCodec: _text(stats?.audioCodec),
  );
}

/// `2560 × 1440`; “—” unless both sizes are positive.
String formatPlaybackSize(int? width, int? height) =>
    width == null || height == null || width <= 0 || height <= 0 ? '—' : '$width × $height';

/// `60.0 fps`; “—” when unknown.
String formatPlaybackFps(double? fps) =>
    fps == null || !fps.isFinite || fps <= 0 ? '—' : '${fps.toStringAsFixed(1)} fps';

/// The short display name of a `video-format` value.
String formatPlaybackCodec(String? format) {
  final codec = format?.trim().toLowerCase() ?? '';
  return switch (codec) {
    '' => '—',
    'h264' || 'avc' => 'H.264',
    'hevc' || 'h265' => 'H.265',
    'av1' => 'AV1',
    'vp9' => 'VP9',
    'vp8' => 'VP8',
    _ => codec.toUpperCase(),
  };
}

/// The encoder the streamer wrote into the stream's metadata; “—” when the
/// stream carries none.
String formatPlaybackEncoder(String? encoder) => _text(encoder) ?? '—';

/// `48 kHz · 立体声 · 160 kbps`; the parts that are known, or “—”.
String formatPlaybackAudio(PlaybackStats? stats) {
  final parts = [
    if (stats?.sampleRate case final rate? when rate > 0) formatPlaybackSampleRate(rate),
    if (stats?.channels case final channels? when channels > 0) formatPlaybackChannels(channels),
    if (stats?.audioBitrate case final bitrate? when bitrate > 0) formatPlaybackAudioBitrate(bitrate),
  ];
  return parts.isEmpty ? '—' : parts.join(' · ');
}

/// `48 kHz`; values below 1000 stay in Hz.
String formatPlaybackSampleRate(int hz) {
  if (hz < 1000) return '$hz Hz';
  final khz = hz / 1000;
  return '${khz.toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz';
}

/// 1 is mono, 2 stereo, more a channel count.
String formatPlaybackChannels(int channels) => switch (channels) {
  1 => i18n('playback_info_mono'),
  2 => i18n('playback_info_stereo'),
  _ => i18n('playback_info_channels', args: {'count': '$channels'}),
};

/// `160 kbps`; values below 1000 stay in bps.
String formatPlaybackAudioBitrate(int bitsPerSecond) {
  if (bitsPerSecond < 1000) return '$bitsPerSecond bps';
  return '${(bitsPerSecond / 1000).round()} kbps';
}

/// `2 / 503`; either side is “—” when unknown.
String formatPlaybackFrames(int? dropped, int? decoded) =>
    dropped == null && decoded == null ? '—' : '${dropped ?? '—'} / ${decoded ?? '—'}';

/// `6.40 s`; “—” when unknown.
String formatPlaybackBuffer(double? seconds) =>
    seconds == null || !seconds.isFinite || seconds < 0 ? '—' : '${seconds.toStringAsFixed(2)} s';

/// `3.0 Mbps` from bytes a second; “—” when unknown or zero.
String formatPlaybackDownload(double? bytesPerSecond) {
  if (bytesPerSecond == null || !bytesPerSecond.isFinite || bytesPerSecond <= 0) return '—';
  final bits = bytesPerSecond * 8;
  if (bits >= 1000000) return '${(bits / 1000000).toStringAsFixed(1)} Mbps';
  if (bits >= 1000) return '${(bits / 1000).toStringAsFixed(0)} kbps';
  return '${bits.toStringAsFixed(0)} bps';
}

/// The stream's host; “本机中继” for a loopback relay and “—” when unknown.
String formatPlaybackHost(LivePlayLine? line) {
  final url = line?.url.trim() ?? '';
  if (url.isEmpty) return '—';
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '';
  if (host.isEmpty) return '—';
  const local = {'localhost', '127.0.0.1', '::1'};
  return local.contains(host.toLowerCase()) ? i18n('playback_info_local_relay') : host;
}

/// `mpv 0.41.0 · FFmpeg 9.0.2`; null when neither version is known.
String? formatPlaybackPlayerCore(PlaybackStats? stats) {
  final mpv = _version(stats?.mpvVersion, 'mpv');
  final ffmpeg = _version(stats?.ffmpegVersion, 'FFmpeg');
  final parts = [mpv, ffmpeg].whereType<String>().toList();
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _version(String? value, String label) {
  final text = _text(value);
  if (text == null) return null;
  return text.toLowerCase().startsWith(label.toLowerCase()) ? text : '$label $text';
}

String? _text(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
