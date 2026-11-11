import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/shared/rooms/playback_diagnostics.dart';

void main() {
  test('issue #33: terminal failure is recorded once and again after retry', () {
    final diagnostics = PlaybackFailureDiagnostics();
    const error = PlayerException(
      message: 'private transport detail',
      type: PlayerErrorType.codec,
      code: 'video_decoder_init',
    );
    const failed = PlaybackState(status: PlaybackStatus.error, error: error);
    expect(diagnostics.update(const PlaybackState(status: PlaybackStatus.opening)), isNull);
    expect(
      diagnostics.update(failed),
      'type=codec code=video_decoder_init decoder=hardware audioOnly=false video=none',
    );
    expect(diagnostics.update(failed.copyWith(volume: 0.5)), isNull);
    expect(diagnostics.update(const PlaybackState(status: PlaybackStatus.playing)), isNull);
    expect(diagnostics.update(failed), isNotNull);
  });

  test('issue #33: arbitrary codes, exception messages and nested errors are omitted', () {
    final diagnostics = PlaybackFailureDiagnostics();
    final error = PlayerException(
      message: 'https://example.invalid/private?cookie=private-value',
      type: PlayerErrorType.native,
      code: 'private_value',
      error: StateError('private account and headers'),
    );
    final result = diagnostics.update(PlaybackState(status: PlaybackStatus.error, error: error));
    expect(result, 'type=native code=unknown decoder=hardware audioOnly=false video=none');
    expect(result, isNot(contains('private')));
    expect(
      diagnostics.update(PlaybackState(status: PlaybackStatus.error, error: StateError('private'))),
      'type=unknown code=unknown decoder=hardware audioOnly=false video=none',
    );
  });
}
