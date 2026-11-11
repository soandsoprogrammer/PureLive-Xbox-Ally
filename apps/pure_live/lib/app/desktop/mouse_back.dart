import 'dart:async';
import 'dart:developer';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A desktop mouse's Back button uses the router's ordinary pop chain.
/// The delegate returns false at home; it never asks the OS to quit.
class DesktopMouseBack extends StatefulWidget {
  /// Wraps the application navigator, including its modal routes.
  const new({required this.enabled, required this.onBack, required this.child, super.key});

  /// Desktop targets only; mobile pointer handling stays unchanged.
  final bool enabled;

  /// The router delegate's popRoute, which handles modal and nested routes.
  final Future<bool> Function() onBack;

  /// The navigator and the application frame.
  final Widget child;

  @override
  State<DesktopMouseBack> createState() => _DesktopMouseBackState();
}

class _DesktopMouseBackState extends State<DesktopMouseBack> {
  bool _pending = false;

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pending || event.kind != PointerDeviceKind.mouse || event.buttons != kBackMouseButton) {
      return;
    }
    _pending = true;
    unawaited(_back());
  }

  Future<void> _back() async {
    try {
      await widget.onBack();
    } on Object catch (error, stack) {
      log('Mouse back navigation failed', name: 'Desktop', error: error, stackTrace: stack);
    } finally {
      _pending = false;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(onPointerDown: _down, child: widget.child);
}
