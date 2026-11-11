import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:test/test.dart';

List<LiveMessage> decode(String method, List<int> payload) {
  final envelope =
      (ProtoWriter()
            ..string(1, method)
            ..bytes(2, payload))
          .toBytes();
  final response = (ProtoWriter()..bytes(1, envelope)).toBytes();
  final push = (ProtoWriter()..bytes(8, response)).toBytes();
  return DouyinDanmakuProtocol.decode(push, roomId: '123').messages;
}

List<int> highlight({String room = '123', String key = 'HighlightContainerSyncData', bool preview = true}) {
  final appointment =
      (ProtoWriter()
            ..integer(6, int.parse('7700422666431336449'))
            ..string(11, '每天')
            ..string(12, '16:00'))
          .toBytes();
  final item =
      (ProtoWriter()
            ..integer(100, 2)
            ..bytes(102, appointment))
          .toBytes();
  final content = ProtoWriter()..integer(2, 42);
  if (preview) content.bytes(1, item);
  return (ProtoWriter()
        ..integer(2, int.parse(room))
        ..string(3, key)
        ..integer(4, 43)
        ..bytes(5, content.toBytes()))
      .toBytes();
}

void main() {
  test('room highlight wire fields preserve exact appointment id and platform schedule', () {
    final messages = decode('WebcastRoomDataSyncMessage', highlight());
    expect(messages, hasLength(1));
    expect(messages.single.type, LiveMessageType.roomInfo);
    final update = messages.single.data! as LiveRoomInfoUpdate;
    expect(update.broadcastId, '123');
    expect(update.version, 43);
    expect(update.preview?.id, '7700422666431336449');
    expect(update.preview?.text, '每天 16:00');
    expect(update.preview?.startsAt, isNull);
    expect(messages.single.message, isEmpty);
  });

  test('an empty highlight removes a preview; other rooms and sync schemas do not', () {
    final update = decode('WebcastRoomDataSyncMessage', highlight(preview: false)).single.data! as LiveRoomInfoUpdate;
    expect(update.section, LiveRoomInfoSection.preview);
    expect(update.preview, isNull);
    expect(decode('WebcastRoomDataSyncMessage', highlight(room: '124')), isEmpty);
    expect(decode('WebcastRoomDataSyncMessage', highlight(key: 'RoomLinkMicSyncData')), isEmpty);
  });

  test('room intro carries separate dynamics and a real appointment without parsing its prose', () {
    final common =
        (ProtoWriter()
              ..integer(3, 123)
              ..integer(4, 100))
            .toBytes();
    final appointment =
        (ProtoWriter()
              ..integer(1, 1)
              ..string(2, '7700422666431336449')
              ..string(3, '每天16:00'))
            .toBytes();
    final intro =
        (ProtoWriter()
              ..bytes(1, common)
              ..string(4, '今天比赛改至晚上，详情见公告')
              ..bytes(22, appointment))
            .toBytes();
    final messages = decode('WebcastRoomIntroMessage', intro);
    expect(messages, hasLength(2));
    final dynamics = messages[0].data! as LiveRoomInfoUpdate;
    final preview = messages[1].data! as LiveRoomInfoUpdate;
    expect(dynamics.dynamics, ['今天比赛改至晚上，详情见公告']);
    expect(preview.preview?.text, '每天16:00');
    final proseOnly =
        (ProtoWriter()
              ..bytes(1, common)
              ..string(4, '每天16:00'))
            .toBytes();
    expect(decode('WebcastRoomIntroMessage', proseOnly), hasLength(1));
    expect((decode('WebcastRoomIntroMessage', proseOnly).single.data! as LiveRoomInfoUpdate).preview, isNull);
  });
}
