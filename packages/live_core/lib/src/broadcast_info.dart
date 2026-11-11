import 'package:meta/meta.dart';

/// A platform-published preview. Display text is supplied by the platform;
/// streamer signatures and room titles are never interpreted as a schedule.
@immutable
final class LiveBroadcastPreview {
  /// Creates a preview, keeping its id as text to preserve 64-bit precision.
  const new({required this.id, required this.dateText, required this.timeText, this.startsAt});

  /// Platform appointment id.
  final String id;

  /// A date or recurring-day label, for example "每天".
  final String dateText;

  /// The platform's local time label, without an inferred timezone conversion.
  final String timeText;

  /// An absolute time only when the platform supplies an actual timestamp.
  final DateTime? startsAt;

  /// The platform's complete human-readable schedule.
  String get text => [dateText.trim(), timeText.trim()].where((part) => part.isNotEmpty).join(' ');
}

/// Ephemeral room information, kept with the current room session. It is not
/// serialized into follows, history or backups where a schedule could go stale.
@immutable
final class LiveBroadcastInfo {
  /// Creates the current platform-published information.
  const new({this.preview, this.dynamics = const []});

  /// The upcoming or recurring broadcast, null when removed or not published.
  final LiveBroadcastPreview? preview;

  /// Platform room announcements or activity text, independent of the title.
  final List<String> dynamics;
}

/// Which independently versioned information a room-sync event replaces.
enum LiveRoomInfoSection {
  /// The preview, including a removal with a null value.
  preview,

  /// Platform room announcements/activity, including removal with an empty list.
  dynamics,
}

/// A typed room metadata update; never a chat line or viewer count.
@immutable
final class LiveRoomInfoUpdate {
  /// Creates an update of one published section.
  const new({
    required this.broadcastId,
    required this.section,
    this.version = 0,
    this.preview,
    this.dynamics = const [],
  });

  /// The broadcast from which this update was received.
  final String broadcastId;

  /// The section to replace.
  final LiveRoomInfoSection section;

  /// Monotonic platform version within this broadcast and section, when given.
  final int version;

  /// New preview, null to remove it for [LiveRoomInfoSection.preview].
  final LiveBroadcastPreview? preview;

  /// New announcements for [LiveRoomInfoSection.dynamics].
  final List<String> dynamics;

  /// Applies just this section, preserving the other section's independent data.
  LiveBroadcastInfo applyTo(LiveBroadcastInfo? previous) => LiveBroadcastInfo(
    preview: section == LiveRoomInfoSection.preview ? preview : previous?.preview,
    dynamics: section == LiveRoomInfoSection.dynamics ? dynamics : previous?.dynamics ?? const [],
  );
}
