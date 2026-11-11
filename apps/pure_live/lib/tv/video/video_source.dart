import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/vod.dart';

/// One playable thing of the video player: a part (分P) of an archive or an
/// episode of a season.
@immutable
final class VideoItem {
  /// Creates the item.
  const new({
    required this.cid,
    required this.title,
    this.bvid = '',
    this.aid = 0,
    this.epId = 0,
    this.seasonId = 0,
    this.page = 1,
    this.archiveTitle = '',
    this.cover = '',
    this.owner = const VodOwner(mid: 0, name: ''),
    this.duration = Duration.zero,
    this.badge = '',
    this.needsVip = false,
  });

  /// The parts of [archive] as items.
  static List<VideoItem> partsOf(VodArchive archive) => [
    for (final part in archive.playableParts)
      VideoItem(
        bvid: archive.bvid,
        aid: archive.aid,
        cid: part.cid,
        page: part.page,
        title: archive.playableParts.length > 1 && part.title.isNotEmpty ? part.title : archive.title,
        archiveTitle: archive.title,
        cover: archive.cover,
        owner: archive.owner,
        duration: part.duration > Duration.zero ? part.duration : archive.duration,
      ),
  ];

  /// The episodes of [season] as items.
  static List<VideoItem> episodesOf(PgcSeason season) => [
    for (final (index, episode) in season.episodes.indexed)
      VideoItem(
        bvid: episode.bvid,
        aid: episode.aid,
        cid: episode.cid,
        epId: episode.epId,
        seasonId: season.seasonId,
        page: index + 1,
        title: episodeTitle(episode),
        archiveTitle: season.title,
        cover: episode.cover.isNotEmpty ? episode.cover : season.cover,
        duration: episode.duration,
        badge: episode.badge,
        needsVip: episode.needsVip,
      ),
  ];

  /// What an episode is called: its show title, else "第 N 话 title".
  static String episodeTitle(PgcEpisode episode) {
    if (episode.showTitle.isNotEmpty) return episode.showTitle;
    final number = int.tryParse(episode.title);
    final head = number == null ? episode.title : '第$number话';
    return episode.longTitle.isEmpty ? head : '$head ${episode.longTitle}';
  }

  /// Archive id (UGC; PGC episodes have one too).
  final String bvid;

  /// Archive number id.
  final int aid;

  /// The part's or episode's content id.
  final int cid;

  /// Episode id (PGC), 0 for a part.
  final int epId;

  /// Season id (PGC), 0 for a part.
  final int seasonId;

  /// 1-based place in its archive or season.
  final int page;

  /// The part's or episode's title.
  final String title;

  /// The archive's or season's title.
  final String archiveTitle;

  /// Cover.
  final String cover;

  /// Uploader (parts).
  final VodOwner owner;

  /// Length.
  final Duration duration;

  /// The platform's badge (会员, 限免).
  final String badge;

  /// Member-only (PGC).
  final bool needsVip;

  /// Whether this is a PGC episode.
  bool get isEpisode => epId > 0;

  /// The key of the local watch progress: the archive for parts, the season
  /// for episodes.
  String get progressKey => isEpisode ? 'ss$seasonId' : bvid;

  /// The page the media requests name as Referer.
  String get pageUrl =>
      isEpisode ? 'https://www.bilibili.com/bangumi/play/ep$epId' : 'https://www.bilibili.com/video/$bvid/';
}

/// What the TV video pages ask of Bilibili (M14.0 `live_vod`), as one
/// interface so the pages can be tested with a fake. [LiveVodSource] is the
/// real one.
abstract interface class VideoSource {
  /// Whether a Bilibili login cookie is stored (the live login).
  bool get signedIn;

  /// Fires when the stored cookies change (sign in, sign out).
  Stream<void> get loginChanges;

  /// The home feed (personal when signed in), [page] 1-based.
  Future<List<VodArchive>> recommended(int page);

  /// Popular now.
  Future<VodPage<VodArchive>> popular(int page);

  /// A partition's ranking ([rid] 0 = all).
  Future<List<VodArchive>> ranking(int rid);

  /// Video dynamics of followed uploaders (signed in).
  Future<VodPage<VodDynamic>> dynamics(String? offset);

  /// The archive with its parts.
  Future<VodArchive> detail(String bvid);

  /// Archives related to [bvid].
  Future<List<VodArchive>> related(String bvid);

  /// Whether the user liked, coined and favourited [bvid] (signed in).
  Future<({bool liked, int coins, bool favorited})> relation(String bvid);

  /// Likes or un-likes.
  Future<void> setLike(int aid, {required bool like});

  /// Gives coins.
  Future<void> addCoin(int aid, {int multiply = 1, bool alsoLike = false});

  /// Like, coin and favourite at once.
  Future<void> triple(int aid);

  /// The user's folders; with [aid], which of them hold it.
  Future<List<VodFavFolder>> favFolders({int aid = 0});

  /// Adds to and removes from folders.
  Future<void> setFavorites(int aid, {List<int> add = const [], List<int> remove = const []});

  /// Adds to watch later.
  Future<void> addToView(int aid);

  /// Removes from watch later.
  Future<void> removeToView(int aid);

  /// Root comments, hot or newest first; [offset] from the previous page.
  Future<VodCommentPage> comments(int oid, {bool hot = true, String? offset});

  /// Replies under [root].
  Future<VodPage<VodComment>> replies(int oid, int root, {int page = 1});

  /// Likes or un-likes a comment.
  Future<void> likeComment(int oid, int rpid, {required bool like});

  /// An uploader's header.
  Future<VodUserSpace> userSpace(int mid);

  /// An uploader's followers and followings (guests too).
  Future<({int followers, int following})> relationStat(int mid);

  /// An uploader's videos.
  Future<VodPage<VodArchive>> uploads(int mid, {int page = 1, String order = 'pubdate'});

  /// Follows or unfollows an uploader.
  Future<void> setFollowing(int mid, {required bool follow});

  /// The user's followings.
  Future<VodPage<VodOwner>> followings(int page);

  /// One folder's videos.
  Future<VodPage<VodFavItem>> favItems(int mediaId, int page);

  /// Watch later.
  Future<List<VodArchive>> toView();

  /// Cloud history; [cursor] from the previous page.
  Future<VodPage<VodHistoryEntry>> history(String? cursor);

  /// Deletes history rows (`archive_{aid}`, `pgc_{seasonId}`).
  Future<void> deleteHistory(List<String> kids);

  /// Followed seasons ([type] 1 anime, 2 films and series).
  Future<VodPage<PgcCard>> followedSeasons(int type, int page);

  /// Follows (追番) or unfollows a season.
  Future<void> setSeasonFollowing(int seasonId, {required bool follow});

  /// Trending search words.
  Future<List<VodHotword>> hotwords();

  /// Video search.
  Future<VodPage<VodArchive>> searchVideos(String keyword, int page);

  /// Uploader search.
  Future<VodPage<VodSearchUser>> searchUsers(String keyword, int page);

  /// Season search: films and series when [movies], else anime.
  Future<VodPage<PgcCard>> searchSeasons(String keyword, int page, {required bool movies});

  /// One page of the PGC index.
  Future<VodPage<PgcCard>> pgcIndex(PgcType type, int page);

  /// A season by id or by one of its episodes.
  Future<PgcSeason> season({int? seasonId, int? epId});

  /// The streams of [item] at quality [qn] (0 = the server's choice).
  Future<VodStreams> streams(VideoItem item, {int qn = 0});

  /// Subtitles, the resume point and viewers of a part.
  Future<VodPlayerInfo> playerInfo(VideoItem item);

  /// The cues of a subtitle track.
  Future<List<VodSubtitleCue>> subtitleCues(VodSubtitleTrack track);

  /// How many 6-minute danmaku segments [item] has.
  Future<int> danmakuSegments(VideoItem item);

  /// One danmaku segment, 1-based.
  Future<List<VodDanmaku>> danmakuSegment(VideoItem item, int segment);

  /// The whole danmaku file (fallback).
  Future<List<VodDanmaku>> danmakuXml(VideoItem item);

  /// Reports the watch position to the cloud history (signed in).
  Future<void> reportProgress(VideoItem item, Duration progress);
}

/// [VideoSource] over `live_vod`'s APIs (the app's providers in
/// `lib/app/vod.dart`).
final class LiveVodSource implements VideoSource {
  /// Creates the source.
  new({required this.ugc, required this.pgc, required this.cookieChanges});

  /// Video endpoints.
  final BilibiliUgcApi ugc;

  /// PGC endpoints.
  final BilibiliPgcApi pgc;

  /// The cookie vault's change stream.
  final Stream<Object?> cookieChanges;

  @override
  bool get signedIn => ugc.client.isLoggedIn;

  @override
  Stream<void> get loginChanges => cookieChanges.map((_) {});

  @override
  Future<List<VodArchive>> recommended(int page) => ugc.recommended(page: page);

  @override
  Future<VodPage<VodArchive>> popular(int page) => ugc.popular(page: page);

  @override
  Future<List<VodArchive>> ranking(int rid) => ugc.ranking(rid: rid);

  @override
  Future<VodPage<VodDynamic>> dynamics(String? offset) => ugc.dynamics(offset: offset);

  @override
  Future<VodArchive> detail(String bvid) => ugc.detail(bvid);

  @override
  Future<List<VodArchive>> related(String bvid) => ugc.related(bvid);

  @override
  Future<({bool liked, int coins, bool favorited})> relation(String bvid) => ugc.relation(bvid: bvid);

  @override
  Future<void> setLike(int aid, {required bool like}) => ugc.setLike(aid, like: like);

  @override
  Future<void> addCoin(int aid, {int multiply = 1, bool alsoLike = false}) =>
      ugc.addCoin(aid, multiply: multiply, alsoLike: alsoLike);

  @override
  Future<void> triple(int aid) => ugc.triple(aid);

  @override
  Future<List<VodFavFolder>> favFolders({int aid = 0}) => ugc.favFolders(aid: aid);

  @override
  Future<void> setFavorites(int aid, {List<int> add = const [], List<int> remove = const []}) =>
      ugc.setFavorites(aid, add: add, remove: remove);

  @override
  Future<void> addToView(int aid) => ugc.addToView(aid);

  @override
  Future<void> removeToView(int aid) => ugc.removeToView(aid);

  @override
  Future<VodCommentPage> comments(int oid, {bool hot = true, String? offset}) =>
      ugc.comments(oid: oid, hot: hot, offset: offset);

  @override
  Future<VodPage<VodComment>> replies(int oid, int root, {int page = 1}) =>
      ugc.replies(oid: oid, root: root, page: page);

  @override
  Future<void> likeComment(int oid, int rpid, {required bool like}) =>
      ugc.likeComment(oid: oid, rpid: rpid, like: like);

  @override
  Future<VodUserSpace> userSpace(int mid) => ugc.userSpace(mid);

  @override
  Future<({int followers, int following})> relationStat(int mid) => ugc.relationStat(mid);

  @override
  Future<VodPage<VodArchive>> uploads(int mid, {int page = 1, String order = 'pubdate'}) =>
      ugc.uploads(mid, page: page, order: order);

  @override
  Future<void> setFollowing(int mid, {required bool follow}) => ugc.setFollowing(mid, follow: follow);

  @override
  Future<VodPage<VodOwner>> followings(int page) => ugc.followings(page: page);

  @override
  Future<VodPage<VodFavItem>> favItems(int mediaId, int page) => ugc.favItems(mediaId, page: page);

  @override
  Future<List<VodArchive>> toView() => ugc.toView();

  @override
  Future<VodPage<VodHistoryEntry>> history(String? cursor) => ugc.history(cursor: cursor);

  @override
  Future<void> deleteHistory(List<String> kids) => ugc.deleteHistory(kids);

  @override
  Future<VodPage<PgcCard>> followedSeasons(int type, int page) => pgc.followed(type: type, page: page);

  @override
  Future<void> setSeasonFollowing(int seasonId, {required bool follow}) => pgc.setFollowing(seasonId, follow: follow);

  @override
  Future<List<VodHotword>> hotwords() => ugc.hotwords(limit: 20);

  @override
  Future<VodPage<VodArchive>> searchVideos(String keyword, int page) => ugc.searchVideos(keyword, page: page);

  @override
  Future<VodPage<VodSearchUser>> searchUsers(String keyword, int page) => ugc.searchUsers(keyword, page: page);

  @override
  Future<VodPage<PgcCard>> searchSeasons(String keyword, int page, {required bool movies}) =>
      pgc.search(keyword, page: page, movies: movies);

  @override
  Future<VodPage<PgcCard>> pgcIndex(PgcType type, int page) => pgc.index(type: type, page: page);

  @override
  Future<PgcSeason> season({int? seasonId, int? epId}) => pgc.season(seasonId: seasonId, epId: epId);

  @override
  Future<VodStreams> streams(VideoItem item, {int qn = 0}) => item.isEpisode
      ? pgc.streams(epId: item.epId, cid: item.cid, qn: qn)
      : ugc.streams(bvid: item.bvid, cid: item.cid, qn: qn);

  @override
  Future<VodPlayerInfo> playerInfo(VideoItem item) => ugc.playerInfo(bvid: item.bvid, cid: item.cid, aid: item.aid);

  @override
  Future<List<VodSubtitleCue>> subtitleCues(VodSubtitleTrack track) => ugc.subtitleCues(track);

  @override
  Future<int> danmakuSegments(VideoItem item) =>
      ugc.danmakuSegments(aid: item.aid, cid: item.cid, duration: item.duration);

  @override
  Future<List<VodDanmaku>> danmakuSegment(VideoItem item, int segment) =>
      ugc.danmakuSegment(aid: item.aid, cid: item.cid, segment: segment);

  @override
  Future<List<VodDanmaku>> danmakuXml(VideoItem item) => ugc.danmakuXml(item.cid);

  @override
  Future<void> reportProgress(VideoItem item, Duration progress) =>
      ugc.reportProgress(aid: item.aid, cid: item.cid, progress: progress, epId: item.epId);
}

/// The video source of the TV pages (tests override it).
final Provider<VideoSource> videoSourceProvider = Provider(
  (ref) => LiveVodSource(
    ugc: ref.watch(vodUgcProvider),
    pgc: ref.watch(vodPgcProvider),
    cookieChanges: ref.watch(appServicesProvider).cookies.changes,
  ),
);
