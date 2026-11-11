import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';

/// Binds shared playback commands to phone, TV and multiview pages.
/// Page-specific navigation stays with the page that owns it.
RemotePlaybackTarget playbackRemoteTarget({
  required bool Function() available,
  required LiveRoom? Function() room,
  required PlaybackSession? Function() session,
  required Future<void> Function() refresh,
  required Future<void> Function(double) volume,
  required Map<String, Future<bool> Function()> navigation,
}) {
  var lastVolume = 0.5;
  String? mutedRoom;
  return RemotePlaybackTarget(
    scope: () => room()?.identityKey ?? '',
    suspend: (valid) async {
      final player = session();
      final key = room()?.identityKey;
      if (player == null || key == null || player.state.status == PlaybackStatus.paused) return () async {};
      await player.pause();
      var owned = player.state.status == PlaybackStatus.paused;
      final subscription = player.states.listen((state) {
        if (state.status != PlaybackStatus.paused) owned = false;
      });
      return () async {
        await subscription.cancel();
        if (valid() &&
            owned &&
            identical(session(), player) &&
            room()?.identityKey == key &&
            player.state.status == PlaybackStatus.paused) {
          await refresh();
        }
      };
    },
    available: () => available() && room() != null && session() != null,
    snapshot: () {
      final current = room();
      final state = session()?.state;
      return {
        'nick': current?.nick,
        'title': current?.title,
        'platform': current?.platform,
        'roomKey': current?.identityKey,
        'paused': state?.status == PlaybackStatus.paused,
        'volume': state?.volume,
        'commands': ['play', 'pause', 'refresh', 'volume', 'mute', ...navigation.keys],
      };
    },
    execute: (command, value) async {
      if (!available()) return false;
      final player = session();
      final current = room();
      if (player == null || current == null) return false;
      if (navigation[command] case final callback?) return await callback();
      switch (command) {
        case 'play':
          await player.resume();
        case 'pause':
          await player.pause();
        case 'refresh':
          await refresh();
        case 'volume':
          if (value == null) return false;
          await volume(value);
        case 'mute':
          final level = player.state.volume;
          if (level > 0) {
            lastVolume = level;
            mutedRoom = current.identityKey;
            await volume(0);
          } else {
            await volume(mutedRoom == current.identityKey ? lastVolume : 0.5);
          }
        default:
          return false;
      }
      return true;
    },
  );
}
