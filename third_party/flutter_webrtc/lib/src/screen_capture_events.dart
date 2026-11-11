import 'native/event_channel.dart';

/// OS capture revocation, identified by its captured video track.
/// A stopped old projection cannot revoke a newly selected screen session.
abstract final class ScreenCaptureEvents {
  static Stream<String> get stopped => FlutterWebRTCEventChannel
      .instance.handleEvents.stream
      .where((event) => event['onScreenCaptureStopped']?['trackId'] is String)
      .map((event) => event['onScreenCaptureStopped']['trackId'] as String);
}
