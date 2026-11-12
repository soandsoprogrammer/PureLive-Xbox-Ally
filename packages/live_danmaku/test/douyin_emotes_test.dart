import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:test/test.dart';

const url = 'https://p3.douyinpic.com/example.webp';

DouyinDanmakuFrame frame(String method, ProtoWriter chat) {
  final envelope = ProtoWriter()
    ..string(1, method)
    ..bytes(2, chat.toBytes());
  final response = ProtoWriter()..bytes(1, envelope.toBytes());
  final push = ProtoWriter()..bytes(8, response.toBytes());
  return DouyinDanmakuProtocol.decode(push.toBytes(), roomId: '1');
}

ProtoWriter imagePiece(int field) {
  final image = ProtoWriter()..string(1, url);
  final value = ProtoWriter()..bytes(1, image.toBytes());
  return ProtoWriter()..bytes(field, value.toBytes());
}

void main() {
  test('reads inline emoji in the current web and legacy rich-text formats', () {
    for (final (container, textField, imageField) in [(41, 11, 25), (22, 3, 8)]) {
      final before = ProtoWriter()..string(textField, '前');
      final after = ProtoWriter()..string(textField, '后');
      final rich = ProtoWriter()
        ..bytes(4, before.toBytes())
        ..bytes(4, imagePiece(imageField).toBytes())
        ..bytes(4, after.toBytes());
      final chat = ProtoWriter()
        ..string(3, 'fallback')
        ..bytes(container, rich.toBytes());
      final result = frame('WebcastChatMessage', chat).messages.single;
      expect(result.message, '前[表情1]后');
      expect(result.emotes.single.url, url);
    }
  });

  test('reads standalone stickers and retains plain text if rich text is malformed', () {
    final rich = ProtoWriter()..bytes(4, imagePiece(25).toBytes());
    final sticker = ProtoWriter()
      ..bytes(4, rich.toBytes())
      ..string(5, '[表情]');
    final result = frame('WebcastEmojiChatMessage', sticker).messages.single;
    expect(result.message, '[表情1]');
    expect(result.emotes.single.code, '[表情1]');
    final chat = ProtoWriter()
      ..string(3, '普通弹幕')
      ..bytes(41, [128]);
    expect(frame('WebcastChatMessage', chat).messages.single.message, '普通弹幕');
  });
}
