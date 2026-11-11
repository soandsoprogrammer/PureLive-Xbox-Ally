import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/services.dart';

/// What one track plays from: the play lines (main and backup hosts, with
/// the media headers and the expiry), and the audio rendition when it is
/// audio only (the cache downloads it).
typedef MusicStream = ({MusicTrack track, List<LivePlayLine> lines, VodRendition? audio, Map<String, String> headers});

/// Everything music mode asks the network for (M14.4), over `live_vod`
/// (M14.0). The pages and the player only see this interface, so tests
/// replace the whole network with a fake.
abstract interface class MusicCatalog {
  /// Whether a Bilibili login cookie is stored (cloud history, follows, fav
  /// folders and every write need one).
  bool get isLoggedIn;

  /// The music partition's ranking (`rid=3`).
  Future<List<VodArchive>> ranking();

  /// Video search, one page.
  Future<VodPage<VodArchive>> search(String keyword, {int page = 1});

  /// Trending search words.
  Future<List<VodHotword>> hotwords();

  /// The archive with every part.
  Future<VodArchive> detail(String bvid);

  /// Archives related to [bvid] (daily picks).
  Future<List<VodArchive>> related(String bvid);

  /// Cloud history, newest first, by cursor.
  Future<VodPage<VodHistoryEntry>> history({String? cursor});

  /// Deletes one archive's cloud history row.
  Future<void> deleteHistory(VodArchive archive);

  /// The account's followed uploaders.
  Future<VodPage<VodOwner>> followings({int page = 1});

  /// Follows or unfollows [mid] on the account.
  Future<void> setFollowing(int mid, {required bool follow});

  /// The account's own fav folders.
  Future<List<VodFavFolder>> favFolders();

  /// Every playable archive of a fav folder (up to 500).
  Future<List<VodArchive>> folderArchives(int folderId);

  /// An uploader's seasons and series (their playlists).
  Future<VodPage<VodUpCollection>> collections(int mid);

  /// The archives of one season or series.
  Future<VodPage<VodArchive>> collectionArchives(VodUpCollection collection, {int page = 1});

  /// An uploader's newest uploads.
  Future<VodPage<VodArchive>> uploads(int mid, {int page = 1});

  /// What [track] plays from: the best audio ([lossless] prefers Hi-Res)
  /// when [audioOnly], else the muxed MP4 (picture and sound).
  Future<MusicStream> stream(MusicTrack track, {required bool audioOnly, bool lossless = false});

  /// Reports the start of [track] to the cloud history (signed in only).
  Future<void> reportPlay(MusicTrack track);

  /// The songs of another platform's playlist (through the configured
  /// third-party mirror).
  Future<List<ImportedTrack>> importTracks(PlaylistPlatform platform, String id);

  /// The lyric sources in order (Bilibili BGM, lrc.cx, rangotec, NetEase).
  List<LyricSource> get lyricSources;

  /// Opens [url] with [headers] for the audio cache's download.
  Future<LiveStreamedResponse> download(String url, Map<String, String> headers);
}

/// The real catalog: Bilibili through the app's HTTP client and cookies,
/// the third-party services at the addresses of the music settings.
final class BilibiliMusicCatalog implements MusicCatalog {
  /// Creates the catalog over the app's [http], [cookies] and [settings].
  new({required this.http, required CookieVault cookies, required this.settings})
    : ugc = BilibiliUgcApi(BilibiliVodClient(http, cookies: cookies));

  /// Transport.
  final LiveHttp http;

  /// The music settings (third-party addresses).
  final SettingsStore settings;

  /// The UGC API.
  final BilibiliUgcApi ugc;

  /// The music API.
  late final BilibiliMusicApi music = BilibiliMusicApi(ugc);

  ThirdPartyEndpoints get _endpoints => ThirdPartyEndpoints.fromJson(settings.get(Settings.musicThirdPartyEndpoints));

  @override
  bool get isLoggedIn => ugc.client.isLoggedIn;

  @override
  Future<List<VodArchive>> ranking() => ugc.ranking(rid: 3);

  @override
  Future<VodPage<VodArchive>> search(String keyword, {int page = 1}) => ugc.searchVideos(keyword, page: page);

  @override
  Future<List<VodHotword>> hotwords() => ugc.hotwords();

  @override
  Future<VodArchive> detail(String bvid) => ugc.detail(bvid);

  @override
  Future<List<VodArchive>> related(String bvid) => ugc.related(bvid);

  @override
  Future<VodPage<VodHistoryEntry>> history({String? cursor}) => ugc.history(cursor: cursor, business: 'archive');

  @override
  Future<void> deleteHistory(VodArchive archive) => ugc.deleteHistory(['archive_${archive.aid}']);

  @override
  Future<VodPage<VodOwner>> followings({int page = 1}) => ugc.followings(page: page);

  @override
  Future<void> setFollowing(int mid, {required bool follow}) => ugc.setFollowing(mid, follow: follow);

  @override
  Future<List<VodFavFolder>> favFolders() => ugc.favFolders();

  @override
  Future<List<VodArchive>> folderArchives(int folderId) async {
    final archives = <VodArchive>[];
    for (var page = 1; page <= 25; page++) {
      final items = await ugc.favItems(folderId, page: page);
      archives.addAll([
        for (final item in items.items)
          if (!item.invalid) item.archive,
      ]);
      if (!items.hasMore || items.items.isEmpty) break;
    }
    return archives;
  }

  @override
  Future<VodPage<VodUpCollection>> collections(int mid) => music.collections(mid);

  @override
  Future<VodPage<VodArchive>> collectionArchives(VodUpCollection collection, {int page = 1}) =>
      music.collectionArchives(collection, page: page);

  @override
  Future<VodPage<VodArchive>> uploads(int mid, {int page = 1}) => ugc.uploads(mid, page: page);

  @override
  Future<MusicStream> stream(MusicTrack track, {required bool audioOnly, bool lossless = false}) async {
    final resolved = await music.resolve(track);
    if (audioOnly) {
      final (:streams, :audio) = await music.audio(resolved, lossless: lossless);
      return (track: resolved, lines: streams.linesOf(audio), audio: audio, headers: streams.headers);
    }
    final streams = await ugc.streams(bvid: resolved.archive.bvid, cid: resolved.part.cid, qn: 80, mp4: true);
    final segment = streams.segments.firstOrNull;
    if (segment == null) throw StreamUnavailable(vodSite, 'playurl: no mp4 for ${track.id}');
    return (track: resolved, lines: streams.linesOfSegment(segment), audio: null, headers: streams.headers);
  }

  @override
  Future<void> reportPlay(MusicTrack track) async {
    if (!isLoggedIn || track.archive.aid <= 0 || track.part.cid <= 0) return;
    await ugc.reportProgress(aid: track.archive.aid, cid: track.part.cid, progress: Duration.zero);
  }

  @override
  Future<List<ImportedTrack>> importTracks(PlaylistPlatform platform, String id) =>
      PlaylistImportSource(http, endpoints: _endpoints).fetch(platform, id);

  @override
  List<LyricSource> get lyricSources {
    final lyrics = ThirdPartyLyrics(http, endpoints: _endpoints);
    String titleOf(LyricQuery query) => Lrc.cleanTitle(query.title);
    return [
      (query) async {
        if (query.bvid.isEmpty || query.cid <= 0) return const [];
        final bgm = await music.bgmLyric(bvid: query.bvid, cid: query.cid, aid: query.aid);
        return [
          if (bgm != null) LyricCandidate(source: 'bilibili', lrc: bgm.lrc, title: bgm.title, artist: bgm.artist),
        ];
      },
      (query) => lyrics.lrcCx(title: titleOf(query), artist: query.artist),
      (query) => lyrics.rangotec(title: titleOf(query), artist: query.artist),
      (query) => lyrics.netease(query.artist.isEmpty ? titleOf(query) : '${titleOf(query)} ${query.artist}'),
    ];
  }

  @override
  Future<LiveStreamedResponse> download(String url, Map<String, String> headers) =>
      http.open(LiveRequest(site: vodSite, url: Uri.parse(url), headers: headers, timeout: const Duration(minutes: 5)));
}

/// Music mode's network (M14.4); tests override it with a fake.
final Provider<MusicCatalog> musicCatalogProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return BilibiliMusicCatalog(http: services.http, cookies: services.cookies, settings: services.store.settings);
});
