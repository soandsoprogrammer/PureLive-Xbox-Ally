import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Models an old native stop whose completion has not arrived. The underlying
/// mpv handle and its initialization are real; only the stop reply is held.
class _HeldStopPlayer extends NativePlayer {
  new() : super(configuration: const PlayerConfiguration());

  final entered = Completer<void>();
  final stopReply = Completer<void>();

  @override
  Future<void> stop({bool open = false, bool notify = true, bool synchronized = true}) async {
    if (!entered.isCompleted) entered.complete();
    await stopReply.future;
    await super.stop(open: open, notify: notify, synchronized: synchronized);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('G02.12: an unfinished old disposal cannot block a replacement native player', () async {
    MediaKit.ensureInitialized();
    final old = _HeldStopPlayer();
    await old.waitForPlayerInitialization;
    final retiring = old.dispose();
    await old.entered.future;
    final next = Player();
    addTearDown(() async {
      old.stopReply.complete();
      await retiring;
      await next.dispose();
    });
    final native = next.platform! as NativePlayer;
    await native.waitForPlayerInitialization.timeout(const Duration(seconds: 2));
    await next.setVolume(27).timeout(const Duration(seconds: 2));
    expect(await native.getPropertyAsync('volume'), '27.000000');
    await next.pause().timeout(const Duration(seconds: 2));
    expect(await native.getPropertyAsync('pause'), 'yes');
    expect(old.stopReply.isCompleted, isFalse, reason: 'the replacement must work before old teardown completes');
  });
}
