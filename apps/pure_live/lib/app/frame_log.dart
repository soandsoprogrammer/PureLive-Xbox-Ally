import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Frame times in the log, for measuring on a phone (R01.3): built only with
/// `--dart-define=PL_FRAME_LOG=true`, so a release has none of it.
///
/// Each frame that missed its vsync is one `frame-jank` line (build, raster
/// and the whole span from vsync to the end of raster, in ms); every two
/// seconds with frames, a `frame-stats` line sums them up.
abstract final class FrameLog {
  /// Whether this build logs frames.
  static const bool enabled = bool.fromEnvironment('PL_FRAME_LOG');

  /// The frame budget: 120 Hz.
  static const Duration budget = Duration(microseconds: 8334);

  static final List<FrameTiming> _window = [];
  static int _windowStart = 0;

  /// Starts logging, when [enabled].
  static void install() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_record);
  }

  static void _record(List<FrameTiming> timings) {
    for (final timing in timings) {
      final total = timing.totalSpan;
      if (total > budget) {
        debugPrint(
          'frame-jank build=${_ms(timing.buildDuration)} raster=${_ms(timing.rasterDuration)} '
          'total=${_ms(total)} vsync=${timing.timestampInMicroseconds(FramePhase.vsyncStart)}',
        );
      }
      if (_window.isEmpty) _windowStart = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      _window.add(timing);
    }
    final now = timings.last.timestampInMicroseconds(FramePhase.rasterFinish);
    if (now - _windowStart < 2000000) return;
    final janky = _window.where((t) => t.totalSpan > budget).length;
    final builds = [for (final t in _window) t.buildDuration]..sort();
    final rasters = [for (final t in _window) t.rasterDuration]..sort();
    Duration p90(List<Duration> sorted) => sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
    debugPrint(
      'frame-stats frames=${_window.length} janky=$janky build_p90=${_ms(p90(builds))} '
      'raster_p90=${_ms(p90(rasters))} build_max=${_ms(builds.last)} raster_max=${_ms(rasters.last)}',
    );
    _window.clear();
  }

  static String _ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);
}
