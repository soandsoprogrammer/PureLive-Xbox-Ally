import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('G02.11: async native properties preserve values, unavailable states and errors', () async {
    MediaKit.ensureInitialized();
    final player = Player();
    addTearDown(player.dispose);
    final native = player.platform! as NativePlayer;
    final values = await Future.wait([
      native.getPropertyAsync('idle-active'),
      native.getPropertyAsync('pause'),
      native.getPropertyAsync('video-params/w'),
    ]);
    expect(values[0], 'yes');
    expect(values[1], anyOf('yes', 'no'));
    expect(values[2], isEmpty, reason: 'no source has been opened');
    await expectLater(native.getPropertyAsync('purelive-nonexistent-property'), throwsStateError);
    expect(await native.getPropertyAsync('idle-active'), 'yes', reason: 'a failed read must not poison later reads');
  });

  test('G02.11: async native reads reject a disposed handle', () async {
    MediaKit.ensureInitialized();
    final player = Player();
    final native = player.platform! as NativePlayer;
    await native.getPropertyAsync('idle-active');
    await player.dispose();
    await expectLater(native.getPropertyAsync('idle-active'), throwsStateError);
  });
}
