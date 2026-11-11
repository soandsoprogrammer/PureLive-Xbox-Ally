import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/tv/video/video_source.dart';

/// Where one archive or season stopped (the card bars and resume read it).
@immutable
final class VideoProgress {
  /// Creates the entry.
  const new({
    required this.cid,
    required this.position,
    required this.duration,
    this.epId = 0,
    this.page = 1,
    this.updatedAt = 0,
    this.title = '',
  });

  /// Reads a stored entry.
  factory fromJson(Map<String, Object?> json) => VideoProgress(
    cid: jsonInt(json['cid']) ?? 0,
    epId: jsonInt(json['epId']) ?? 0,
    page: jsonInt(json['page']) ?? 1,
    position: Duration(seconds: jsonInt(json['position']) ?? 0),
    duration: Duration(seconds: jsonInt(json['duration']) ?? 0),
    updatedAt: jsonInt(json['updatedAt']) ?? 0,
    title: jsonString(json['title']) ?? '',
  );

  /// The part or episode watched last.
  final int cid;

  /// Its episode id (PGC).
  final int epId;

  /// Its 1-based place.
  final int page;

  /// Where it stopped.
  final Duration position;

  /// Its length.
  final Duration duration;

  /// When, in seconds since the epoch.
  final int updatedAt;

  /// The part's or episode's title.
  final String title;

  /// How far, 0 to 1.
  double get fraction =>
      duration > Duration.zero ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0;

  /// The stored form.
  Map<String, Object?> toJson() => {
    'cid': cid,
    if (epId > 0) 'epId': epId,
    'page': page,
    'position': position.inSeconds,
    'duration': duration.inSeconds,
    'updatedAt': updatedAt,
    if (title.isNotEmpty) 'title': title,
  };
}

/// The player preferences of the video mode.
@immutable
final class VideoPrefs {
  /// Creates the preferences.
  const new({this.quality = 80, this.danmaku = true, this.subtitles = true, this.autoNext = true});

  /// Reads stored preferences.
  factory fromJson(Map<String, Object?> json) => VideoPrefs(
    quality: jsonInt(json['quality']) ?? 80,
    danmaku: json['danmaku'] != false,
    subtitles: json['subtitles'] != false,
    autoNext: json['autoNext'] != false,
  );

  /// The quality asked for (`qn`, default 1080P; the server caps it for
  /// guests and non-members).
  final int quality;

  /// Danmaku shown.
  final bool danmaku;

  /// Subtitles shown when the part has them.
  final bool subtitles;

  /// Plays the next part or episode at the end.
  final bool autoNext;

  /// A copy with changes.
  VideoPrefs copyWith({int? quality, bool? danmaku, bool? subtitles, bool? autoNext}) => VideoPrefs(
    quality: quality ?? this.quality,
    danmaku: danmaku ?? this.danmaku,
    subtitles: subtitles ?? this.subtitles,
    autoNext: autoNext ?? this.autoNext,
  );

  /// The stored form.
  Map<String, Object?> toJson() => {
    'quality': quality,
    'danmaku': danmaku,
    'subtitles': subtitles,
    'autoNext': autoNext,
  };
}

/// The video mode's own records in `live_store` (its meta table; video
/// on demand is new in v4, so there is nothing of 3.x to migrate): the
/// local watch progress, the search history and the player preferences.
final class VideoStore extends ChangeNotifier {
  /// Creates the store over [meta].
  new(this.meta, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The storage.
  final MetaStore meta;

  final DateTime Function() _now;

  /// Meta key of the progress map.
  static const String progressKey = 'tv_video.progress';

  /// Meta key of the search history.
  static const String searchKey = 'tv_video.search_history';

  /// Meta key of the preferences.
  static const String prefsKey = 'tv_video.prefs';

  /// How many archives keep their progress.
  static const int progressLimit = 500;

  /// How many searches are remembered.
  static const int searchLimit = 20;

  final Map<String, VideoProgress> _progress = {};
  List<String> _searches = const [];
  VideoPrefs _prefs = const VideoPrefs();
  Future<void>? _loading;
  bool _disposed = false;

  /// Reads the records once (later calls wait for the same read).
  Future<void> load() => _loading ??= () async {
    try {
      final progress = jsonDecode(await meta.get(progressKey) ?? '{}');
      if (progress is Map) {
        for (final MapEntry(:key, :value) in progress.entries) {
          if (value is Map<String, Object?>) _progress['$key'] = VideoProgress.fromJson(value);
        }
      }
      final searches = jsonDecode(await meta.get(searchKey) ?? '[]');
      if (searches is List) _searches = [for (final word in searches) '$word'];
      final prefs = jsonDecode(await meta.get(prefsKey) ?? '{}');
      if (prefs is Map<String, Object?>) _prefs = VideoPrefs.fromJson(prefs);
    } on FormatException {
      // A damaged record starts empty.
    }
    if (!_disposed) notifyListeners();
  }();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The progress of the archive or season [key] ([VideoItem.progressKey]).
  VideoProgress? progressOf(String key) => _progress[key];

  /// Records where [item] is; a part watched to the end drops the entry (it
  /// starts from the top next time). Writes only on a real move (another
  /// part, or 10 s since the stored position).
  Future<void> record(VideoItem item, Duration position, Duration duration) async {
    if (duration <= Duration.zero) return;
    final key = item.progressKey;
    if (key.isEmpty || key == 'ss0') return;
    final finished =
        position >= duration - const Duration(seconds: 5) || position.inMilliseconds / duration.inMilliseconds >= 0.98;
    final previous = _progress[key];
    if (finished) {
      if (previous == null || previous.cid != item.cid) return;
      _progress.remove(key);
    } else {
      if (previous != null &&
          previous.cid == item.cid &&
          (previous.position - position).abs() < const Duration(seconds: 10)) {
        return;
      }
      _progress.remove(key);
      _progress[key] = VideoProgress(
        cid: item.cid,
        epId: item.epId,
        page: item.page,
        position: position,
        duration: duration,
        updatedAt: _now().millisecondsSinceEpoch ~/ 1000,
        title: item.title,
      );
      while (_progress.length > progressLimit) {
        _progress.remove(_progress.keys.first);
      }
    }
    notifyListeners();
    await meta.set(progressKey, jsonEncode({for (final entry in _progress.entries) entry.key: entry.value.toJson()}));
  }

  /// Recent searches, newest first.
  List<String> get searches => _searches;

  /// Puts [keyword] first in the search history.
  Future<void> addSearch(String keyword) async {
    final word = keyword.trim();
    if (word.isEmpty) return;
    _searches = [word, ..._searches.where((item) => item != word)].take(searchLimit).toList();
    notifyListeners();
    await meta.set(searchKey, jsonEncode(_searches));
  }

  /// Removes one search, or all when [keyword] is null.
  Future<void> removeSearch([String? keyword]) async {
    _searches = keyword == null ? const [] : _searches.where((item) => item != keyword).toList();
    notifyListeners();
    await meta.set(searchKey, jsonEncode(_searches));
  }

  /// The player preferences.
  VideoPrefs get prefs => _prefs;

  /// Stores new preferences.
  Future<void> setPrefs(VideoPrefs prefs) async {
    _prefs = prefs;
    notifyListeners();
    await meta.set(prefsKey, jsonEncode(prefs.toJson()));
  }
}

/// The video mode's records (loaded on first use).
final Provider<VideoStore> videoStoreProvider = Provider((ref) {
  final store = VideoStore(ref.watch(storeProvider).meta);
  ref.onDispose(store.dispose);
  unawaited(store.load());
  return store;
});
