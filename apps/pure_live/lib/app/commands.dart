import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The app's keyboard commands, one table for the Mac's menu bar and the
/// iPad's keyboard (docs/A-界面设计/A18-苹果平台界面: A18.2 c4–c5, A18.1 c10):
/// ⌘, settings, ⌘F search, ⌘L the link parser, ⌘Y the watch history,
/// ⌘1–⌘4 follows, popular, areas and the recording centre, ⌘[ back. The
/// room's own commands are [RoomCommands]; v3's single keys stay where they
/// were (the room's space, R, arrows and Esc).
enum AppCommand {
  /// ⌘, the settings.
  settings(LogicalKeyboardKey.comma),

  /// ⌘F search.
  search(LogicalKeyboardKey.keyF),

  /// ⌘L the link parser.
  openLink(LogicalKeyboardKey.keyL),

  /// ⌘Y the watch history.
  history(LogicalKeyboardKey.keyY),

  /// ⌘1 the follows.
  favorites(LogicalKeyboardKey.digit1),

  /// ⌘2 popular.
  popular(LogicalKeyboardKey.digit2),

  /// ⌘3 the areas.
  areas(LogicalKeyboardKey.digit3),

  /// ⌘4 the recording centre.
  record(LogicalKeyboardKey.digit4),

  /// ⌘[ back.
  back(LogicalKeyboardKey.bracketLeft);

  new(this.key);

  /// The key pressed with ⌘.
  final LogicalKeyboardKey key;

  /// ⌘ and [key].
  SingleActivator get activator => SingleActivator(key, meta: true);

  /// The home destination this command shows, if any.
  HomeMenu? get homeMenu => switch (this) {
    favorites => HomeMenu.favorites,
    popular => HomeMenu.popular,
    areas => HomeMenu.areas,
    record => HomeMenu.record,
    _ => null,
  };

  /// Does it (pages open without waiting for them to close). A home
  /// destination goes back to the home page first.
  void run() {
    if (homeMenu case final menu?) {
      AppNavigator.router.go(RoutePath.kInitial);
      // After the home page is back and listening.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HomeSignals.select.value = (menu, (HomeSignals.select.value?.$2 ?? 0) + 1);
      });
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    switch (this) {
      case settings:
        unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings));
      case search:
        unawaited(AppNavigator.toNamed<void>(RoutePath.kSearch));
      case openLink:
        unawaited(AppNavigator.toNamed<void>(RoutePath.kToolbox));
      case history:
        unawaited(AppNavigator.toNamed<void>(RoutePath.kHistory));
      case back:
        // The page's own back first (a room leaves its full screen, a panel
        // closes), as the system's back does.
        final context = AppNavigator.navigatorContext;
        if (context != null) Navigator.maybePop(context);
      case favorites || popular || areas || record:
        break;
    }
  }
}

/// What the open live room offers the Mac's "播放" menu (A18.2 c4); the room
/// page puts its own here while it is on top, so the menu is greyed
/// elsewhere.
abstract interface class RoomCommands {
  /// Pauses or plays (space).
  Future<void> togglePlay();

  /// Loads the room again (⌘R; v3's R).
  Future<void> refresh();

  /// Into or out of the room's full screen (v3's F).
  void toggleFullScreen();

  /// Into or out of the full screen inside the window (desktops).
  void toggleWindowFullScreen();

  /// Flying danmaku on or off.
  Future<void> toggleDanmaku();

  /// The danmaku settings panel.
  void danmakuSettings();

  /// Sound only, or the picture back.
  Future<void> toggleAudioOnly();

  /// The volume panel.
  void volume();

  /// The recording panel.
  void record();

  /// The room on top, or null.
  static final ValueNotifier<RoomCommands?> current = ValueNotifier(null);
}

/// ⌘R, the room's refresh.
const SingleActivator refreshActivator = SingleActivator(LogicalKeyboardKey.keyR, meta: true);

/// The [AppCommand]s as keyboard shortcuts over [child] on an iPad (A18.1
/// c10); elsewhere [child] alone (the Mac has them in its menu bar). The
/// iPad also gets them as the system's key commands ([IosKeyCommands]):
/// holding ⌘ lists them, and the system runs them (the shortcuts here then
/// stand aside, so a key does not run twice).
class AppCommandShortcuts extends StatefulWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  State<AppCommandShortcuts> createState() => _AppCommandShortcutsState();
}

class _AppCommandShortcutsState extends State<AppCommandShortcuts> {
  @override
  void initState() {
    super.initState();
    IosKeyCommands.active.addListener(_changed);
  }

  @override
  void dispose() {
    IosKeyCommands.active.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return widget.child;
    // The titles follow the language: sent again on every build (only when
    // they changed).
    IosKeyCommands.sync();
    if (IosKeyCommands.active.value) return widget.child;
    return CallbackShortcuts(
      bindings: {
        for (final command in AppCommand.values) command.activator: command.run,
        refreshActivator: () => unawaited(RoomCommands.current.value?.refresh()),
      },
      child: widget.child,
    );
  }
}

/// The iPad's key commands (A18.1 c10, native `pure_live/key_commands` in
/// `AppDelegate.swift`): the [AppCommand] table with the words of the Mac's
/// menu, in groups, plus the room's ⌘R, given to the system as
/// `UIKeyCommand`s so holding ⌘ lists them; the system runs them back here
/// (`run` with the command's name). ⌘R is offered only while a room is on
/// top (`room`).
abstract final class IosKeyCommands {
  static const MethodChannel _channel = MethodChannel('pure_live/key_commands');

  /// Whether the system took the commands (the Dart shortcuts stand aside).
  static final ValueNotifier<bool> active = ValueNotifier(false);

  static String? _sent;
  static bool _listening = false;

  /// The id of the room's refresh in the table.
  static const String refreshId = 'refresh';

  /// The table: groups of commands with their words and keys.
  @visibleForTesting
  static Map<String, Object> table() => {
    'title': i18n('app_name'),
    'commands': [
      for (final (group, entries) in [
        (
          'go',
          [
            (AppCommand.search, 'menu_search'),
            (AppCommand.openLink, 'menu_open_link'),
            (AppCommand.settings, 'menu_settings'),
          ],
        ),
        (
          'pages',
          [
            (AppCommand.favorites, 'favorites_title'),
            (AppCommand.popular, 'popular_title'),
            (AppCommand.areas, 'areas_title'),
            (AppCommand.record, 'record_center'),
            (AppCommand.history, 'watch_history'),
          ],
        ),
        ('back', [(AppCommand.back, 'menu_back')]),
      ])
        for (final (command, key) in entries)
          {'id': command.name, 'title': i18n(key), 'input': _input(command.key), 'group': group},
      {'id': refreshId, 'title': i18n('refresh'), 'input': 'r', 'group': 'room'},
    ],
  };

  static String _input(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.comma => ',',
    LogicalKeyboardKey.bracketLeft => '[',
    LogicalKeyboardKey.digit1 => '1',
    LogicalKeyboardKey.digit2 => '2',
    LogicalKeyboardKey.digit3 => '3',
    LogicalKeyboardKey.digit4 => '4',
    _ => key.keyLabel.toLowerCase(),
  };

  /// Gives the system the table (again when its words changed) and listens
  /// for the commands it runs; iOS only.
  static void sync() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'run') run(call.arguments as String?);
      });
      RoomCommands.current.addListener(_room);
    }
    final table = IosKeyCommands.table();
    final text = table.toString();
    if (text == _sent) return;
    _sent = text;
    unawaited(_send(table));
  }

  static Future<void> _send(Map<String, Object> table) async {
    try {
      final taken = await _channel.invokeMethod<bool>('set', table) ?? false;
      if (taken) {
        active.value = true;
        await _room();
      }
    } on PlatformException {
      // An older system: the Dart shortcuts stay.
    } on MissingPluginException {
      // No native side (tests).
    }
  }

  static Future<void> _room() async {
    if (!active.value) return;
    try {
      await _channel.invokeMethod<void>('room', RoomCommands.current.value != null);
    } on PlatformException {
      // Ignored: ⌘R stays offered.
    } on MissingPluginException {
      // No native side.
    }
  }

  /// Forgets what was sent and stops listening (tests).
  @visibleForTesting
  static void debugReset() {
    if (_listening) RoomCommands.current.removeListener(_room);
    _listening = false;
    _sent = null;
    active.value = false;
  }

  /// Runs the command the system sent ([AppCommand]'s name or [refreshId]).
  @visibleForTesting
  static void run(String? id) {
    if (id == refreshId) {
      unawaited(RoomCommands.current.value?.refresh());
      return;
    }
    for (final command in AppCommand.values) {
      if (command.name == id) command.run();
    }
  }
}
