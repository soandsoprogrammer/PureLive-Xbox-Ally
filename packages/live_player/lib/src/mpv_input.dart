/// Opens MPEG-TS over RTP with the demuxer present in every bundled kernel.
///
/// Android's FFmpeg has no RTP/SDP demuxer. Keep the ordinary RTP protocol
/// input and select MPEG-TS explicitly rather than probing packet headers.
/// Clear the per-player override before other sources reuse the engine.
Future<void> openMpvMediaInput(
  Uri source, {
  required Future<void> Function(String name, String value) configure,
  required Future<void> Function(String input) open,
}) async {
  await configure('demuxer-lavf-format', source.isScheme('rtp') ? 'mpegts' : '');
  await open(source.toString());
}

/// RTP may join before the next decodable video frame. Allow a bounded
/// initial wait for recoverable decoder logs; other inputs keep the normal
/// diagnostic window. This does not delay terminal or later runtime faults.
Duration? mpvDecoderStartupWindow(Uri source) => source.isScheme('rtp') ? const Duration(seconds: 5) : null;
