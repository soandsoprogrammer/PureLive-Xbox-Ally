import 'package:flutter/widgets.dart';

/// iOS: a swipe in from the left edge goes back the room's way where the
/// system's back swipe is off (docs/A-界面设计/A18-苹果平台界面/A18.1-iOS和iPadOS差异设计 c3):
/// in full screen it leaves the full screen, with a panel open it closes the
/// panel — what [onBack] does. Only a swipe that starts within [edge] of the
/// left side and goes [distance] to the right counts; the rest of the
/// picture keeps its own gestures. Without [enabled], [child] alone.
class EdgeSwipeBack extends StatefulWidget {
  /// Wraps [child].
  const new({required this.enabled, required this.onBack, required this.child, super.key});

  /// Whether the swipe is caught (iOS, while the room holds its back).
  final bool enabled;

  /// The room's back.
  final VoidCallback onBack;

  /// The room.
  final Widget child;

  /// How far from the left side a swipe may start.
  static const double edge = 24;

  /// How far it has to go.
  static const double distance = 64;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  double _moved = 0;

  void _end(DragEndDetails details) {
    final fling = (details.primaryVelocity ?? 0) > 600;
    if (_moved >= EdgeSwipeBack.distance || (fling && _moved > 0)) widget.onBack();
    _moved = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: EdgeSwipeBack.edge,
          child: GestureDetector(
            key: const ValueKey('room-edge-swipe'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _moved = 0,
            onHorizontalDragUpdate: (details) => _moved += details.delta.dx,
            onHorizontalDragEnd: _end,
            onHorizontalDragCancel: () => _moved = 0,
          ),
        ),
      ],
    );
  }
}
