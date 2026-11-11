import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/features/favorite/live_alert_watch.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

// "开播提醒" on Android (docs/O-Android系统集成/O01-通知和前台服务/O01.1-开播提醒;
// V01.1 L7): `pure_live/live_alerts` `post`, drawn by `LiveAlerts.kt`.

/// What the notification of [room] says (V01.1 L7): "晚风 开播了" (the
/// platform's name for a streamer without one) over the broadcast's title,
/// or "点按进入直播间" when there is none.
({String title, String text}) liveAlertContent(LiveRoom room) {
  final title = room.title.trim();
  return (
    title: i18n('live_alert_title', args: {'name': room.displayNick(platformName(room.platform))}),
    text: title.isEmpty ? i18n('live_alert_text_empty') : title,
  );
}

/// The arguments of `post`: the room to open (`platform`, `roomId`, and
/// `nick`, `roomTitle` for the room page before it loads), the words, the
/// broadcast's start (`since`, milliseconds since the epoch, shown as the
/// notification's time; null when the platform did not say) and the
/// channel's name and description.
Map<String, Object?> liveAlertArguments(LiveRoom room) =>
    liveAlertArgumentsOf(room, content: liveAlertContent(room), texts: liveAlertTexts());

/// The notification's words in the app's language (the background check
/// gets them through its file, O01.2).
LiveAlertTexts liveAlertTexts() => (
  title: i18n('live_alert_title', args: {'name': '{name}'}),
  empty: i18n('live_alert_text_empty'),
  channel: i18n('live_alert_channel_name'),
  channelDescription: i18n('live_alert_channel_desc'),
);

/// [liveAlertArguments] with the words given (the background check).
Map<String, Object?> liveAlertArgumentsOf(
  LiveRoom room, {
  required ({String title, String text}) content,
  required LiveAlertTexts texts,
}) {
  return {
    'platform': room.platform,
    'roomId': room.roomId,
    'nick': room.nick.trim(),
    'roomTitle': room.title.trim(),
    'title': content.title,
    'text': content.text,
    'since': room.startedAt?.millisecondsSinceEpoch,
    'channel': texts.channel,
    'channelDescription': texts.channelDescription,
  };
}

/// Android's go-live notifications (`pure_live/live_alerts`).
final class LiveAlertChannel {
  /// Creates the poster over [channel].
  const new({this.channel = const MethodChannel('pure_live/live_alerts')});

  /// The native channel.
  final MethodChannel channel;

  /// Posts [room]'s notification; a missing native side or a refusal is
  /// only logged (notifications off: Android drops it).
  Future<void> post(LiveRoom room) => postArguments(liveAlertArguments(room));

  /// Posts a notification of [arguments] ([liveAlertArguments]).
  Future<void> postArguments(Map<String, Object?> arguments) async {
    try {
      await channel.invokeMethod<bool>('post', arguments);
    } on PlatformException catch (error) {
      log('Live alert failed: ${error.message}', name: 'LiveAlerts');
    } on MissingPluginException {
      // A build without the native side.
    }
  }
}

/// Posts "开播提醒" where the platform can (Android), else null: the switch
/// is not offered and nothing is tracked.
final Provider<Future<void> Function(LiveRoom room)?> liveAlertPosterProvider = Provider(
  (ref) => !kIsWeb && Platform.isAndroid ? const LiveAlertChannel().post : null,
);

/// Android's periodic background check of "开播提醒" (O01.2):
/// `pure_live/live_alert_worker` `schedule` (`on`), run by
/// `LiveAlertWorker.kt`, which starts `liveAlertWorkerMain`.
final class LiveAlertWorkerChannel {
  /// Creates the switch over [channel].
  const new({this.channel = const MethodChannel('pure_live/live_alert_worker')});

  /// The native channel.
  final MethodChannel channel;

  /// Turns the periodic check on or off.
  Future<void> schedule({required bool on}) async {
    try {
      await channel.invokeMethod<void>('schedule', {'on': on});
    } on PlatformException catch (error) {
      log('Live alert worker failed: ${error.message}', name: 'LiveAlerts');
    } on MissingPluginException {
      // A build without the native side.
    }
  }
}

/// The shared file of the background check, in the app's support folder.
LiveAlertWatchFile liveAlertWatchFile() => LiveAlertWatchFile(
  getApplicationSupportDirectory().then((folder) => File(p.join(folder.path, LiveAlertWatchFile.name))),
);

/// The background check's side in the app (O01.2; Android), else null.
final Provider<LiveAlertBackground?> liveAlertBackgroundProvider = Provider(
  (ref) => !kIsWeb && Platform.isAndroid
      ? LiveAlertBackground(
          file: liveAlertWatchFile(),
          schedule: const LiveAlertWorkerChannel().schedule,
          texts: liveAlertTexts,
          nameOf: (room) => room.displayNick(platformName(room.platform)),
        )
      : null,
);
