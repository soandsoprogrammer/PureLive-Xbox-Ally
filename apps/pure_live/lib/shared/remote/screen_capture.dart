import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Platform screen capture only; cameras and microphones are never requested.
abstract final class ScreenCapture {
  static const _channel = MethodChannel('pure_live/screen_capture');
  static int _generation = 0;
  static int? _active;
  static VoidCallback? _onStopped;
  static StreamSubscription<String>? _projectionStops;

  /// Connects the locally visible notification's Stop button to all peers.
  static void onStopped(VoidCallback? callback) {
    _onStopped = callback;
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              final data = call.arguments;
              if (call.method == 'stopped' && data is Map && data['generation'] == _active) {
                _active = null;
                callback();
              }
            },
    );
  }

  /// Selects the actual OS display/window and requests fresh local consent.
  static Future<MediaStream> start() async {
    final attempt = ++_generation;
    DesktopCapturerSource? source;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (Platform.isMacOS && !await Helper.requestCapturePermission()) {
        throw StateError('screen capture permission denied');
      }
      final sources = await desktopCapturer.getSources(types: [SourceType.Window, SourceType.Screen]);
      final context = AppNavigator.navigatorContext;
      if (context == null || !context.mounted || sources.isEmpty) throw StateError('screen source unavailable');
      final selected = await showAppOptionDialog<String>(
        context: context,
        title: i18n('screen_share_source'),
        message: i18n('screen_share_source_desc'),
        selected: '',
        options: [for (final item in sources.take(64)) AppDialogOption(value: item.id, label: item.name)],
      );
      source = sources.where((item) => item.id == selected).firstOrNull;
      if (source == null) throw StateError('screen source selection canceled');
    }
    if (attempt != _generation) throw StateError('screen capture selection canceled');
    if (Platform.isAndroid) {
      // Consent first, foreground acknowledgement second, projection last.
      // A fresh token is mandatory for each session on Android14 and later.
      if (!await Helper.requestCapturePermission()) throw StateError('screen capture permission denied');
      if (attempt != _generation) throw StateError('screen capture permission canceled');
      _active = attempt;
      await _channel.invokeMethod<void>('start', {
        'generation': _active,
        'title': i18n('screen_share_active'),
        'text': i18n('screen_share_video_only'),
        'stop': i18n('screen_share_stop'),
      });
      if (_active != attempt) throw StateError('screen capture start canceled');
    }
    if (Platform.isIOS) _active = attempt;
    final captureGeneration = _active;
    Set<String>? tracks;
    final ended = <String>{};
    if (Platform.isAndroid || Platform.isIOS) {
      _projectionStops = ScreenCaptureEvents.stopped.listen((id) {
        if (_active != captureGeneration) return;
        final current = tracks;
        if (current == null) {
          // A user can revoke from the OS before getDisplayMedia returns.
          if (ended.length < 64) ended.add(id);
        } else if (current.contains(id)) {
          _active = null;
          _onStopped?.call();
        }
      });
    }
    try {
      final stream = await navigator.mediaDevices.getDisplayMedia({
        'audio': false,
        'video': source == null
            ? true
            : {
                'deviceId': {'exact': source.id},
                'mandatory': {'frameRate': 15.0},
              },
      });
      tracks = stream.getVideoTracks().map((track) => track.id!).toSet();
      if (attempt != _generation ||
          ((Platform.isAndroid || Platform.isIOS) && (_active != captureGeneration || ended.any(tracks.contains)))) {
        for (final track in stream.getTracks()) {
          await track.stop();
        }
        await stream.dispose();
        throw StateError('screen capture revoked before becoming ready');
      }
      return stream;
    } on Object {
      if (attempt == _generation) await stop();
      rethrow;
    }
  }

  /// Drops only this app's capture foreground lifetime.
  static Future<void> stop() async {
    _generation++;
    _active = null;
    await _projectionStops?.cancel();
    _projectionStops = null;
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stop');
  }
}
