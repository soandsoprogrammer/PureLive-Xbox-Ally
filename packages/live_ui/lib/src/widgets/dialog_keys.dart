import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The keyboard of a dialog on computers (docs/specs/UI.md §5.4): Enter
/// presses the main button ([onEnter]) and, when given, Esc runs [onEscape]
/// (a dialog that a tap outside does not close gets no Esc from the route).
///
/// The dialog takes the focus when it opens, unless [autofocus] is off
/// because something inside takes it (a text field, the "取消" of a
/// destructive question); Enter on a focused button still presses that
/// button.
///
/// A TV remote has only the arrows and OK (issue #8): the dialog is a focus
/// scope, so an arrow while the dialog itself holds the focus goes to the
/// first control that way (a plain focus node held it, every control lay
/// inside its own area, and the arrows found nothing); OK there moves to the
/// first control instead of pressing anything unseen.
class DialogKeys extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, this.onEnter, this.onEscape, this.autofocus = true, super.key});

  /// The dialog.
  final Widget child;

  /// The main button's action.
  final VoidCallback? onEnter;

  /// Esc's action; null leaves Esc to the route.
  final VoidCallback? onEscape;

  /// Whether the dialog takes the focus when it opens.
  final bool autofocus;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && onEscape != null) {
      onEscape!();
      return KeyEventResult.handled;
    }
    // Only the dialog's own focus: a focused button keeps its Enter and OK.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (onEnter != null && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
      onEnter!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.gameButtonA) {
      node.nextFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => FocusScope(autofocus: autofocus, onKeyEvent: _onKey, child: child);
}
