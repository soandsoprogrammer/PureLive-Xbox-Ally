import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// Persistent signed gain overrides, independent of a room's 0..1 volume.
abstract final class RoomGain {
  /// The stored override, or null when the global setting applies.
  static int? overrideOf(SettingsStore settings, LiveRoom room) {
    final value = settings.get(Settings.roomVolumeGains)[room.identityKey];
    return value is num && value.isFinite ? value.round().clamp(-12, 12) : null;
  }

  /// The effective gain of this room on all layouts.
  static int effective(SettingsStore settings, LiveRoom room) =>
      overrideOf(settings, room) ?? settings.get(Settings.volumeBoostDb);

  /// Saves an override; null restores inheritance without changing the global setting.
  static Future<void> save(SettingsStore settings, LiveRoom room, int? decibels) async {
    final values = Map<String, Object?>.of(settings.get(Settings.roomVolumeGains));
    if (decibels == null) {
      values.remove(room.identityKey);
    } else {
      values[room.identityKey] = decibels.clamp(-12, 12);
    }
    await settings.set(Settings.roomVolumeGains, values);
  }
}
