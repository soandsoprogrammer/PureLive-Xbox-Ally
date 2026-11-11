import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  test('preview removal preserves room dynamics and metadata never becomes saved history', () {
    const preview = LiveBroadcastPreview(id: '123', dateText: '每天', timeText: '16:00');
    const original = LiveBroadcastInfo(preview: preview, dynamics: ['比赛安排已更新']);
    const removal = LiveRoomInfoUpdate(broadcastId: '1', section: LiveRoomInfoSection.preview, version: 2);
    final cleared = removal.applyTo(original);
    expect(cleared.preview, isNull);
    expect(cleared.dynamics, ['比赛安排已更新']);
    final room = LiveRoom(platform: 'douyin', roomId: '1', broadcastInfo: original);
    expect(room.copyWith(title: 'title').broadcastInfo, same(original));
    expect(room.toJson().keys, isNot(contains('broadcastInfo')));
    expect(LiveRoom.fromJson(room.toJson()).broadcastInfo, isNull);
  });
}
