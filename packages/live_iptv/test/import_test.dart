import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

/// Answers GETs from [bodies] by URL; anything else is a 404.
final class _FakeHttp implements LiveHttp {
  final bodies = <String, List<int>>{};
  final requests = <LiveRequest>[];
  Completer<void>? gate;
  Completer<void>? requested;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final started = requested;
    if (started != null && !started.isCompleted) started.complete();
    await gate?.future;
    final body = bodies[request.url.toString()];
    return LiveResponse(status: body == null ? 404 : 200, bytes: body ?? const [], url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

const _playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="cctv1" group-title="央视" tvg-logo="https://f/1.png" catchup="append" catchup-source="&s={utc}",CCTV-1
https://f/cctv1.m3u8|user-agent=TV
#EXTINF:-1 group-title="卫视",湖南卫视
https://f/hunan.m3u8
''';

const _guide = '''
<tv>
<channel id="cctv1"><display-name>CCTV-1 综合</display-name></channel>
<channel id="hunan"><display-name>湖南卫视</display-name></channel>
<programme channel="cctv1" start="20261001110000 +0000" stop="20261001130000 +0000"><title>新闻</title><desc>今日</desc></programme>
<programme channel="cctv1" start="20260920110000 +0000" stop="20260920130000 +0000"><title>Old</title></programme>
</tv>''';

void main() {
  late Directory directory;
  late MemoryIptvLibrary library;
  late _FakeHttp http;
  late IptvImporter importer;
  var selected = '';
  var clock = DateTime.utc(2026, 10, 1, 12);
  var ids = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('live_iptv_test');
    library = MemoryIptvLibrary();
    http = _FakeHttp();
    selected = '';
    clock = DateTime.utc(2026, 10, 1, 12);
    ids = 0;
    importer = IptvImporter(
      library: library,
      http: http,
      playlistDirectory: directory,
      selectedGuideSourceId: () => selected,
      autoSyncEnabled: () => true,
      now: () => clock,
      newId: () => '00000000-0000-4000-8000-${(++ids).toString().padLeft(12, '0')}',
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  IptvSite site() =>
      IptvSite(library: library, importer: importer, selectedGuideSourceId: () => selected, now: () => clock);

  for (final format in ['m3u', 'txt']) {
    test('issue 48: $format imports RTP and preserves it through room resolution', () async {
      const stream = 'rtp://239.1.2.3:5140';
      final body = format == 'm3u'
          ? '#EXTM3U\n#EXTINF:-1 group-title="News",CCTV1\n$stream\n'
          : 'News,#genre#\nCCTV1,$stream\n';
      final imported = await importer.importPlaylistText(body, 'multicast.$format');
      expect(imported.status, IptvImportStatus.imported);
      final channels = await library.channels(imported.id!);
      expect(channels.single.entry.streamUrl, stream);
      final iptv = site();
      final detail = await iptv.getRoomDetail(roomId: channels.single.id);
      final quality = (await iptv.getPlayQualities(detail: detail)).single;
      expect(await iptv.getPlayUrls(detail: detail, quality: quality), [stream]);
      expect(http.requests, isEmpty, reason: 'Parsing does not contact the multicast network');
    });
  }

  test('issue 48: direct RTP channel id is resolved without a playlist or network', () async {
    const stream = 'rtp://239.1.2.3:5140';
    final iptv = site();
    final detail = await iptv.getRoomDetail(roomId: stream);
    final quality = (await iptv.getPlayQualities(detail: detail)).single;
    expect(await iptv.getPlayUrls(detail: detail, quality: quality), [stream]);
    expect(http.requests, isEmpty);
  });

  test('URL import, guide import, mapping on sync and the platform view', () async {
    http.bodies['https://f/list/cn.m3u'] = utf8.encode(_playlist);
    http.bodies['https://f/epg.xml.gz'] = gzip.encode(utf8.encode(_guide));

    final imported = await importer.importPlaylistFromUrl('https://f/list/cn.m3u');
    expect(imported.status, IptvImportStatus.imported);
    final playlist = (await library.playlists()).single;
    expect((playlist.name, playlist.source, playlist.autoUpdate), ('cn', 'https://f/list/cn.m3u', true));
    expect(http.requests.first.site, 'iptv');

    final guide = await importer.importGuideFromUrl('https://f/epg.xml.gz');
    expect(guide.status, IptvImportStatus.imported);
    expect(http.requests.last.headers['user-agent'], IptvImporter.guideUserAgent);
    selected = guide.id!;
    final before = await library.channels(playlist.id);
    expect((await importer.syncPlaylist(playlist)).status, IptvImportStatus.imported);
    final after = await library.channels(playlist.id);
    expect(after.map((c) => c.id), before.map((c) => c.id), reason: 'ids survive a sync');
    expect((await library.mappings(playlist.id)).map((m) => m.channelId).toSet(), after.map((c) => c.id).toSet());

    final iptv = site();
    final categories = await iptv.getCategories(1, 30);
    expect(categories.single.name, 'cn');
    expect(categories.single.children.map((a) => (a.areaName, a.areaPic, a.platform)), [
      ('CCTV-1', 'https://f/1.png', 'iptv'),
      ('湖南卫视', '', 'iptv'),
    ]);
    final room = await iptv.getRoomDetail(roomId: after.first.id);
    expect((room.title, room.nick, room.area, room.liveStatus), ('CCTV-1', 'CCTV-1', '央视', LiveStatus.live));
    expect((room.currentProgramme, room.currentProgrammeDescription), ('新闻', '今日'));
    expect(room.epgId, epgChannelKey(selected, 'cctv1'));
    expect((room.catchUp.mode, room.catchUp.source), ('append', '&s={utc}'));
    expect(room.httpHeaders, {'user-agent': 'TV'});
    final qualities = await iptv.getPlayQualities(detail: room);
    expect(qualities.single.quality, '默认');
    expect(await iptv.getPlayUrls(detail: room, quality: qualities.single), ['https://f/cctv1.m3u8']);
    final area = await iptv.getCategoryRooms(categories.single.children.last);
    expect((area.single.title, area.single.nick), ('湖南卫视', '卫视'));
    expect(await iptv.getCategoryRooms(categories.single.children.last, page: 2), isEmpty);
    expect((await iptv.searchRooms('cctv')).single.roomId, after.first.id);
    expect(await iptv.searchRooms('  '), isEmpty);
    expect(
      await library.programmes(room.epgId!, from: DateTime.utc(2026, 9), to: DateTime.utc(2026, 11)),
      hasLength(1),
    );
  });

  test('unknown rooms: a stream URL plays as it is, anything else is NotFound', () async {
    final iptv = site();
    final room = await iptv.getRoomDetail(roomId: 'udp://239.0.0.1:1234');
    expect(await iptv.getPlayQualities(detail: room), hasLength(1));
    expect(() => iptv.getRoomDetail(roomId: 'gone'), throwsA(isA<NotFound>()));
    expect(await iptv.getPlayQualities(detail: LiveRoom(data: '   ')), isEmpty);
  });

  test('local import keeps a copy, asks before replacing, retires the old copy', () async {
    final first = await importer.importPlaylistText('央视,#genre#\nCCTV-1,http://f/1\n', 'list.txt');
    expect(first.status, IptvImportStatus.imported);
    final saved = (await library.playlists()).single;
    expect(saved.format, IptvPlaylistFormat.txt);
    expect(File(saved.source).existsSync(), isTrue);
    expect(p(saved.source), startsWith(directory.path));

    final declined = await importer.importPlaylistText(
      '#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n',
      'LIST',
      confirmReplace: (_) => false,
    );
    expect(declined.status, IptvImportStatus.cancelled);
    final replaced = await importer.importPlaylistText(
      '#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n',
      'LIST',
      confirmReplace: (_) => true,
    );
    expect(replaced.id, saved.id);
    final now = (await library.playlists()).single;
    expect(now.format, IptvPlaylistFormat.m3u);
    expect(File(saved.source).existsSync(), isFalse);
    expect((await importer.syncPlaylist(now)).status, IptvImportStatus.imported, reason: 'sync re-reads the copy');
    expect(await importer.deletePlaylist((await library.playlists()).single), isTrue);
    expect(directory.listSync(), isEmpty);
  });

  test('a cut-off download or an empty list keeps the saved playlist', () async {
    http.bodies['https://f/a.m3u'] = utf8.encode('#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n');
    final playlist = (await importer.importPlaylistFromUrl('https://f/a.m3u')).id!;
    http.bodies['https://f/a.m3u'] = utf8.encode('#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n#EXTINF:-1,B\n');
    final saved = (await library.playlist(playlist))!;
    expect((await importer.syncPlaylist(saved)).status, IptvImportStatus.invalid);
    http.bodies['https://f/a.m3u'] = utf8.encode('<html>');
    expect((await importer.syncPlaylist(saved)).status, IptvImportStatus.unsupportedFormat);
    http.bodies.remove('https://f/a.m3u');
    expect((await importer.syncPlaylist(saved)).status, IptvImportStatus.networkFailed);
    expect(await library.channels(playlist), hasLength(1));
    expect((await importer.importPlaylistFromUrl('https://f/page')).status, IptvImportStatus.networkFailed);
  });

  test('a list named "hot" stays a normal list; the hot list feeds recommendations', () async {
    http.bodies[IptvImporter.hotPlaylistUrl] = utf8.encode('#EXTM3U\n#EXTINF:-1,Hot\nhttp://f/hot\n');
    await importer.importPlaylistText('#EXTM3U\n#EXTINF:-1,Mine\nhttp://f/mine\n', 'hot');
    final rooms = await site().getRecommendRooms();
    expect(rooms.single.title, 'Hot');
    expect(rooms.single.introduction, 'Hot');
    expect((await site().getCategories(1, 30)).single.children.single.areaName, 'Mine');
    expect(await site().getRecommendRooms(page: 2), isEmpty);
  });

  test('L01.4: concurrent default initialization shares one download', () async {
    http
      ..bodies[IptvImporter.hotPlaylistUrl] = utf8.encode(_playlist)
      ..gate = Completer<void>()
      ..requested = Completer<void>();
    final rooms = site().hotRooms();
    await http.requested!.future;
    final settingsLoad = importer.loadHotPlaylist();
    http.gate!.complete();
    await settingsLoad;
    expect(await rooms, hasLength(2));
    expect(http.requests, hasLength(1));
    expect(await library.playlists(), hasLength(1));
  });

  test('L01.4: deletion preference changed during the first download prevents initialization', () async {
    var removed = false;
    final iptv = IptvSite(
      library: library,
      importer: importer,
      selectedGuideSourceId: () => selected,
      hotRemoved: () => removed,
    );
    http
      ..bodies[IptvImporter.hotPlaylistUrl] = utf8.encode(_playlist)
      ..gate = Completer<void>()
      ..requested = Completer<void>();
    final rooms = iptv.hotRooms();
    await http.requested!.future;
    final settingsLoad = importer.loadHotPlaylist();
    removed = true;
    http.gate!.complete();
    await settingsLoad;
    expect(await rooms, isEmpty);
    expect(http.requests, hasLength(1), reason: 'the second entry point shares the first live deletion guard');
    expect(await library.playlists(), isEmpty, reason: 'a restored deletion preference is authoritative');
  });

  test('L01.4: a late default download cannot restore a playlist deleted while it waited', () async {
    http.bodies[IptvImporter.hotPlaylistUrl] = utf8.encode(_playlist);
    await importer.loadHotPlaylist();
    final hot = (await library.playlist(IptvPlaylist.hotId))!;
    http
      ..gate = Completer<void>()
      ..requested = Completer<void>();
    final loading = importer.loadHotPlaylist();
    await http.requested!.future;
    expect(await importer.deletePlaylist(hot), isTrue);
    http.gate!.complete();
    await loading;
    expect(await library.playlist(IptvPlaylist.hotId), isNull);
    expect(await library.channels(IptvPlaylist.hotId), isEmpty);
  });

  test('L01.4: a late first download cannot replace a restored built-in playlist', () async {
    http
      ..bodies[IptvImporter.hotPlaylistUrl] = utf8.encode(_playlist)
      ..gate = Completer<void>()
      ..requested = Completer<void>();
    final loading = importer.loadHotPlaylist();
    await http.requested!.future;
    await importer.importPlaylist(
      bytes: utf8.encode('#EXTM3U\n#EXTINF:-1,Restored\nhttps://f/restored.m3u8\n'),
      format: IptvPlaylistFormat.m3u,
      name: IptvImporter.hotName,
      url: 'https://f/restored.m3u',
      isHot: true,
    );
    final restored = await library.playlist(IptvPlaylist.hotId);
    http.gate!.complete();
    await loading;
    expect(await library.playlist(IptvPlaylist.hotId), restored);
    expect((await library.channels(IptvPlaylist.hotId)).single.name, 'Restored');
  });

  test('L01.4: recommendations can still refill an existing empty built-in playlist', () async {
    http.bodies[IptvImporter.hotPlaylistUrl] = utf8.encode(_playlist);
    await importer.loadHotPlaylist();
    final hot = (await library.playlist(IptvPlaylist.hotId))!;
    await library.savePlaylist(hot, const [], expected: hot);
    expect(await site().hotRooms(), hasLength(2));
    expect(http.requests, hasLength(2));
    expect(await library.playlists(), hasLength(1));
  });

  test(
    'V02.9 (issue #6): recommendations show the chosen playlist; a deleted hot list is not imported again',
    () async {
      http.bodies[IptvImporter.hotPlaylistUrl] = utf8.encode('#EXTM3U\n#EXTINF:-1,Hot\nhttp://f/hot\n');
      http.bodies['https://f/net.m3u'] = utf8.encode('#EXTM3U\n#EXTINF:-1,Net\nhttp://f/net\n');
      await importer.importPlaylistText('#EXTM3U\n#EXTINF:-1,Mine\nhttp://f/mine\n', 'cn_all');
      await importer.importPlaylistFromUrl('https://f/net.m3u');
      final mine = (await library.playlists()).firstWhere((playlist) => playlist.name == 'cn_all');
      var wanted = '';
      var removed = false;
      IptvSite chosen() => IptvSite(
        library: library,
        importer: importer,
        selectedGuideSourceId: () => selected,
        popularPlaylistId: () => wanted,
        hotRemoved: () => removed,
        now: () => clock,
      );
      Future<List<String>> titles() async => [for (final room in await chosen().getRecommendRooms()) room.title];

      expect(await titles(), ['Hot'], reason: 'the built-in list by default, imported on first use');
      wanted = mine.id;
      expect(await titles(), ['Mine']);
      expect((await chosen().getRecommendRooms()).single.introduction, 'Mine');

      // The user deletes the built-in list (the page then sets hotRemoved).
      final hot = (await library.playlists()).firstWhere((playlist) => playlist.isHot);
      expect(await importer.deletePlaylist(hot), isTrue);
      removed = true;
      wanted = '';
      final requests = http.requests.length;
      expect(await titles(), ['Net'], reason: 'the first imported list: network ones first');
      expect(await chosen().hotRooms(), isEmpty);
      expect(http.requests, hasLength(requests), reason: 'the deleted hot list is not downloaded again');
      expect((await library.playlists()).where((playlist) => playlist.isHot), isEmpty);

      wanted = IptvPlaylist.hotId;
      expect(await titles(), ['Net'], reason: 'a deleted hot list cannot be chosen');
      wanted = 'gone';
      expect(await titles(), ['Net']);

      // Restored (the page clears hotRemoved): imported again.
      removed = false;
      wanted = '';
      expect(await titles(), ['Hot']);
    },
  );

  test('V02.9: the shown playlist', () {
    IptvPlaylist playlist(String id, String name, {bool remote = false}) => IptvPlaylist(
      id: id,
      name: name,
      source: remote ? 'https://f/$name.m3u' : '/f/$name.m3u',
      format: IptvPlaylistFormat.m3u,
    );
    final hot = playlist(IptvPlaylist.hotId, 'hot', remote: true);
    final local = playlist('a', 'Zed');
    final net = playlist('b', 'beta', remote: true);
    expect(shownIptvPlaylist([], wanted: '', hotRemoved: false), IptvPlaylist.hotId);
    expect(shownIptvPlaylist([], wanted: '', hotRemoved: true), isNull);
    expect(shownIptvPlaylist([hot, local, net], wanted: 'a', hotRemoved: false), 'a');
    expect(shownIptvPlaylist([hot, local, net], wanted: 'x', hotRemoved: false), IptvPlaylist.hotId);
    expect(shownIptvPlaylist([local, net], wanted: 'x', hotRemoved: true), 'b');
    expect(shownIptvPlaylist([hot, local], wanted: IptvPlaylist.hotId, hotRemoved: true), 'a');
    expect(shownIptvPlaylist([local, playlist('c', 'alpha')], wanted: '', hotRemoved: true), 'c');
  });

  test('automatic sync refreshes only due network sources with auto sync on', () async {
    http.bodies['https://f/a.m3u'] = utf8.encode('#EXTM3U\n#EXTINF:-1,A\nhttp://f/a\n');
    http.bodies['https://f/g.xml'] = utf8.encode(_guide);
    await importer.importPlaylistFromUrl('https://f/a.m3u');
    await importer.importGuideFromUrl('https://f/g.xml');
    await importer.importPlaylistText('#EXTM3U\n#EXTINF:-1,L\nhttp://f/l\n', 'local');
    expect(await importer.syncExpired(hours: 24), isEmpty);
    clock = clock.add(const Duration(hours: 25));
    final results = await importer.syncExpired(hours: 24);
    expect(results.map((r) => r.status), [IptvImportStatus.imported, IptvImportStatus.imported]);
    expect(IptvImporter.normalizeAutoSyncHours(1), 2);
    expect(IptvImporter.normalizeAutoSyncHours(500), 72);
  });

  test('guide replacement by name asks first; old programmes are pruned', () async {
    final bytes = utf8.encode(_guide);
    final first = await importer.importGuide(bytes: bytes, name: 'g', source: '/tmp/g.xml');
    final key = epgChannelKey(first.id!, 'cctv1');
    expect(await library.programmes(key, from: DateTime.utc(2026), to: DateTime.utc(2027)), hasLength(1));
    final declined = await importer.importGuide(
      bytes: bytes,
      name: 'G',
      source: '/tmp/g.xml',
      confirmReplace: (_) => false,
    );
    expect(declined.status, IptvImportStatus.cancelled);
    expect(
      (await importer.importGuide(bytes: utf8.encode('<tv><bad></tv>'), name: 'g', source: '')).status,
      IptvImportStatus.invalid,
    );
    expect(
      (await importer.importGuide(bytes: utf8.encode('<tv></tv>'), name: 'g', source: '')).status,
      IptvImportStatus.unsupportedFormat,
    );
    expect(await importer.deleteGuide((await library.guideSources()).single), isTrue);
  });
}

String p(String path) => File(path).absolute.path;
