import 'package:flutter/services.dart';

/// The app's own Android TV input dialog, never another app or the system IME.
abstract final class NativeRemoteInput {
  static const _channel = MethodChannel('pure_live/app');
  static int _next = 0;
  static int? _pending;
  static int _revision = 0;

  /// Negative identifiers cannot collide with Flutter focus generations.
  static int? get inputId => _pending == null ? null : -_pending!;

  /// Invalidates queued input when a native dialog opens or closes.
  static int get revision => _revision;

  /// Opens the existing app-owned native editor and bounds its input lifetime.
  static Future<String?> prompt(Map<String, Object?> fields) async {
    if (_pending != null) throw StateError('native input already open');
    final id = ++_next;
    _pending = id;
    _revision++;
    try {
      return await _channel.invokeMethod<String>('inputText', {...fields, 'remoteInputId': id});
    } finally {
      if (_pending == id) {
        _pending = null;
        _revision++;
      }
    }
  }

  /// Submits to the exact still-open native dialog through its ordinary OK path.
  static Future<bool> insertText(int id, String text) async {
    if (id != inputId || text.length > 4096) return false;
    return await _channel.invokeMethod<bool>('remoteInputText', {'id': -id, 'text': text}) ?? false;
  }

  /// Delivers only this fixed key set to that same app-owned dialog.
  static Future<bool> command(String command) async {
    final id = _pending;
    if (id == null || !{'up', 'down', 'left', 'right', 'ok', 'back'}.contains(command)) return false;
    return await _channel.invokeMethod<bool>('remoteInputCommand', {'id': id, 'command': command}) ?? false;
  }
}
