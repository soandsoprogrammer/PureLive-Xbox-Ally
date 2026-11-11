import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Parts of the screen the system's back gesture leaves alone (Android 10+,
/// `View.systemGestureExclusionRects` through `pure_live/app`): the in-app
/// floating window tucked into a side, so pulling it back out does not go
/// back (the user's K90 report with full-screen gestures).
abstract final class SystemGestureExclusion {
  static const MethodChannel _channel = MethodChannel('pure_live/app');

  /// Whether to treat this as Android (tests); null asks the platform.
  @visibleForTesting
  static bool? debugAndroid;

  static bool get _android => debugAndroid ?? defaultTargetPlatform == TargetPlatform.android;

  /// What was sent last (tests read it).
  @visibleForTesting
  static List<Rect> current = const [];

  /// Keeps [rects] (logical pixels of the app's view, [pixelRatio] physical
  /// ones each) out of the back gesture; none clears it.
  static Future<void> set(List<Rect> rects, {double pixelRatio = 1}) async {
    current = rects;
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('setGestureExclusion', {
        'rects': [
          for (final rect in rects)
            [
              (rect.left * pixelRatio).round(),
              (rect.top * pixelRatio).round(),
              (rect.right * pixelRatio).round(),
              (rect.bottom * pixelRatio).round(),
            ],
        ],
      });
    } on PlatformException {
      // An older system: the gesture stays as it was.
    } on MissingPluginException {
      // No activity.
    }
  }
}
