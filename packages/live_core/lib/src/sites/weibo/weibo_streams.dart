import 'dart:async';
import 'dart:typed_data';

import 'package:live_core/src/live_area.dart';
import 'package:live_net/live_net.dart';

/// One optional, public Weibo transcoding profile; never a caller-supplied URL.
final class WeiboStreamCandidate {
  /// Creates a candidate derived from the room's public CDN address.
  const new({required this.id, required this.label, required this.sort, required this.url, required this.avcOnly});

  /// Stable selector, independent of the current broadcast URL.
  final String id;

  /// The common quality name translated by the application's platform labels.
  final String label;

  /// Higher values rank higher, like other platform quality lists.
  final int sort;

  /// The exact candidate to probe before offering or playing it.
  final Uri url;

  /// Transcoded AVC profiles must announce AVC, not an unexpected codec.
  final bool avcOnly;

  /// The option with its observed FLV video codec.
  LivePlayQuality quality(String codec) => LivePlayQuality(quality: label, id: id, sort: sort, codec: codec);
}

/// Optional Weibo CDN profiles verified against public live broadcasts.
///
/// The web API exposes only its 720 AVC URL. Probe the source, 1080 AVC and
/// 480 AVC profiles without guessing that every broadcast has every profile.
/// Preserve unknown/signed URL forms unchanged through the legacy fallback.
abstract final class WeiboStreams {
  /// Upper bound for one probe, including headers and the first video tag.
  static const probeTimeout = Duration(seconds: 3);

  /// No probe buffers more than this many bytes of a live response.
  static const int prefixLimit = 64 * 1024;

  static final RegExp _host = RegExp(r'^plwb[0-9]+\.live\.weibo\.com$');
  static final RegExp _path = RegExp(r'^/alicdn/([0-9]{12,24})_wb720avc\.flv$');
  static const List<(String, String, String, int, bool)> _profiles = [
    ('weibo-source', '原画', '', 4000, false),
    ('weibo-1080-avc', '蓝光', '_wb1080avc', 3000, true),
    ('weibo-480-avc', '高清', '_wb480avc', 1000, true),
  ];

  /// Whether an option belongs to this fixed set of profiles.
  static bool knows(String id) => _profiles.any((profile) => profile.$1 == id);

  /// Candidates from the first canonical, unsigned HTTPS FLV address only.
  static List<WeiboStreamCandidate> candidates(Iterable<String> mediaUrls) {
    for (final raw in mediaUrls) {
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.port != 443 ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          !_host.hasMatch(uri.host)) {
        continue;
      }
      final match = _path.firstMatch(uri.path);
      if (match == null) continue;
      return [
        for (final (id, label, suffix, sort, avcOnly) in _profiles)
          WeiboStreamCandidate(
            id: id,
            label: label,
            sort: sort,
            avcOnly: avcOnly,
            url: uri.replace(path: '/alicdn/${match[1]}$suffix.flv'),
          ),
      ];
    }
    return const [];
  }

  /// AVC/HEVC announced by a bounded FLV sequence header, or null if absent.
  /// This checks the transport/container declaration, not full video decoding.
  static String? codecFromFlv(List<int> bytes) {
    if (bytes.length < 13 || bytes[0] != 70 || bytes[1] != 76 || bytes[2] != 86 || bytes[3] != 1) return null;
    final offset = (bytes[5] << 24) | (bytes[6] << 16) | (bytes[7] << 8) | bytes[8];
    if (offset < 9 || offset > prefixLimit - 4) return null;
    var pos = offset + 4;
    while (pos + 11 <= bytes.length) {
      final size = (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
      if (size > prefixLimit || pos + 11 + size > bytes.length) return null;
      final body = pos + 11;
      if ((bytes[pos] & 31) == 9 && size >= 12) {
        final first = bytes[body];
        if ((first & 0x80) == 0 && bytes[body + 1] == 0 && bytes[body + 5] == 1) {
          final codec = switch (first & 15) {
            7 => 'avc',
            12 => 'hevc',
            _ => null,
          };
          if (codec != null) return codec;
        } else if ((first & 0x80) != 0 && (first & 15) == 0 && size >= 28) {
          final fourcc = String.fromCharCodes(bytes.sublist(body + 1, body + 5));
          if (fourcc == 'hvc1' && bytes[body + 5] == 1) return 'hevc';
        }
      }
      pos += 11 + size + 4;
    }
    return null;
  }

  /// Reads only enough of one public candidate to observe its video header.
  /// Cancels its own stream on success, timeout or parent cancellation; never
  /// closes the shared HTTP client. Missing profiles remain optional.
  static Future<String?> probe(LiveHttp http, Uri url, {CancelToken? cancel}) async {
    void checkCancelled() {
      if (cancel?.isCancelled ?? false) throw const TransportFailure('weibo', TransportReason.cancelled);
    }

    checkCancelled();
    final local = CancelToken();
    var finished = false;
    if (cancel != null) {
      unawaited(
        cancel.whenCancelled.then((_) {
          if (!finished) local.cancel();
        }),
      );
    }
    StreamIterator<List<int>>? iterator;
    Future<String?> read() async {
      final response = await http.open(
        LiveRequest(
          site: 'weibo',
          url: url,
          timeout: probeTimeout,
          cancel: local,
          followRedirects: false,
          headers: const {'range': 'bytes=0-65535', 'user-agent': 'Mozilla/5.0'},
        ),
      );
      if (local.isCancelled || !response.isSuccess) {
        await response.discard();
        return null;
      }
      final chunks = StreamIterator(response.body);
      iterator = chunks;
      final prefix = BytesBuilder(copy: false);
      while (await chunks.moveNext()) {
        checkCancelled();
        final chunk = chunks.current;
        final remaining = prefixLimit - prefix.length;
        prefix.add(chunk.length > remaining ? chunk.sublist(0, remaining) : chunk);
        final bytes = prefix.toBytes();
        if (bytes.length >= 3 && (bytes[0] != 70 || bytes[1] != 76 || bytes[2] != 86)) return null;
        final codec = codecFromFlv(bytes);
        if (codec != null) return codec;
        if (prefix.length >= prefixLimit) return null;
      }
      return null;
    }

    try {
      final result = await read().timeout(probeTimeout);
      checkCancelled();
      return result;
    } on TransportFailure {
      checkCancelled();
      return null;
    } on TimeoutException {
      checkCancelled();
      return null;
    } finally {
      finished = true;
      local.cancel();
      await iterator?.cancel();
    }
  }
}
