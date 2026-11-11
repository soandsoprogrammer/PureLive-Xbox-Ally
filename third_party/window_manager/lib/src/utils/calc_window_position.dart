import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';

Future<Offset> calcWindowPosition(
  Size windowSize,
  Alignment alignment,
) async {
  final manager = DisplayManager.instance;
  final displays = manager.getAll();
  late final Rect workArea;
  try {
    if (displays.isEmpty) throw StateError('No display available');
    final cursor = manager.getCursorPosition().toOffset();
    final current = displays.firstWhere(
      (display) => (display.position.toOffset() & display.size.toSize())
          .contains(cursor),
      orElse: () => displays.firstWhere(
        (display) => display.isPrimary,
        orElse: () => displays.first,
      ),
    );
    final candidate = current.workArea.toRect();
    workArea = candidate.isFinite && !candidate.isEmpty
        ? candidate
        : current.position.toOffset() & current.size.toSize();
  } finally {
    for (final display in displays) {
      display.dispose();
    }
  }
  final visibleWidth = workArea.width;
  final visibleHeight = workArea.height;
  final visibleStartX = workArea.left;
  final visibleStartY = workArea.top;
  Offset position = const Offset(0, 0);

  if (alignment == Alignment.topLeft) {
    position = Offset(
      visibleStartX + 0,
      visibleStartY + 0,
    );
  } else if (alignment == Alignment.topCenter) {
    position = Offset(
      visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
      visibleStartY + 0,
    );
  } else if (alignment == Alignment.topRight) {
    position = Offset(
      visibleStartX + visibleWidth - windowSize.width,
      visibleStartY + 0,
    );
  } else if (alignment == Alignment.centerLeft) {
    position = Offset(
      visibleStartX + 0,
      visibleStartY + ((visibleHeight / 2) - (windowSize.height / 2)),
    );
  } else if (alignment == Alignment.center) {
    position = Offset(
      visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
      visibleStartY + ((visibleHeight / 2) - (windowSize.height / 2)),
    );
  } else if (alignment == Alignment.centerRight) {
    position = Offset(
      visibleStartX + visibleWidth - windowSize.width,
      visibleStartY + ((visibleHeight / 2) - (windowSize.height / 2)),
    );
  } else if (alignment == Alignment.bottomLeft) {
    position = Offset(
      visibleStartX + 0,
      visibleStartY + (visibleHeight - windowSize.height),
    );
  } else if (alignment == Alignment.bottomCenter) {
    position = Offset(
      visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
      visibleStartY + (visibleHeight - windowSize.height),
    );
  } else if (alignment == Alignment.bottomRight) {
    position = Offset(
      visibleStartX + visibleWidth - windowSize.width,
      visibleStartY + (visibleHeight - windowSize.height),
    );
  } else {
    final left = (visibleWidth - windowSize.width) / 2 +
        alignment.x * ((visibleWidth - windowSize.width) / 2);
    final top = (visibleHeight - windowSize.height) / 2 +
        alignment.y * ((visibleHeight - windowSize.height) / 2);
    position = Offset(
      visibleStartX + left,
      visibleStartY + top,
    );
  }
  return position;
}
