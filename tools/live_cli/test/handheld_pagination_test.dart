import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import '../bin/handheld_platforms.dart' as handheld;

class PagedSite extends LiveSite {
  @override
  String get id => 'douyu';
  @override
  String get name => 'Fixture';
  final pages = <int>[];

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    pages.add(page);
    if (page > 2) return [];
    return List.generate(40, (index) => LiveRoom(
      roomId: '${(page - 1) * 40 + index + 1}', platform: id, title: 'Room',
    ));
  }
}

void main() {
  test('Douyin follow live links use the room path, not the anchor id', () {
    final site = DouyinSite(ReplayHttp([]));
    expect(site.roomIdFromUrl('https://www.douyin.com/follow/live/952854931534?anchor_id=418233413547824'), '952854931534');
    expect(site.roomIdFromUrl('https://live.douyin.com/952854931534'), '952854931534');
    for (final url in [
      'https://www.douyin.com/video/952854931534',
      'https://www.douyin.com/follow/live/not-a-room',
      'https://www.douyin.com/follow/live/952854931534/extra',
      'https://www.douyin.com.example.com/follow/live/952854931534',
    ]) {
      expect(site.roomIdFromUrl(url), isNull);
    }
  });

  test('carousel and replay remain distinct from offline and live', () {
    for (final entry in {
      LiveStatus.live: 'live', LiveStatus.replay: 'replay',
      LiveStatus.carousel: 'replay', LiveStatus.offline: 'offline',
      LiveStatus.unknown: 'unknown',
    }.entries) {
      final room = LiveRoom(roomId: '1', platform: 'bilibili', liveStatus: entry.key);
      expect(handheld.broadcastStatus(room), entry.value);
    }
  });

  test('passes page numbers and retains every room in native-sized pages', () async {
    final site = PagedSite();
    final registry = SiteRegistry({'douyu': () => site});
    final http = ReplayHttp([]);
    final first = await handheld.findRooms(registry, http, 'douyu', '');
    final second = await handheld.findRooms(registry, http, 'douyu', '', page: 2);
    final end = await handheld.findRooms(registry, http, 'douyu', '', page: 3);
    expect(site.pages, [1, 2, 3]);
    expect(first.length, 40);
    expect(first.last['id'], '40');
    expect(second.first['id'], '41');
    expect(second.last['id'], '80');
    expect(end, isEmpty);
  });

  test('normalizes invalid page to first page', () async {
    final site = PagedSite();
    await handheld.findRooms(SiteRegistry({'douyu': () => site}), ReplayHttp([]), 'douyu', '', page: 0);
    expect(site.pages, [1]);
  });
}
