import 'package:live_net/live_net.dart';
import 'package:live_vod/src/douyu/models.dart';

/// Read-only official video endpoints. Tests provide deterministic responses.
abstract interface class DouyuVodSource {
  /// Public recommendations.
  Future<DouyuVodPage> home({CancelToken? cancel});

  /// Search the explicit replay/video tab.
  Future<DouyuVodPage> search(String keyword, {bool replay = true, int page = 1, int limit = 20, CancelToken? cancel});

  /// An author's paged replay sessions/uploads.
  Future<DouyuVodPage> author(String id, {bool replay = true, int page = 1, int limit = 10, CancelToken? cancel});

  /// Current metadata and signing descriptor.
  Future<DouyuVodDetail> detail(String id, {CancelToken? cancel});

  /// Segments of the same broadcast.
  Future<List<DouyuVodVideo>> replaySegments(DouyuVodVideo video, {CancelToken? cancel});

  /// Fresh, permission-labelled renditions.
  Future<List<DouyuVodQuality>> qualities(DouyuVodDetail detail, {CancelToken? cancel});

  /// Position-based comments.
  Future<DouyuVodDanmakuChunk> danmaku(String id, Duration start, {CancelToken? cancel});
}
