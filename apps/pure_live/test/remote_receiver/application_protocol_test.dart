import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';
import 'package:pure_live/shared/remote/remote_client.dart';

void main() {
  test('app navigation and text work outside playback; route/focus changes reject queued input', () async {
    var revision = 1;
    var blocked = false;
    final events = <String>[];
    final remote = PlaybackRemote()
      ..scopeRevision = (() => revision)
      ..inputBlocked = (() => blocked)
      ..applicationTarget = RemotePlaybackTarget(
        available: () => true,
        snapshot: () => {
          'commands': ['ok', 'home'],
          'inputId': 7,
          'secretInput': true,
        },
        execute: (command, _) async {
          events.add(command);
          return true;
        },
      )
      ..onText = (text, inputId) async {
        if (inputId != 7) return false;
        events.add('text:$text');
        return true;
      }
      ..onLink = (_, _) async {
        events.add('link');
        return true;
      };
    await remote.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final client = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${remote.port}/'));
    try {
      await client.pair(remote.code);
      final initial = await client.status();
      final target = initial['targetId']! as String;
      expect((initial['state'] as Map)['secretInput'], isTrue);
      await client.command(target, 'ok');
      await client.insertText(target, 7, 'replacement');
      revision++;
      await expectLater(client.command(target, 'home'), throwsA(isA<HttpException>()));
      await expectLater(client.insertText(target, 7, 'late'), throwsA(isA<HttpException>()));
      final fresh = (await client.status())['targetId']! as String;
      await expectLater(client.insertText(fresh, 6, 'wrong field'), throwsA(isA<HttpException>()));
      blocked = true;
      expect((await client.status())['targetId'], isNull);
      await expectLater(client.command(fresh, 'home'), throwsA(isA<HttpException>()));
      await expectLater(client.sendLink('https://www.douyu.com/1'), throwsA(isA<HttpException>()));
      expect(events, ['ok', 'text:replacement']);
    } finally {
      client.close();
      await remote.stop();
      remote.dispose();
    }
  });

  test('a visible player keeps playback commands and delegates missing navigation to the app', () async {
    final events = <String>[];
    final remote = PlaybackRemote()
      ..applicationTarget = RemotePlaybackTarget(
        available: () => true,
        snapshot: () => {
          'commands': ['home'],
        },
        execute: (command, _) async {
          events.add('app:$command');
          return true;
        },
      );
    final player = RemotePlaybackTarget(
      available: () => true,
      snapshot: () => {
        'commands': ['pause'],
      },
      execute: (command, _) async {
        events.add('player:$command');
        return true;
      },
    );
    remote.register(player);
    await remote.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final client = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${remote.port}/'));
    try {
      await client.pair(remote.code);
      final target = (await client.status())['targetId']! as String;
      await client.command(target, 'home');
      await client.command(target, 'pause');
      expect(events, ['app:home', 'player:pause']);
      remote.applicationOnly = () => true;
      await expectLater(client.command(target, 'pause'), throwsA(isA<HttpException>()));
    } finally {
      client.close();
      await remote.stop();
      remote.dispose();
    }
  });

  test('screen signaling is revoked while awaiting a peer and one unpair releases only its owner', () async {
    final entered = Completer<void>();
    final finish = Completer<void>();
    final released = <String>[];
    var negotiatedAfterRevocation = false;
    final remote = PlaybackRemote()
      ..screenState = (() => {'capturing': true, 'receiveAllowed': false})
      ..onSessionRevoked = ((owner) async => released.add(owner))
      ..onScreen = (action, data, owner, authorized) async {
        expect(action, 'view');
        entered.complete();
        await finish.future;
        negotiatedAfterRevocation = authorized();
        return {'session': 'test-only', 'sdp': 'not an actual peer'};
      };
    await remote.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final a = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${remote.port}/'));
    final b = PlaybackRemoteClient(a.uri);
    try {
      await a.pair(remote.code);
      await b.pair(remote.code);
      expect((await b.status())['screen'], {'capturing': true, 'receiveAllowed': false});
      final pending = a.screen('view', {});
      await entered.future;
      await a.disconnect();
      expect(released, hasLength(1));
      expect(remote.pairedCount, 1);
      finish.complete();
      await expectLater(pending, throwsA(isA<HttpException>()));
      expect(negotiatedAfterRevocation, isFalse);
      expect((await b.status())['screen'], isNotNull);
    } finally {
      if (!finish.isCompleted) finish.complete();
      a.close();
      b.close();
      await remote.stop();
      remote.dispose();
    }
  });

  test('mirror restoration keeps the exact registered room identity across a covering route', () async {
    final remote = PlaybackRemote();
    var room = 'first';
    var visible = true;
    bool Function()? stillOwned;
    final player = RemotePlaybackTarget(
      identity: () => room,
      available: () => visible,
      snapshot: () => {},
      execute: (_, _) async => true,
      suspend: (valid) async {
        stillOwned = valid;
        return () async {};
      },
    );
    remote.register(player);
    await remote.suspendForMirror();
    visible = false;
    expect(stillOwned!(), isTrue, reason: 'the mirror covers rather than unregisters the original room');
    room = 'second';
    expect(stillOwned!(), isFalse, reason: 'a new room cannot be resumed by an old mirror lease');
    room = 'first';
    remote.unregister(player);
    expect(stillOwned!(), isFalse);
    remote.dispose();
  });
}
