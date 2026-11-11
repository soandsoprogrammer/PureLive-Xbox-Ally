import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/tv/gamepad_actions.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';

void main() {
  testWidgets('a deferred offscreen request cannot steal later user focus', (tester) async {
    final grid = GlobalKey<TvGridState>();
    final outside = FocusNode(debugLabel: 'outside grid');
    addTearDown(outside.dispose);
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        home: TvTheme(
          palette: TvPalette.of(scheme),
          child: Scaffold(
            body: Column(
              children: [
                TvButton(label: '外部按钮', focusNode: outside, onTap: () {}),
                Expanded(
                  child: TvGrid(
                    key: grid,
                    itemCount: 100,
                    columns: 4,
                    aspectRatio: 2,
                    itemBuilder: (context, index, node, onKey) => TvFocusable(
                      key: ValueKey('pending-$index'),
                      focusNode: node,
                      onKey: onKey,
                      onTap: () {},
                      builder: (_, focused) => Text('卡片$index'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    grid.currentState!.focusIndex(0);
    await tester.pump(const Duration(seconds: 1));
    grid.currentState!.focusIndex(99);
    outside.requestFocus();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(outside.hasFocus, isTrue, reason: 'an old post-frame target no longer owns input after the user leaves');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an explicit return target overrides old grid focus memory', (tester) async {
    final grid = GlobalKey<TvGridState>();
    final outside = FocusNode(debugLabel: 'outside grid');
    addTearDown(outside.dispose);
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        home: TvTheme(
          palette: TvPalette.of(scheme),
          child: Scaffold(
            body: Column(
              children: [
                TvButton(label: '外部按钮', focusNode: outside, onTap: () {}),
                Expanded(
                  child: TvGrid(
                    key: grid,
                    itemCount: 8,
                    columns: 4,
                    aspectRatio: 2,
                    itemBuilder: (context, index, node, onKey) => TvFocusable(
                      key: ValueKey('restore-$index'),
                      focusNode: node,
                      onKey: onKey,
                      onTap: () {},
                      builder: (_, focused) => Text('卡片$index'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    grid.currentState!.focusIndex(0);
    await tester.pump(const Duration(seconds: 1));
    outside.requestFocus();
    await tester.pump(const Duration(seconds: 1));
    grid.currentState!.focusIndex(5);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<TvFocusable>(find.byKey(const ValueKey('restore-5'))).focusNode!.hasFocus,
      isTrue,
      reason: 'returning after a channel switch must focus the shown room, not the old remembered room',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('native gamepad actions navigate, restore a reflowed room and activate it', (tester) async {
    const channel = MethodChannel('pure_live/gamepad');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => null);
    GamepadActions.install();
    addTearDown(GamepadActions.uninstall);
    final grid = GlobalKey<TvGridState>();
    String? selected;
    Future<void> send(String action) async {
      final reply = Completer<void>();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'pure_live/gamepad',
        const StandardMethodCodec().encodeMethodCall(MethodCall('action', action)),
        (_) => reply.complete(),
      );
      await reply.future;
      await tester.pumpAndSettle();
    }

    Widget layout(List<String> rooms, int columns) => MaterialApp(
      home: Scaffold(
        body: TvGrid(
          key: grid,
          itemCount: rooms.length,
          columns: columns,
          aspectRatio: 2,
          itemIdentity: (index) => rooms[index],
          itemBuilder: (context, index, node, onKey) => TvFocusable(
            key: ValueKey(rooms[index]),
            focusNode: node,
            onKey: onKey,
            onTap: () => selected = rooms[index],
            builder: (_, focused) => Text(rooms[index]),
          ),
        ),
      ),
    );

    await tester.pumpWidget(layout(['a', 'b', 'c', 'd'], 3));
    grid.currentState!.focusIndex(0);
    await tester.pumpAndSettle();
    await send('right');
    expect(grid.currentState!.lastFocused, 1);
    await tester.pumpWidget(layout(['a', 'c', 'b', 'd'], 2));
    await tester.pumpAndSettle();
    await send('confirm');
    expect(selected, 'b');
  });
}
