import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:media_kit/media_kit.dart';

class _BrokenSetup extends NativePlayer {
  new() : super(configuration: const PlayerConfiguration());
  int releases = 0;
  @override
  Future<void> setPropertyAsync(String name, String value) async => throw StateError('controlled setup failure');
  @override
  Future<void> dispose({bool synchronized = true}) async {
    releases++;
    await super.dispose(synchronized: synchronized);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('G02.13: a failed engine factory releases its native handle before propagating', () async {
    MediaKit.ensureInitialized();
    final broken = _BrokenSetup();
    addTearDown(() async {
      if (broken.releases == 0) await broken.dispose();
    });
    final lines = <String>[];
    await expectLater(
      MpvEngine.create(
        onBufferingSnapshot: lines.add,
        createPlayer: () async {
          final wrapper = Player();
          await wrapper.dispose();
          wrapper.platform = broken;
          return wrapper;
        },
      ),
      throwsA(isA<StateError>().having((e) => e.message, 'original failure', 'controlled setup failure')),
    );
    expect(broken.releases, 1, reason: 'the session never receives this engine and cannot release its player');
    expect(lines, contains(contains('phase=create-failed')));
    expect(lines.every((line) => !line.contains('controlled setup failure')), isTrue);
  });
}
