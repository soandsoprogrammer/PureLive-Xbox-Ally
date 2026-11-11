import 'package:pure_live/platform/system_access.dart';

/// A user refusal, distinct from an invalid address or pairing code.
final class RemoteControlAccessDenied implements Exception {
  /// Creates the denial without any device or account data.
  const new();
}

/// Requests Android 17 LAN access before receiver, discovery or pairing I/O.
/// Other platforms use their existing native local-network privacy controls.
Future<void> ensurePlaybackRemoteAccess() async {
  if (!await SystemAccess.requestLocalNetwork()) throw const RemoteControlAccessDenied();
}
