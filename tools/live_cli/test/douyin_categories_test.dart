import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import '../bin/handheld_platforms.dart';

class CategorySite extends LiveSite {
  @override
  String get id => 'douyin';
  @override
  String get name => '抖音';
  bool available = true;
  int feedCalls = 0;
  final requests = <(String, int)>[];
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async => available ? [
    for (final name in ['游戏', '舞蹈', '聊天'])
      LiveCategory(id: 'dynamic-$name', name: name, children: [
        LiveArea(platform: id, areaId: 'dynamic-$name', areaName: name),
      ]),
  ] : [];
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    requests.add((category.areaId, page));
    return List.generate(15, (i) => LiveRoom(platform: id, roomId: '${page * 100 + i}'));
  }
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    feedCalls++;
    return [];
  }
}

void main() {
  test('category browsing resolves live catalog IDs and paginates without using random feed', () async {
    final site = CategorySite();
    final registry = SiteRegistry({'douyin': () => site});
    final http = ReplayHttp([]);
    final first = await findRooms(registry, http, 'douyin', '', category: 'game');
    final next = await findRooms(registry, http, 'douyin', '', category: 'game', page: 2);
    expect(first.length, 15);
    expect(next.first['id'], '200');
    await findRooms(registry, http, 'douyin', '', category: 'dance');
    await findRooms(registry, http, 'douyin', '', category: 'chat');
    expect(site.requests, [('dynamic-游戏', 1), ('dynamic-游戏', 2), ('dynamic-舞蹈', 1), ('dynamic-聊天', 1)]);
    expect(site.feedCalls, 0);
    await findRooms(registry, http, 'douyin', '', category: '');
    expect(site.feedCalls, 1);
  });
  test('missing or invalid categories report an error instead of silently returning unrelated rooms', () async {
    final site = CategorySite()..available = false;
    final registry = SiteRegistry({'douyin': () => site});
    final http = ReplayHttp([]);
    await expectLater(findRooms(registry, http, 'douyin', '', category: 'game'), throwsFormatException);
    await expectLater(findRooms(registry, http, 'douyin', '', category: 'invalid'), throwsFormatException);
    expect(site.feedCalls, 0);
  });
}
