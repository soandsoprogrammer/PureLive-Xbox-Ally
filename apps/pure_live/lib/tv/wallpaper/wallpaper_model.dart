import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';

// The TV's background (docs/A-界面设计/A17-电视界面/A17.8-电视壁纸): what it
// is, how it fills the screen, the veil and the blur.

/// The seven fills, in pure_live_TV's order, with their words' keys.
const List<(BoxFit, String)> tvWallpaperFits = [
  (BoxFit.cover, 'tv_wallpaper_fit_cover'),
  (BoxFit.contain, 'tv_wallpaper_fit_contain'),
  (BoxFit.fill, 'tv_wallpaper_fit_fill'),
  (BoxFit.fitWidth, 'tv_wallpaper_fit_width'),
  (BoxFit.fitHeight, 'tv_wallpaper_fit_height'),
  (BoxFit.none, 'tv_wallpaper_fit_none'),
  (BoxFit.scaleDown, 'tv_wallpaper_fit_scale_down'),
];

/// The blur steps (A17.8 h1; 0 is none).
const List<double> tvWallpaperBlurs = [0, 2, 4, 6, 8, 12, 16, 24, 32, 48];

/// The fill stored as [name], `cover` when unknown.
BoxFit tvWallpaperFitOf(String name) {
  for (final (fit, _) in tvWallpaperFits) {
    if (fit.name == name) return fit;
  }
  return BoxFit.cover;
}

/// What a background is.
enum TvWallpaperKind {
  /// The theme's plain colour (as before).
  none,

  /// One colour.
  color,

  /// A gradient of [tvGradients].
  gradient,

  /// A picture file.
  image,

  /// A video file, muted and looping.
  video;

  /// The kind stored as [name], [none] when unknown.
  static TvWallpaperKind of(String name) => values.asNameMap()[name] ?? none;
}

/// A gradient background: one of the built-in [LiveSwatches.gradients].
extension TvGradientPaint on LiveGradientSwatch {
  /// The gradient to paint (CSS angles: 0 runs bottom to top, 90 left to
  /// right).
  LinearGradient get gradient {
    final radians = (degrees - 90) * math.pi / 180;
    final dx = math.cos(radians);
    final dy = math.sin(radians);
    return LinearGradient(begin: Alignment(-dx, -dy), end: Alignment(dx, dy), colors: colors);
  }
}

/// The built-in gradients.
List<LiveGradientSwatch> get tvGradients => LiveSwatches.gradients;

/// The gradient named [name], or null.
LiveGradientSwatch? tvGradientOf(String name) {
  for (final gradient in tvGradients) {
    if (gradient.name == name) return gradient;
  }
  return null;
}

/// The background as stored.
@immutable
final class TvWallpaper {
  /// Creates the background.
  const new({
    this.kind = TvWallpaperKind.none,
    this.value = '',
    this.source = '',
    this.fit = BoxFit.cover,
    this.mask = 0.35,
    this.blur = 0,
  });

  /// The background in [settings].
  factory of(SettingsStore settings) => TvWallpaper(
    kind: TvWallpaperKind.of(settings.get(Settings.tvWallpaperKind)),
    value: settings.get(Settings.tvWallpaperValue),
    source: settings.get(Settings.tvWallpaperSource),
    fit: tvWallpaperFitOf(settings.get(Settings.tvWallpaperFit)),
    mask: settings.get(Settings.tvWallpaperMask).clamp(0, 1).toDouble(),
    blur: settings.get(Settings.tvWallpaperBlur),
  );

  /// What it is.
  final TvWallpaperKind kind;

  /// The colour, gradient name or file.
  final String value;

  /// The address it came from.
  final String source;

  /// The fill.
  final BoxFit fit;

  /// The veil, 0 to 1.
  final double mask;

  /// The blur (pictures only).
  final double blur;

  /// Whether there is one (the pages then draw no plain colour of their own).
  bool get active => kind != TvWallpaperKind.none && value.isNotEmpty;
}
