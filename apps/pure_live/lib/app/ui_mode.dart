import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';

/// Whether this Windows build uses the handheld layout by default.
bool get isHandheldBuild =>
    defaultTargetPlatform == TargetPlatform.windows && const bool.fromEnvironment('PURE_LIVE_HANDHELD');

/// The interfaces the app has (M14.1): the phone and desktop one (3.x), and
/// the TV one (pure_live_TV's look and remote control).
enum UiMode {
  /// The TV interface on a television, the phone/desktop one elsewhere.
  auto,

  /// The phone and desktop interface everywhere.
  phone,

  /// The TV interface everywhere.
  tv;

  /// The stored value ([Settings.uiMode]); unknown values are [auto].
  static UiMode parse(String value) => values.asNameMap()[value] ?? auto;

  /// Whether this choice shows the TV interface on a device that
  /// [television] or not.
  bool showsTv({required bool television}) => switch (this) {
    auto => television || isHandheldBuild,
    phone => false,
    tv => true,
  };
}

/// Whether this device is a television, checked at start and on resume.
///
/// Android answers through `pure_live/app` `isTelevision` (`UiModeManager`
/// in television mode, or the leanback feature); every other system is not
/// one. A confirmed TV stays a TV during this process; a failed or negative
/// cold-start probe can be retried when Android's services are ready.
abstract final class TvDevice {
  static final _answer = ValueNotifier<bool?>(null);
  static Future<bool>? _pending;

  /// Notifications for recovered detection after the app is already visible.
  static ValueListenable<bool?> get changes => _answer;

  /// The answer of [detect]; false before it ran.
  static bool get isTelevision => _answer.value ?? false;

  /// The stored answer, null before [detect] (tests).
  @visibleForTesting
  static bool? get debugTelevision => _answer.value;

  /// Sets the answer (tests); null asks again on the next [detect].
  @visibleForTesting
  static set debugTelevision(bool? value) => _answer.value = value;

  /// Coalesces probes; transient startup failures never become a cached false.
  static Future<bool> detect({MethodChannel channel = const MethodChannel('pure_live/app')}) {
    if (isTelevision) return Future.value(true);
    if (defaultTargetPlatform != TargetPlatform.android) {
      _answer.value = false;
      return Future.value(false);
    }
    return _pending ??= _detect(channel).whenComplete(() => _pending = null);
  }

  static Future<bool> _detect(MethodChannel channel) async {
    try {
      final answer = await channel.invokeMethod<bool>('isTelevision');
      if (answer != null) _answer.value = isTelevision || answer;
    } on PlatformException {
      // The next resume retries rather than freezing the phone router.
    } on MissingPluginException {
      // Flutter/plugin startup can be retried after the first frame.
    }
    return isTelevision;
  }
}

/// Whether this device is a television ([TvDevice.isTelevision]; tests
/// override it).
final Provider<bool> televisionDeviceProvider = Provider((ref) {
  void changed() => ref.invalidateSelf();
  TvDevice.changes.addListener(changed);
  ref.onDispose(() => TvDevice.changes.removeListener(changed));
  return TvDevice.isTelevision;
});

/// Whether [settings] show the TV interface on this device.
bool showsTvInterface(SettingsStore settings, {required bool television}) =>
    UiMode.parse(settings.get(Settings.uiMode)).showsTv(television: television);
