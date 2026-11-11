import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone's media volume and the window's brightness
/// (`pure_live/device_controls` on Android and iOS; 3.x used the
/// volume_controller and screen_brightness plugins). Null where there is
/// no such control (desktop, tests).
abstract final class DeviceControls {
  static const MethodChannel _channel = MethodChannel('pure_live/device_controls');

  /// Whether the controls exist on this platform.
  static bool get available =>
      debugAvailable ??
      (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS));

  /// Replaces [available] (tests answer the channel themselves).
  @visibleForTesting
  static bool? debugAvailable;

  static Future<double?> _get(String method) async {
    if (!available) return null;
    try {
      return (await _channel.invokeMethod<num>(method))?.toDouble();
    } on Object {
      return null;
    }
  }

  static Future<void> _set(String method, double value) async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>(method, {'value': value.clamp(0.0, 1.0)});
    } on Object catch (error) {
      developer.log('$method failed', name: 'LivePlay', error: error);
    }
  }

  /// The media volume, 0 to 1.
  static Future<double?> volume() => _get('getVolume');

  /// Sets the media volume without the system's volume panel.
  static Future<void> setVolume(double value) => _set('setVolume', value);

  /// The window's brightness, 0 to 1 (the system's when not overridden).
  static Future<double?> brightness() => _get('getBrightness');

  /// Overrides the window's brightness.
  static Future<void> setBrightness(double value) => _set('setBrightness', value);

  /// Gives the brightness back to the system (leaving the room).
  static Future<void> resetBrightness() async {
    if (!available) return;
    try {
      await _channel.invokeMethod<void>('resetBrightness');
    } on Object {
      // The window is gone.
    }
  }
}
