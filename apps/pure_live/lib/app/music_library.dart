import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/music_catalog.dart';
import 'package:pure_live/app/services.dart';

/// Music mode's small state on `live_store`'s meta records (keys under
/// `music.`): read once at start, then served from memory, so live_vod's
/// synchronous [VodKeyValueStore] works on it; writes go through.
final class MusicMetaStore implements VodKeyValueStore {
  /// Creates the store over [meta]; call [load] first.
  new(this.meta);

  /// The records.
  final MetaStore meta;

  /// Every key music mode uses starts with this.
  static const String prefix = 'music.';

  final Map<String, String> _values = {};

  /// Reads every `music.` record.
  Future<void> load() async {
    _values
      ..clear()
      ..addAll(await meta.entries(prefix));
  }

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
    await meta.set(key, value);
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
    await meta.set(key, null);
  }

  /// The JSON value of [key], or null.
  Object? readJson(String key) {
    final text = _values[key];
    if (text == null || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// Stores [value] as JSON under [key].
  Future<void> writeJson(String key, Object? value) => write(key, jsonEncode(value));
}

/// One playlist the user made (or imported) on this device (pure_live_TV
/// `MusicUserPlaylist`).
@immutable
final class MusicPlaylist {
  /// Creates a playlist.
  const new({required this.id, required this.name, required this.createdAt, this.pinnedAt, this.tracks = const []});

  /// Reads [toJson]'s shape.
  factory fromJson(Map<String, Object?> json) => MusicPlaylist(
    id: jsonString(json['id']) ?? '',
    name: jsonString(json['name']) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(jsonInt(json['createdAt']) ?? 0),
    pinnedAt: switch (jsonInt(json['pinnedAt'])) {
      final int at when at > 0 => DateTime.fromMillisecondsSinceEpoch(at),
      _ => null,
    },
    tracks: _tracksOf(json['tracks']),
  );

  /// Identity.
  final String id;

  /// Name.
  final String name;

  /// When it was made.
  final DateTime createdAt;

  /// When it was pinned (pinned ones come first, newest pin first).
  final DateTime? pinnedAt;

  /// The songs, in order.
  final List<MusicTrack> tracks;

  /// A copy with the given fields.
  MusicPlaylist copyWith({String? name, DateTime? pinnedAt, bool unpin = false, List<MusicTrack>? tracks}) =>
      MusicPlaylist(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        pinnedAt: unpin ? null : pinnedAt ?? this.pinnedAt,
        tracks: tracks ?? this.tracks,
      );

  /// The stored shape.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'pinnedAt': pinnedAt?.millisecondsSinceEpoch ?? 0,
    'tracks': [for (final track in tracks) track.toJson()],
  };
}

/// A Bilibili fav folder kept on this device (pure_live_TV's synced
/// playlists): opens offline, refreshed by "sync".
@immutable
final class MusicSyncedFolder {
  /// Creates the entry.
  const new({required this.folder, this.archives = const [], this.syncedAt});

  /// Reads [toJson]'s shape.
  factory fromJson(Map<String, Object?> json) {
    final folder = json['folder'];
    return MusicSyncedFolder(
      folder: VodFavFolder.fromJson(folder is Map<String, Object?> ? folder : const {}),
      archives: [
        if (json['archives'] case final List<Object?> list)
          for (final item in list.whereType<Map<String, Object?>>()) VodArchive.fromJson(item),
      ],
      syncedAt: switch (jsonInt(json['syncedAt'])) {
        final int at when at > 0 => DateTime.fromMillisecondsSinceEpoch(at),
        _ => null,
      },
    );
  }

  /// The folder.
  final VodFavFolder folder;

  /// Its playable archives at the last sync.
  final List<VodArchive> archives;

  /// The last sync.
  final DateTime? syncedAt;

  /// Every part of every archive.
  List<MusicTrack> get tracks => [for (final archive in archives) ...MusicTrack.of(archive)];

  /// The stored shape.
  Map<String, Object?> toJson() => {
    'folder': folder.toJson(),
    'archives': [for (final archive in archives) archive.toJson()],
    'syncedAt': syncedAt?.millisecondsSinceEpoch ?? 0,
  };
}

List<MusicTrack> _tracksOf(Object? value) => [
  if (value is List<Object?>)
    for (final item in value.whereType<Map<String, Object?>>()) MusicTrack.fromJson(item),
];

/// The music library of this device (pure_live_TV `MusicLibraryController`
/// and `MusicPlaylistSyncController`): followed albums and uploaders, liked
/// songs, recent plays, the user's playlists and the synced fav folders;
/// plus the lyric chain and the daily picks, which keep their state in the
/// same store.
final class MusicLibrary extends ChangeNotifier {
  /// Creates the library; [ready] completes once the store is read.
  new({required this.store, required this.catalog, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Where everything is kept.
  final MusicMetaStore store;

  /// The network.
  final MusicCatalog catalog;

  final DateTime Function() _now;

  /// How many recent plays are kept.
  static const int recentsLimit = 100;

  /// The id of the liked-songs playlist (always first, not deletable).
  static const String likedId = 'liked';

  static const String _albumsKey = 'music.library.albums';
  static const String _upsKey = 'music.library.ups';
  static const String _recentsKey = 'music.library.recents';
  static const String _likedKey = 'music.library.liked';
  static const String _playlistsKey = 'music.library.playlists';
  static const String _foldersKey = 'music.library.folders';

  Future<void>? _loading;
  bool _ready = false;
  bool _disposed = false;

  List<VodArchive> _albums = const [];
  List<VodOwner> _ups = const [];
  List<MusicTrack> _recents = const [];
  List<MusicTrack> _liked = const [];
  List<MusicPlaylist> _playlists = const [];
  List<MusicSyncedFolder> _folders = const [];
  int? _syncing;

  /// Whether the store has been read.
  bool get isReady => _ready;

  /// Reads the store once.
  Future<void> ready() => _loading ??= _load();

  Future<void> _load() async {
    await store.load();
    List<T> rows<T>(String key, T Function(Map<String, Object?> json) read) => [
      if (store.readJson(key) case final List<Object?> list)
        for (final item in list.whereType<Map<String, Object?>>()) read(item),
    ];
    _albums = rows(_albumsKey, VodArchive.fromJson);
    _ups = rows(_upsKey, VodOwner.fromJson).where((up) => up.mid > 0).toList();
    _recents = rows(_recentsKey, MusicTrack.fromJson);
    _liked = rows(_likedKey, MusicTrack.fromJson);
    _playlists = rows(_playlistsKey, MusicPlaylist.fromJson).where((playlist) => playlist.id.isNotEmpty).toList();
    _folders = rows(_foldersKey, MusicSyncedFolder.fromJson);
    _ready = true;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Lyrics and daily picks --------------------------------------------------

  /// The lyric chain (manual pick, stored hit, then each source).
  late final LyricLookup lyrics = LyricLookup(sources: catalog.lyricSources, store: store);

  /// The daily picks.
  late final DailyRecommender daily = DailyRecommender(
    folderArchives: catalog.folderArchives,
    related: (seed) => catalog.related(seed.bvid),
    store: store,
    now: _now,
  );

  // Followed albums -----------------------------------------------------------

  /// Followed albums (archives), newest first.
  List<VodArchive> get albums => _albums;

  /// Whether [bvid] is followed.
  bool isAlbumFollowed(String bvid) => _albums.any((archive) => archive.bvid == bvid);

  /// Follows or unfollows [archive]; returns whether it is followed now.
  Future<bool> toggleAlbum(VodArchive archive) async {
    final followed = isAlbumFollowed(archive.bvid);
    _albums = followed
        ? [
            for (final item in _albums)
              if (item.bvid != archive.bvid) item,
          ]
        : [archive, ..._albums];
    _changed();
    await store.writeJson(_albumsKey, [for (final item in _albums) item.toJson()]);
    return !followed;
  }

  // Followed uploaders (local) --------------------------------------------------

  /// Uploaders followed on this device, newest first.
  List<VodOwner> get ups => _ups;

  /// Whether [mid] is followed here.
  bool isUpFollowed(int mid) => _ups.any((up) => up.mid == mid);

  /// Follows or unfollows [up] here; returns whether it is followed now.
  Future<bool> toggleUp(VodOwner up) async {
    final followed = isUpFollowed(up.mid);
    _ups = followed
        ? [
            for (final item in _ups)
              if (item.mid != up.mid) item,
          ]
        : [up, ..._ups];
    _changed();
    await store.writeJson(_upsKey, [for (final item in _ups) item.toJson()]);
    return !followed;
  }

  // Recent plays ----------------------------------------------------------------

  /// Tracks played, newest first.
  List<MusicTrack> get recents => _recents;

  /// [track] started playing.
  Future<void> recordPlay(MusicTrack track) async {
    _recents = [
      track,
      for (final item in _recents)
        if (item.id != track.id) item,
    ].take(recentsLimit).toList();
    _changed();
    await store.writeJson(_recentsKey, [for (final item in _recents) item.toJson()]);
  }

  /// Removes [track] from the recent plays.
  Future<void> removeRecent(MusicTrack track) async {
    _recents = [
      for (final item in _recents)
        if (item.id != track.id) item,
    ];
    _changed();
    await store.writeJson(_recentsKey, [for (final item in _recents) item.toJson()]);
  }

  /// Forgets every recent play.
  Future<void> clearRecents() async {
    _recents = const [];
    _changed();
    await store.remove(_recentsKey);
  }

  // Liked songs -------------------------------------------------------------------

  /// Liked songs, newest first.
  List<MusicTrack> get liked => _liked;

  /// Whether [track] is liked.
  bool isLiked(MusicTrack track) => _liked.any((item) => item.id == track.id);

  /// Likes or unlikes [track]; returns whether it is liked now.
  Future<bool> toggleLike(MusicTrack track) async {
    final liked = isLiked(track);
    _liked = liked
        ? [
            for (final item in _liked)
              if (item.id != track.id) item,
          ]
        : [track, ..._liked];
    _changed();
    await _saveLiked();
    return !liked;
  }

  Future<void> _saveLiked() => store.writeJson(_likedKey, [for (final item in _liked) item.toJson()]);

  // Playlists ---------------------------------------------------------------------

  /// The user's playlists: pinned first (newest pin first), then newest made
  /// first. The liked songs are not among them (see [likedId]).
  List<MusicPlaylist> get playlists {
    final pinned = _playlists.where((playlist) => playlist.pinnedAt != null).toList()
      ..sort((a, b) => b.pinnedAt!.compareTo(a.pinnedAt!));
    final rest = _playlists.where((playlist) => playlist.pinnedAt == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...pinned, ...rest];
  }

  /// The playlist [id] ([likedId] gives the liked songs), or null.
  MusicPlaylist? playlist(String id) => id == likedId
      ? MusicPlaylist(id: likedId, name: '', createdAt: DateTime.fromMillisecondsSinceEpoch(0), tracks: _liked)
      : _playlists.where((playlist) => playlist.id == id).firstOrNull;

  Future<void> _savePlaylists() =>
      store.writeJson(_playlistsKey, [for (final playlist in _playlists) playlist.toJson()]);

  /// Makes an empty playlist named [name] (trimmed; null when blank).
  Future<String?> createPlaylist(String name, {List<MusicTrack> tracks = const []}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final now = _now();
    var serial = now.microsecondsSinceEpoch;
    while (_playlists.any((playlist) => playlist.id == 'pl_$serial')) {
      serial++;
    }
    final id = 'pl_$serial';
    final unique = {for (final track in tracks) track.id: track}.values.toList();
    _playlists = [MusicPlaylist(id: id, name: trimmed, createdAt: now, tracks: unique), ..._playlists];
    _changed();
    await _savePlaylists();
    return id;
  }

  Future<void> _replace(String id, MusicPlaylist Function(MusicPlaylist playlist) change) async {
    if (id == likedId) {
      final next = change(playlist(likedId)!);
      _liked = next.tracks;
      _changed();
      await _saveLiked();
      return;
    }
    if (!_playlists.any((playlist) => playlist.id == id)) return;
    _playlists = [
      for (final playlist in _playlists)
        if (playlist.id == id) change(playlist) else playlist,
    ];
    _changed();
    await _savePlaylists();
  }

  /// Renames playlist [id].
  Future<void> renamePlaylist(String id, String name) async {
    if (name.trim().isEmpty) return;
    await _replace(id, (playlist) => playlist.copyWith(name: name.trim()));
  }

  /// Pins or unpins playlist [id].
  Future<void> togglePin(String id) => _replace(
    id,
    (playlist) => playlist.pinnedAt == null ? playlist.copyWith(pinnedAt: _now()) : playlist.copyWith(unpin: true),
  );

  /// Removes every song of playlist [id].
  Future<void> clearPlaylist(String id) => _replace(id, (playlist) => playlist.copyWith(tracks: const []));

  /// Deletes playlist [id].
  Future<void> deletePlaylist(String id) async {
    _playlists = [
      for (final playlist in _playlists)
        if (playlist.id != id) playlist,
    ];
    _changed();
    await _savePlaylists();
  }

  /// Adds [tracks] to playlist [id], skipping the ones it has; returns how
  /// many were added.
  Future<int> addTracks(String id, List<MusicTrack> tracks) async {
    final current = playlist(id);
    if (current == null) return 0;
    final known = {for (final track in current.tracks) track.id};
    final fresh = [
      for (final track in tracks)
        if (known.add(track.id)) track,
    ];
    if (fresh.isEmpty) return 0;
    await _replace(id, (playlist) => playlist.copyWith(tracks: [...playlist.tracks, ...fresh]));
    return fresh.length;
  }

  /// Removes [track] from playlist [id].
  Future<void> removeTrack(String id, MusicTrack track) => _replace(
    id,
    (playlist) => playlist.copyWith(
      tracks: [
        for (final item in playlist.tracks)
          if (item.id != track.id) item,
      ],
    ),
  );

  /// Moves song [from] of playlist [id] by [delta] places.
  Future<void> moveTrack(String id, int from, int delta) => _replace(id, (playlist) {
    final tracks = [...playlist.tracks];
    final to = from + delta;
    if (from < 0 || from >= tracks.length || to < 0 || to >= tracks.length) return playlist;
    tracks.insert(to, tracks.removeAt(from));
    return playlist.copyWith(tracks: tracks);
  });

  // Synced fav folders -------------------------------------------------------------

  /// Fav folders kept on this device.
  List<MusicSyncedFolder> get folders => _folders;

  /// The folder being synced, if any.
  int? get syncing => _syncing;

  /// The kept folder [id], or null.
  MusicSyncedFolder? folder(int id) => _folders.where((entry) => entry.folder.id == id).firstOrNull;

  Future<void> _saveFolders() => store.writeJson(_foldersKey, [for (final entry in _folders) entry.toJson()]);

  /// Downloads [folder]'s archives (pure_live_TV `syncFolder`). Throws the
  /// catalog's error.
  Future<void> syncFolder(VodFavFolder folder) async {
    if (_syncing != null) return;
    _syncing = folder.id;
    _changed();
    try {
      final archives = await catalog.folderArchives(folder.id);
      final entry = MusicSyncedFolder(folder: folder, archives: archives, syncedAt: _now());
      final next = [..._folders];
      final at = next.indexWhere((item) => item.folder.id == folder.id);
      if (at < 0) {
        next.add(entry);
      } else {
        next[at] = entry;
      }
      _folders = next;
      await _saveFolders();
    } finally {
      _syncing = null;
      _changed();
    }
  }

  /// Lists the account's folders and syncs each (pure_live_TV `syncAll`).
  Future<void> syncAll() async {
    for (final folder in await catalog.favFolders()) {
      await syncFolder(folder);
    }
  }

  /// Forgets the kept folder [id] (it stays on the account).
  Future<void> removeFolder(int id) async {
    _folders = [
      for (final entry in _folders)
        if (entry.folder.id != id) entry,
    ];
    _changed();
    await _saveFolders();
  }
}

/// The music library (M14.4), read from the store on first use.
final Provider<MusicLibrary> musicLibraryProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  final library = MusicLibrary(store: MusicMetaStore(services.store.meta), catalog: ref.watch(musicCatalogProvider));
  ref.onDispose(library.dispose);
  unawaited(library.ready());
  return library;
});
