import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

const _channel = MethodChannel('com.alexmercerind/media_kit_video');

/// Keeps a real idle native handle for decoder discovery; records output
/// commands without handing a fake Android Surface pointer to native code.
class _RecordingNative extends NativePlayer {
  new() : super(configuration: const PlayerConfiguration());

  final properties = <String, String>{};
  final writes = <String>[];
  Future<void> Function(String, String)? beforeSet;

  @override
  Future<void> setPropertyAsync(String property, String value) async {
    await beforeSet?.call(property, value);
    writes.add('$property=$value');
    properties[property] = value;
  }
}

class _Player implements Player {
  new(this.platform);

  @override
  PlatformPlayer? platform;

  @override
  Future<int> get handle => platform!.handle;

  @override
  PlayerStream get stream => platform!.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _surface(int handle, int wid) async {
  final done = Completer<void>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    _channel.name,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('VideoOutput.Resize', {
        'handle': handle,
        'id': 1,
        'wid': wid,
        'rect': const {'left': 0, 'top': 0, 'width': 640, 'height': 360},
      }),
    ),
    (_) => done.complete(),
  );
  await done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('G02.11: a Surface published during create remains attached after initialization', () async {
    MediaKit.ensureInitialized();
    final native = _RecordingNative();
    final player = _Player(native);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'VideoOutputManager.Create') {
          await _surface(await native.handle, 123);
          // Allow the early callback to finish before the create reply, as a
          // vendor platform channel can do. No real source or network is used.
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        return null;
      });
    addTearDown(() async {
      await native.dispose();
      messenger.setMockMethodCallHandler(_channel, null);
    });
    await AndroidVideoController.create(player, const VideoControllerConfiguration(vo: 'gpu', hwdec: 'no'));
    expect(native.properties['wid'], '123');
    expect(native.properties['vid'], 'auto');
    expect(native.properties['vo'], 'gpu', reason: 'startup defaults must not overwrite the available Surface');
  });

  test('G02.11: a Surface arriving during initial properties cannot interleave native writes', () async {
    MediaKit.ensureInitialized();
    final native = _RecordingNative();
    final reached = Completer<void>();
    final release = Completer<void>();
    native.beforeSet = (key, _) async {
      if (key == 'force-window') {
        reached.complete();
        await release.future;
      }
    };
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_channel, (_) async => null);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await native.dispose();
      messenger.setMockMethodCallHandler(_channel, null);
    });
    final creating = AndroidVideoController.create(
      _Player(native),
      const VideoControllerConfiguration(vo: 'gpu', hwdec: 'no'),
    );
    await reached.future;
    await _surface(await native.handle, 456);
    await Future<void>.delayed(const Duration(seconds: 1));
    final earlyWrites = List<String>.of(native.writes);
    release.complete();
    await creating;
    expect(earlyWrites, isNot(contains('vo=gpu')), reason: 'the Surface callback must wait for initial options');
    expect(native.properties['wid'], '456');
    expect(native.properties['vo'], 'gpu');
  });

  test('G02.11: creation without a Surface completes and a later callback enables video', () async {
    MediaKit.ensureInitialized();
    final native = _RecordingNative();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_channel, (_) async => null);
    addTearDown(() async {
      await native.dispose();
      messenger.setMockMethodCallHandler(_channel, null);
    });
    await AndroidVideoController.create(
      _Player(native),
      const VideoControllerConfiguration(vo: 'gpu', hwdec: 'no'),
    ).timeout(const Duration(seconds: 3));
    expect(native.properties['vo'], 'null');
    expect(native.properties['vid'], 'auto', reason: 'decoding must start before some devices publish a Surface');
    await _surface(await native.handle, 789);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(native.properties['wid'], '789');
    expect(native.properties['vo'], 'gpu');
  });
}
