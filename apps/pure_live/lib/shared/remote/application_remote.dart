import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/remote/native_remote_input.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';

/// Sends bounded navigation to Flutter's normal input and focus pipeline.
/// It never injects system input or reads a text field's existing value.
final class ApplicationRemote {
  /// [revision] includes page and popup changes, not just the named route.
  new({required this.revision, required this.back, required this.home, required this.available, this.focusRoot}) {
    _target = RemotePlaybackTarget(
      identity: () => '$_id:${revision()}',
      available: available,
      snapshot: () => {
        'title': i18n('remote_control_application'),
        'scope': 'application',
        'inputId': NativeRemoteInput.inputId ?? (_editable == null ? null : _inputId),
        'secretInput': _editable?.obscureText ?? false,
        'commands': ['up', 'down', 'left', 'right', 'ok', 'back', 'home'],
      },
      execute: (command, _) => execute(command),
    );
    FocusManager.instance.addListener(_focusChanged);
  }

  /// Current route-stack generation.
  final int Function() revision;

  /// The app's normal modal-aware Back action.
  final Future<bool> Function() back;

  /// Returns to this application's home page.
  final FutureOr<void> Function() home;

  /// False while the app is inactive or a local-only consent flow is open.
  final bool Function() available;

  /// The app navigator's focus, used after the platform restores view-level focus.
  final FocusNode? Function()? focusRoot;

  final String _id = UniqueKey().toString();
  late final RemotePlaybackTarget _target;
  int _inputId = 0;

  /// Lowest-priority target, used when no current playback page applies.
  RemotePlaybackTarget get target => _target;

  EditableText? get _editable =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>();

  /// Changes whenever the focused control or input is replaced.
  int get focusRevision => _inputId + NativeRemoteInput.revision;

  void _focusChanged() => _inputId++;

  /// Replaces only the selected range of the precise currently focused input.
  /// Text is never retained in protocol status, settings or logging.
  Future<bool> insertText(String text, int inputId) async {
    if (available() && NativeRemoteInput.inputId != null) return await NativeRemoteInput.insertText(inputId, text);
    if (!available() || inputId != _inputId || text.length > 4096) return false;
    final field = _editable;
    if (field == null || field.readOnly) return false;
    final current = field.controller.value;
    final selection = current.selection;
    final start = selection.isValid ? selection.start.clamp(0, current.text.length) : current.text.length;
    final end = selection.isValid ? selection.end.clamp(start, current.text.length) : start;
    field.controller.value = TextEditingValue(
      text: current.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    return true;
  }

  /// Runs one normal key press, retaining all page-specific focus handling.
  Future<bool> execute(String command) async {
    if (!available()) return false;
    if (NativeRemoteInput.inputId != null) {
      if (command != 'home') return await NativeRemoteInput.command(command);
      if (!await NativeRemoteInput.command('back')) return false;
    }
    if (command == 'back') return await back();
    if (command == 'home') {
      await home();
      return true;
    }
    final keys = switch (command) {
      'up' => (PhysicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp),
      'down' => (PhysicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowDown),
      'left' => (PhysicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft),
      'right' => (PhysicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowRight),
      'ok' => (PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter),
      _ => null,
    };
    if (keys == null) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed ||
        keyboard.physicalKeysPressed.contains(keys.$1)) {
      return false;
    }
    // Android can restore focus to View's outer scope after a native dialog
    // or route replacement. It lies above WidgetsApp's Shortcuts, so keys
    // there never reach app navigation. Reenter only when focus is outside
    // the application; keep a current dialog, field or global Stop action.
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext?.findAncestorWidgetOfExactType<WidgetsApp>() == null) {
      final root = focusRoot?.call();
      if (root != null && root.canRequestFocus) {
        // Navigator's public node is not a scope. Enter its current route's
        // traversable scope so the first arrow reaches visible controls.
        final scope = root.descendants
            .whereType<FocusScopeNode>()
            .where(
              (node) =>
                  !node.skipTraversal &&
                  node.canRequestFocus &&
                  node.enclosingScope == root.enclosingScope &&
                  node.traversalDescendants.isNotEmpty,
            )
            .firstOrNull;
        (scope ?? root).requestFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
      }
    }
    final now = WidgetsBinding.instance.currentSystemFrameTimeStamp;
    final dispatch = ServicesBinding.instance.platformDispatcher.onKeyData;
    if (dispatch == null) return false;
    try {
      dispatch(
        ui.KeyData(
          physical: keys.$1.usbHidUsage,
          logical: keys.$2.keyId,
          timeStamp: now,
          type: ui.KeyEventType.down,
          synthesized: true,
          character: null,
        ),
      );
    } finally {
      dispatch(
        ui.KeyData(
          physical: keys.$1.usbHidUsage,
          logical: keys.$2.keyId,
          timeStamp: now + const Duration(microseconds: 1),
          type: ui.KeyEventType.up,
          synthesized: true,
          character: null,
        ),
      );
    }
    return true;
  }

  /// Stops observing focus when this app instance shuts down.
  void dispose() => FocusManager.instance.removeListener(_focusChanged);
}
