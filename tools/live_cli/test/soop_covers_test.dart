import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

const original = 'https://liveimg.sooplive.com/m/123';
const categoryCover =
    'https://res.sooplive.com/images/thumb/live/0004_480x270_dark.png';

Map<String, Object?> card({
  Object? grade = 19,
  Object? category = '00040000',
  Object? password = 'N',
}) => {
  'user_id': 'cover_fixture',
  'broad_title': 'Fixture',
  'broad_cate_no': category,
  'broad_grade': grade,
  'is_password': password,
};

void main() {
  test('recommendations retain normal covers and replace age or password placeholders', () {
    String cover(Map<String, Object?> item) => SoopApi.recommendRooms(
      jsonEncode({
        'broad': [
          {...item, 'broad_thumb': original},
        ],
      }),
    ).single.cover;

    expect(cover(card(grade: 0)), original);
    expect(cover(card()), categoryCover);
    expect(cover(card(grade: 0, password: 'Y')), categoryCover);
    expect(cover(card(category: 40000)), categoryCover);
    for (final category in [null, '', 'invalid', '000400001']) {
      expect(cover(card(category: category)), original);
    }
  });

  test('search and area cards use the same category covers', () {
    final search = SoopApi.searchRooms(
      jsonEncode({
        'RESULT': 1,
        'REAL_BROAD': [
          {...card(), 'broad_img': original},
        ],
      }),
    );
    final areaCard = card()..remove('broad_cate_no');
    final area = SoopApi.areaRooms(
      jsonEncode({
        'result': 1,
        'data': {
          'list': [
            {...areaCard, 'category_no': '00040000', 'thumbnail': original},
          ],
        },
      }),
      areaName: 'Fixture',
    );
    expect(search.single.cover, categoryCover);
    expect(area.single.cover, categoryCover);
  });

  test('room refresh supplies a category cover for saved follows', () {
    final now = DateTime.utc(2026, 11, 19);
    final room = SoopApi.roomDetail(
      jsonEncode({
        'CHANNEL': {
          'RESULT': 1,
          'BNO': '123',
          'BJID': 'cover_fixture',
          'CATE': '00040000',
          'GRADE': 19,
          'VIEWPRESET': [],
        },
      }),
      requestedId: 'cover_fixture',
      now: now,
    );
    expect(room.cover, categoryCover);

    final station = SoopApi.station(
      jsonEncode({
        'station': {'user_nick': 'Fixture'},
        'broad': {
          'broad_no': '123',
          'broad_cate_no': '00040000',
          'broad_grade': 19,
        },
      }),
    );
    final saved = LiveRoom(
      roomId: 'cover_fixture',
      platform: 'soop',
      cover: original,
      liveStatus: LiveStatus.live,
    );
    expect(SoopApi.withStation(saved, station, now: now).cover, categoryCover);
  });
}
