import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/desktop/projection_channel.dart';
import 'package:pure_live/app/launch_args.dart';

void main() {
  test('one receiver is reused, public room fields survive, close reaches only its owner', () async {
    final root = Directory.systemTemp.createTempSync('purelive-projection-');
    final selections = <ProjectionSelection>[];
    var starts = 0;
    var closes = 0;
    ProjectionReceiver? receiver;
    final channel = ProjectionChannel(
      root,
      launch: (args) async {
        starts++;
        final launch = LaunchArgs.parse(args);
        expect(launch.projection, isTrue);
        expect(launch.room, isNull);
        receiver = await ProjectionReceiver.start(
          file: File(p.join(root.path, 'instances', launch.instanceId, 'projection.json')),
          onOpen: (selection) async => selections.add(selection),
          onClose: () async => closes++,
        );
      },
    );
    try {
      await channel.select(
        ProjectionSelection(
          LiveRoom(platform: 'douyu', roomId: '1'),
          display: 'display-a',
        ),
      );
      await channel.select(ProjectionSelection(LiveRoom(platform: 'douyu', roomId: '2')));
      expect(starts, 1);
      expect(selections.map((selection) => selection.room.roomId), ['1', '2']);
      expect(selections.map((selection) => selection.display), ['display-a', '']);
      await channel.close();
      expect(closes, 1);
      await channel.select(ProjectionSelection(LiveRoom(platform: 'douyu', roomId: '3')));
      expect(selections.length, 2);
    } finally {
      await channel.close();
      await receiver?.dispose();
      root.deleteSync(recursive: true);
    }
  });

  test('no bearer, foreign origin, malformed and oversized messages cannot navigate', () async {
    final root = Directory.systemTemp.createTempSync('purelive-projection-auth-');
    final file = File(p.join(root.path, 'receiver.json'));
    var opened = 0;
    final receiver = await ProjectionReceiver.start(file: file, onOpen: (_) async => opened++, onClose: () async {});
    final data = jsonDecode(file.readAsStringSync()) as Map;
    final client = HttpClient();
    Future<int> send({bool auth = true, bool origin = false, String body = '{}'}) async {
      final request = await client.postUrl(Uri.parse('http://127.0.0.1:${data['port']}/room'));
      if (auth) request.headers.set('authorization', 'Bearer ${data['token']}');
      if (origin) request.headers.set('origin', 'https://invalid.example');
      request.write(body);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    try {
      expect(await send(auth: false), HttpStatus.forbidden);
      expect(await send(origin: true), HttpStatus.forbidden);
      expect(await send(), HttpStatus.badRequest);
      expect(await send(body: 'x' * 16385), HttpStatus.badRequest);
      expect(opened, 0);
    } finally {
      client.close(force: true);
      await receiver.dispose();
      expect(file.existsSync(), isFalse);
      root.deleteSync(recursive: true);
    }
  });

  test('rapid taps collapse pending rooms while preserving the latest choice', () async {
    final root = Directory.systemTemp.createTempSync('purelive-projection-latest-');
    final first = Completer<void>();
    final entered = Completer<void>();
    final rooms = <String>[];
    ProjectionReceiver? receiver;
    final channel = ProjectionChannel(
      root,
      launch: (args) async {
        receiver = await ProjectionReceiver.start(
          file: File(p.join(root.path, 'instances', LaunchArgs.parse(args).instanceId, 'projection.json')),
          onOpen: (selection) async {
            rooms.add(selection.room.roomId);
            if (rooms.length == 1) {
              entered.complete();
              await first.future;
            }
          },
          onClose: () async {},
        );
      },
    );
    try {
      final initial = channel.select(ProjectionSelection(LiveRoom(platform: 'douyu', roomId: '1')));
      await entered.future;
      final second = channel.select(ProjectionSelection(LiveRoom(platform: 'douyu', roomId: '2')));
      final last = channel.select(ProjectionSelection(LiveRoom(platform: 'douyu', roomId: '3')));
      first.complete();
      await Future.wait([initial, second, last]);
      expect(rooms, ['1', '3']);
    } finally {
      await channel.close();
      await receiver?.dispose();
      root.deleteSync(recursive: true);
    }
  });
}
