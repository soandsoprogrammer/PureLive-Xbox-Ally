import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/platform/recording_platform.dart';

void main() {
  final workspace = Directory('../..');
  final config = File('${workspace.path}/pubspec.yaml').readAsStringSync();
  final bundles = File('${workspace.path}/tools/ffmpeg_kit/bundles.txt').readAsStringSync();
  final entries = RegExp(r'^  (\w+): \.ffmpeg_kit/(\S+)$', multiLine: true).allMatches(config);

  for (final entry in entries) {
    final os = entry[1]!;
    final filename = entry[2]!;
    test('the configured $os recording bundle enables its recorder', () {
      expect(bundles, contains('$filename\t'), reason: 'The build manifest must pin the native bundle');
      expect(hasBundledFfmpeg(os), isTrue, reason: 'Do not inject null FFmpeg for a platform whose bundle is shipped');
    });
  }

  test('unknown platforms remain unavailable', () {
    expect(hasBundledFfmpeg('fuchsia'), isFalse);
    expect(hasBundledFfmpeg('web'), isFalse);
    expect(hasBundledFfmpeg(''), isFalse);
  });

  test('the actual platform capability uses its operating system', () {
    expect(platformHasFfmpeg, hasBundledFfmpeg(Platform.operatingSystem));
  });
}
