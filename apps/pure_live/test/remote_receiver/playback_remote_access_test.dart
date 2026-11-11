import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/shared/net/mdns_peers.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';
import 'package:pure_live/shared/remote/remote_access.dart';
import 'package:pure_live/shared/remote/remote_client.dart';

void main() {
  tearDown(() => SystemAccess.debugCall = null);

  test('denied LAN access never opens a receiver or creates a pairing code', () async {
    final requests = <String>[];
    SystemAccess.debugCall = (method) async {
      requests.add(method);
      return false;
    };
    final receiver = PlaybackRemote();
    try {
      await expectLater(
        receiver.start(bind: InternetAddress.loopbackIPv4, discovery: false),
        throwsA(isA<RemoteControlAccessDenied>()),
      );
      expect(requests, ['requestLocalNetwork']);
      expect(receiver.running, isFalse);
      expect(receiver.port, 0);
      expect(receiver.code, isEmpty);
    } finally {
      await receiver.stop();
      receiver.dispose();
    }
  });

  test('denied pairing never issues a session on an already running receiver', () async {
    SystemAccess.debugCall = (_) async => true;
    final receiver = PlaybackRemote();
    await receiver.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final client = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${receiver.port}/'));
    SystemAccess.debugCall = (_) async => false;
    try {
      await expectLater(client.pair(receiver.code), throwsA(isA<RemoteControlAccessDenied>()));
      expect(receiver.pairedCount, 0);
      expect(client.paired, isFalse);
    } finally {
      client.close();
      await receiver.stop();
      receiver.dispose();
    }
  });

  test('denied discovery stops before native mDNS or UDP broadcast', () async {
    SystemAccess.debugCall = (_) async => false;
    final mdns = _NoNetworkMdns();
    await expectLater(discoverPlaybackRemotes(mdns: mdns), throwsA(isA<RemoteControlAccessDenied>()));
    expect(mdns.starts, 0);
  });

  test('stopping during a permission prompt cannot start a receiver after late approval', () async {
    final requested = Completer<void>();
    final permission = Completer<bool>();
    SystemAccess.debugCall = (_) {
      requested.complete();
      return permission.future;
    };
    final receiver = PlaybackRemote();
    final starting = receiver.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    await requested.future;
    expect(receiver.running, isFalse);
    await receiver.stop();
    permission.complete(true);
    await starting;
    expect(receiver.running, isFalse);
    expect(receiver.code, isEmpty);
    receiver.dispose();
  });

  test('explicit approval after refusal permits a fresh start and normal pairing', () async {
    final receiver = PlaybackRemote();
    PlaybackRemoteClient? client;
    try {
      SystemAccess.debugCall = (_) async => false;
      await expectLater(
        receiver.start(bind: InternetAddress.loopbackIPv4, discovery: false),
        throwsA(isA<RemoteControlAccessDenied>()),
      );
      SystemAccess.debugCall = (_) async => true;
      await receiver.start(bind: InternetAddress.loopbackIPv4, discovery: false);
      expect(receiver.running, isTrue);
      client = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${receiver.port}/'));
      await client.pair(receiver.code);
      expect(client.paired, isTrue);
      expect(receiver.pairedCount, 1);
    } finally {
      client?.close();
      await receiver.stop();
      receiver.dispose();
    }
  });
}

/// Any unguarded start fails before touching a real multicast transport.
final class _NoNetworkMdns implements MdnsPeers {
  int starts = 0;
  @override
  Future<void> start({
    required String name,
    required int port,
    required Map<String, String> attributes,
    required void Function(MdnsPeer peer) found,
    required void Function(String id) lost,
  }) async {
    starts++;
    throw StateError('discovery ran before its permission check');
  }

  @override
  Future<void> stop() async {}
}
