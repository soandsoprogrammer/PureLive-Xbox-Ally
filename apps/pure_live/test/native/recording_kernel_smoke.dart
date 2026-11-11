// Cloud-only native check: local PCM input, no platform URLs or user data.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:pure_live/platform/recording_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final root = Directory('${Directory.systemTemp.path}/purelive-recording-kernel-smoke');
  await root.create(recursive: true);
  final result = <String, Object?>{'operating_system': Platform.operatingSystem, 'available': platformHasFfmpeg};
  try {
    if (!platformHasFfmpeg) throw StateError('The shipped native bundle is disabled');
    final input = File('${root.path}/silence.pcm');
    final output = File('${root.path}/silence.wav');
    await input.writeAsBytes(Uint8List(16000), flush: true);
    final execution = await FfmpegKitRunner()
        .start([
          '-hide_banner',
          '-nostdin',
          '-y',
          '-f',
          's16le',
          '-ar',
          '8000',
          '-ac',
          '1',
          '-i',
          input.path,
          '-t',
          '1',
          '-c:a',
          'pcm_s16le',
          output.path,
        ])
        .timeout(const Duration(seconds: 45));
    final code = await execution.exitCode.timeout(const Duration(seconds: 45));
    final bytes = await output.readAsBytes();
    final wave =
        bytes.length > 44 &&
        ascii.decode(bytes.sublist(0, 4)) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12)) == 'WAVE';
    result.addAll({'exit_code': code, 'bytes': bytes.length, 'riff_wave': wave, 'passed': code == 0 && wave});
  } on Object catch (error, stack) {
    result.addAll({'passed': false, 'error': error.toString(), 'stack': stack.toString()});
  }
  await File('${root.path}/result.json').writeAsString(jsonEncode(result), flush: true);
}
