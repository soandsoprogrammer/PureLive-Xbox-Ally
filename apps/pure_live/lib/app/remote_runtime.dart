import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/app/intake/system_intake.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/remote/application_remote.dart';
import 'package:pure_live/shared/remote/native_remote_input.dart';
import 'package:pure_live/shared/remote/screen_capture.dart';

/// Wires LAN link pushes to the same supported-platform parser as system shares.
/// Revoking pairing while a short link resolves prevents late navigation.
void installPlaybackRemote(AppServices services) {
  final share = services.screenShare;
  var mirrorOpening = false;
  void screenChanged() {
    if (!share.receiving || mirrorOpening || liveRouteObserver.topPage.value?.name == RoutePath.kScreenMirror) return;
    mirrorOpening = true;
    unawaited(() async {
      try {
        final context = await appNavigatorReady();
        if (context == null || !context.mounted || !share.receiving) return;
        await AppNavigator.toNamed<void>(RoutePath.kScreenMirror);
      } on Object {
        if (share.receiving) await share.stop();
      } finally {
        mirrorOpening = false;
        if (share.receiving) unawaited(share.stop());
      }
    }());
  }

  share.addListener(screenChanged);
  ScreenCapture.onStopped(() => unawaited(share.stop()));
  share.suspendPlayback = services.remoteControl.suspendForMirror;
  services.remoteControl.screenState = () => share.snapshot;
  services.remoteControl.onScreen = (action, data, owner, authorized) =>
      share.signal(action, data, owner: owner, authorized: authorized);
  services.remoteControl.onRevokeScreen = () => share.stop(revoke: true);
  services.remoteControl.onSessionRevoked = share.revokeOwner;
  services.remoteControl.inputBlocked = () => share.consenting;
  services.remoteControl.applicationOnly = () => share.receiving;

  final application = ApplicationRemote(
    revision: () => liveRouteObserver.revision,
    focusRoot: () => AppNavigator.router.routerDelegate.navigatorKey.currentState?.focusNode,
    back: () async {
      if (share.receiving) {
        await share.stop();
        return true;
      }
      return await AppNavigator.mouseBack();
    },
    home: () async {
      // Navigate immediately; asynchronous capture cleanup cannot send a
      // later Home over a page the local user opened in the meantime.
      AppNavigator.offAllNamed(RoutePath.kInitial);
      await share.stop();
    },
    available: () {
      final state = WidgetsBinding.instance.lifecycleState;
      if (share.receiving && liveRouteObserver.topPage.value?.name != RoutePath.kScreenMirror) return false;
      return AppNavigator.navigatorContext?.mounted == true &&
          (state == null ||
              state == AppLifecycleState.resumed ||
              (state == AppLifecycleState.inactive && NativeRemoteInput.inputId != null));
    },
  );
  services.remoteControl.applicationTarget = application.target;
  services.remoteControl.scopeRevision = () => liveRouteObserver.revision + application.focusRevision + share.revision;
  services.remoteControl.onText = application.insertText;
  services.remoteControl.onDisposeApplication = () {
    share.removeListener(screenChanged);
    ScreenCapture.onStopped(null);
    application.dispose();
  };

  services.remoteControl.onLink = (text, authorized) async {
    if (!authorized()) return false;
    final link = await LinkParser(services.sites, services.http).parse(text);
    if (link == null || !authorized()) return false;
    final context = await appNavigatorReady();
    if (context == null || !context.mounted || !authorized()) return false;
    final room = LiveRoom(platform: link.platform, roomId: link.roomId);
    final follows = await services.store.follows.all();
    if (!authorized()) return false;
    final args = LiveRoomArgs(
      room: room,
      playlist: [room, ...follows.where((other) => other.identityKey != room.identityKey)],
    );
    final open = liveRouteObserver.topPage.value?.name == RoutePath.kLivePlay
        ? AppNavigator.offAndToNamed<void>(RoutePath.kLivePlay, arguments: args)
        : AppNavigator.toNamed<void>(RoutePath.kLivePlay, arguments: args);
    unawaited(open);
    return true;
  };
}
