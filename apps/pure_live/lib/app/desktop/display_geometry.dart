import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart' as screens;

/// A copied display geometry in logical pixels; no native handle escapes a read.
final class DesktopDisplayGeometry {
  /// Creates a display snapshot. The position distinguishes same-name monitors.
  const new({required this.name, required this.bounds, required this.workArea, required this.isPrimary});

  /// The OS monitor name, without a process-local native handle identifier.
  final String name;

  /// Full monitor bounds in the desktop coordinate space.
  final Rect bounds;

  /// Usable bounds, excluding task bars, menu bars and panels.
  final Rect workArea;

  /// Whether this is the primary display in this snapshot.
  final bool isPrimary;

  /// Persistent identity across nativeapi handle allocation and app restarts.
  String get persistenceKey => 'display-v1:${jsonEncode([name, bounds.left, bounds.top])}';

  /// Accepts an old platform ID only when its saved window is on this display.
  /// New keys distinguish monitors even when their old geometry overlaps.
  bool acceptsSavedWindow(String savedKey, Rect window) {
    if (!window.isFinite || window.isEmpty) return false;
    if (savedKey.startsWith('display-v1:')) return savedKey == persistenceKey;
    return workArea.contains(window.center);
  }
}

/// Reads current display geometry and releases every native object immediately.
List<DesktopDisplayGeometry> readDesktopDisplays() {
  final displays = screens.DisplayManager.instance.getAll();
  try {
    return [for (final display in displays) ?_snapshotDisplay(display)];
  } finally {
    for (final display in displays) {
      display.dispose();
    }
  }
}

DesktopDisplayGeometry? _snapshotDisplay(screens.Display display) {
  final bounds = display.position.toOffset() & display.size.toSize();
  final workArea = display.workArea.toRect();
  if (!bounds.isFinite || bounds.isEmpty) return null;
  return DesktopDisplayGeometry(
    name: display.name ?? '',
    bounds: bounds,
    workArea: workArea.isFinite && !workArea.isEmpty ? workArea : bounds,
    isPrimary: display.isPrimary,
  );
}
