import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// What keeps a playing room on screen when the app is left
/// (docs/A-界面设计/A07-直播间界面/A07.25-小窗整体设计): nothing (the room plays on or
/// pauses as "后台播放" says), the app's floating window over the other apps,
/// or the system's picture-in-picture.
enum LeaveAppWindow {
  /// Nothing ("离开应用时自动小窗" off, the default as before).
  none,

  /// The system's picture-in-picture ([Settings.useSystemPip]).
  pip,

  /// The app's floating window (the default kind of mini window).
  overlay,
}

/// The mini window the button and leaving the app use (A07.25 c7, c12): the
/// app's floating window unless [Settings.useSystemPip].
LeaveAppWindow miniWindowKind(SettingsStore settings) =>
    settings.get(Settings.useSystemPip) ? LeaveAppWindow.pip : LeaveAppWindow.overlay;

/// What leaving the app does: nothing unless "离开应用时自动小窗"
/// ([Settings.autoPipOnLeave]), else [miniWindowKind].
LeaveAppWindow leaveAppWindow(SettingsStore settings) =>
    settings.get(Settings.autoPipOnLeave) ? miniWindowKind(settings) : LeaveAppWindow.none;

/// Once (A07.25): a user who had "离开应用时自动画中画" on before the floating
/// window came keeps the picture-in-picture; everyone else gets the floating
/// window. Writes [Settings.useSystemPip] the first time only.
Future<void> keepPictureInPicture(SettingsStore settings) async {
  if (settings.isSet(Settings.useSystemPip)) return;
  await settings.set(Settings.useSystemPip, settings.get(Settings.autoPipOnLeave));
}

/// The app's own floating window over other apps on Android (A07.25; native
/// `FloatingOverlay`, channel `pure_live/overlay`): when the app is left
/// while it is armed, the app's one engine draws in a small window above the
/// other apps; the in-app floating window fills it ([active]) with its own
/// buttons. Needs "显示在其他应用的上层" ([permitted], [openSettings]).
abstract final class OverlayWindow {
  static const MethodChannel _channel = MethodChannel('pure_live/overlay');

  /// Whether to treat this as Android (tests); null asks the platform.
  @visibleForTesting
  static bool? debugAndroid;

  static bool get _android => debugAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// Whether the app draws in the floating window now.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  /// Whether "显示在其他应用的上层" is given (looked at on start and every
  /// return to the app).
  static final ValueNotifier<bool> permitted = ValueNotifier(false);

  /// The room whose page the window took over (it opens again when the app
  /// comes back), or null.
  static LiveRoom? fromRoomPage;

  /// The side the native side tucked the window into (`left`, `right`), or
  /// null (A07.25 c8).
  static final ValueNotifier<String?> tucked = ValueNotifier(null);

  /// Where the window was when it went (logical pixels on the screen) and
  /// the side it was tucked into: the in-app window takes it (A07.25 c8).
  static final ValueNotifier<({Rect rect, String? tucked})?> placed = ValueNotifier(null);

  static bool _started = false;
  static Object? _owner;

  /// Listens to the native side; once, at start (Android only).
  static void start() {
    if (!_android || _started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'changed':
          active.value = call.arguments == true;
          if (!active.value) tucked.value = null;
        case 'tucked':
          tucked.value = call.arguments as String?;
        case 'placed':
          placed.value = placedFrom(call.arguments, _pixelRatio);
      }
    });
    AppLifecycleListener(onResume: () => unawaited(refresh()));
    unawaited(refresh());
  }

  /// Looks at the permission again.
  static Future<bool> refresh() async {
    if (!_android) return false;
    permitted.value = await _invoke<bool>('status') ?? false;
    return permitted.value;
  }

  /// Opens the system's "显示在其他应用的上层" page for this app.
  static Future<bool> openSettings() async => await _invoke<bool>('openSettings') ?? false;

  /// Lets leaving the app (home, recents) show the floating window at
  /// [window] (its place on the screen in logical pixels, [pixelRatio]
  /// physical ones each); [enabled] false stops that. [owner] is who arms
  /// it: only the one that armed it last can disarm it (a room page closing
  /// as the in-app floating window takes over does not undo the window's).
  static Future<void> arm({required bool enabled, Rect? window, double pixelRatio = 1, Object? owner}) async {
    if (!_android) return;
    if (enabled) {
      _owner = owner;
    } else if (owner != null && !identical(owner, _owner)) {
      return;
    } else {
      _owner = null;
    }
    final place = enabled ? window : null;
    await _invoke<void>('arm', {
      'enabled': place != null,
      'x': ((place?.left ?? 0) * pixelRatio).round(),
      'y': ((place?.top ?? 0) * pixelRatio).round(),
      'width': ((place?.width ?? 0) * pixelRatio).round(),
      'height': ((place?.height ?? 0) * pixelRatio).round(),
    });
  }

  /// The window's ✕: it goes, the app stays in the background.
  static Future<void> close() => _invoke<void>('close');

  /// A tap on a tucked window: it slides back to its side.
  static Future<void> untuck() => _invoke<void>('untuck');

  /// While the window's buttons show, its grip (the bottom right corner) is
  /// kept out of the system's back gesture ([on]).
  static Future<void> excludeGrip({required bool on}) => _invoke<void>('excludeGrip', {'on': on});

  /// Back to the app.
  static Future<bool> backToApp() async => await _invoke<bool>('backToApp') ?? false;

  /// A drag on the picture began: the native side moves the window with
  /// the finger.
  static Future<void> dragStart() => _invoke<void>('dragStart');

  /// A resize from the grip began: the native side sizes the window with
  /// the finger, the picture's shape kept, growing towards the middle of the
  /// screen (A07.25 c2).
  static Future<void> resizeStart() => _invoke<void>('resizeStart');

  /// Two fingers began to size the window (its centre stays).
  static Future<void> pinchStart() => _invoke<void>('pinchStart');

  /// The two fingers' [factor] since they began.
  static Future<void> pinch(double factor) => _invoke<void>('pinch', {'factor': factor});

  /// The fingers let go of a resize: the window settles on screen.
  static Future<void> resizeEnd() => _invoke<void>('resizeEnd');

  static double get _pixelRatio {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? 1 : views.first.devicePixelRatio;
  }

  /// The native side's `placed` [arguments] (`x`, `y`, `width`, `height` in
  /// physical pixels, `tucked`) in logical pixels at [pixelRatio].
  @visibleForTesting
  static ({Rect rect, String? tucked})? placedFrom(Object? arguments, double pixelRatio) {
    if (arguments is! Map || pixelRatio <= 0) return null;
    double read(String key) => (arguments[key] as num?)?.toDouble() ?? 0;
    final rect = Rect.fromLTWH(read('x'), read('y'), read('width'), read('height'));
    if (rect.isEmpty) return null;
    final side = arguments['tucked'];
    return (
      rect: Rect.fromLTWH(
        rect.left / pixelRatio,
        rect.top / pixelRatio,
        rect.width / pixelRatio,
        rect.height / pixelRatio,
      ),
      tucked: side is String ? side : null,
    );
  }

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
