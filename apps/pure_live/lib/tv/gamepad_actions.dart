import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Input actions sent by the Windows XInput runner.
enum GamepadAction {
  /// Move up.
  up,

  /// Move down.
  down,

  /// Move left.
  left,

  /// Move right.
  right,

  /// Activate the focused control.
  confirm,

  /// Return one level.
  back,

  /// Select the previous tab or room.
  previous,

  /// Select the next tab or room.
  next,

  /// Open search or the room list.
  list,

  /// Toggle the danmaku overlay.
  danmaku,

  /// Lower playback volume.
  volumeDown,

  /// Raise playback volume.
  volumeUp;

  /// The corresponding focus direction for directional actions.
  TraversalDirection? get direction => switch (this) {
    up => TraversalDirection.up,
    down => TraversalDirection.down,
    left => TraversalDirection.left,
    right => TraversalDirection.right,
    _ => null,
  };
}

/// Delivers native XInput actions to the nearest handler of the focused control.
class GamepadActions extends StatelessWidget {
  /// Registers a handler in the focus subtree.
  const new({required this.handle, required this.child, super.key});

  /// Returns true when the action was handled.
  final bool Function(GamepadAction) handle;

  /// The subtree to which the handler applies.
  final Widget child;

  static const _channel = MethodChannel('pure_live/gamepad');
  static final Map<String, GamepadAction> _actions = GamepadAction.values.asNameMap();

  /// Stops native polling and releases the message handler.
  static void uninstall() {
    unawaited(_channel.invokeMethod<void>('stop'));
    _channel.setMethodCallHandler(null);
  }

  /// Starts native polling and listens for actions.
  static void install() {
    _channel.setMethodCallHandler((call) async {
      final name = call.arguments;
      if (call.method != 'action' || name is! String) return;
      final action = _actions[name];
      if (action == null) return;
      final focus = FocusManager.instance.primaryFocus;
      final context = focus?.context;
      if (context != null) {
        var handled = false;
        context.visitAncestorElements((element) {
          final widget = element.widget;
          if (widget is GamepadActions) handled = widget.handle(action);
          return !handled;
        });
        if (handled) return;
      }
      if (action == GamepadAction.back) {
        final navigator = AppNavigator.navigatorContext;
        if (navigator != null) await Navigator.maybePop(navigator);
      } else if (action == GamepadAction.confirm && context != null) {
        Actions.maybeInvoke(context, const ActivateIntent());
      } else if (action.direction case final direction?) {
        focus?.focusInDirection(direction);
      }
    });
    unawaited(_channel.invokeMethod<void>('start'));
  }

  @override
  Widget build(BuildContext context) => child;
}
