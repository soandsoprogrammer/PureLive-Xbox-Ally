import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:pure_live/shared/remote/screen_share.dart';

const _offer = {'type': 'offer', 'sdp': 'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'};

class _Track extends Fake implements MediaStreamTrack {
  bool stopped = false;
  @override
  String get kind => 'video';
  @override
  void Function()? onEnded;
  @override
  Future<void> stop() async => stopped = true;
}

class _Stream extends Fake implements MediaStream {
  final _Track track = _Track();
  bool disposed = false;
  @override
  List<MediaStreamTrack> getVideoTracks() => [track];
  @override
  List<MediaStreamTrack> getTracks() => [track];
  @override
  Future<void> dispose() async => disposed = true;
}

class _Channel extends Fake implements RTCDataChannel {
  @override
  void Function(RTCDataChannelMessage)? onMessage;
  @override
  RTCDataChannelState get state => RTCDataChannelState.RTCDataChannelOpen;
  @override
  Future<void> send(RTCDataChannelMessage message) async {}
}

class _Sender extends Fake implements RTCRtpSender;

class _Peer extends Fake implements RTCPeerConnection {
  bool closed = false;
  bool disposed = false;
  RTCSessionDescription? local;
  final _Stream incoming = _Stream();
  @override
  void Function(RTCPeerConnectionState)? onConnectionState;
  @override
  void Function(RTCIceGatheringState)? onIceGatheringState;
  @override
  void Function(RTCDataChannel)? onDataChannel;
  @override
  void Function(RTCTrackEvent)? onTrack;
  @override
  Future<RTCRtpSender> addTrack(MediaStreamTrack track, [MediaStream? stream]) async => _Sender();
  @override
  Future<RTCDataChannel> createDataChannel(String label, RTCDataChannelInit configuration) async => _Channel();
  @override
  Future<RTCSessionDescription> createOffer([Map<String, dynamic>? constraints]) async =>
      RTCSessionDescription(_offer['sdp'], 'offer');
  @override
  Future<RTCSessionDescription> createAnswer([Map<String, dynamic>? constraints]) async =>
      RTCSessionDescription(_offer['sdp'], 'answer');
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async => local = description;
  @override
  Future<RTCSessionDescription?> getLocalDescription() async => local;
  @override
  Future<RTCIceGatheringState?> getIceGatheringState() async => RTCIceGatheringState.RTCIceGatheringStateComplete;
  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (description.type == 'offer') onTrack?.call(RTCTrackEvent(streams: [incoming], track: incoming.track));
  }

  @override
  Future<void> close() async => closed = true;
  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  test('replacement mirror waits for old cleanup and room restoration', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final order = <String>[];
    var cleanups = 0;
    var suspensions = 0;
    final share =
        ScreenShare(
            capture: () async => _Stream(),
            endCapture: () async {
              if (++cleanups == 1) {
                entered.complete();
                await release.future;
              }
            },
            peer: () async => _Peer(),
          )
          ..suspendPlayback = () async {
            final id = ++suspensions;
            order.add('pause$id');
            return () async => order.add('restore$id');
          };
    await share.allowReceive(enabled: true);
    await share.signal('push', _offer, owner: 'a', authorized: () => true);
    final stopping = share.stop();
    await entered.future;
    final replacement = share.signal('push', _offer, owner: 'b', authorized: () => true);
    final whileCleaning = suspensions;
    release.complete();
    await stopping;
    await replacement;
    expect(whileCleaning, 1, reason: 'old restoration must finish before a new pause');
    expect(order, ['pause1', 'restore1', 'pause2']);
    expect(share.receiving, isTrue);
    await share.close();
  });

  test('latest local receiving choice wins while disabling waits for teardown', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var cleanups = 0;
    final share = ScreenShare(
      capture: () async => _Stream(),
      endCapture: () async {
        if (++cleanups == 1) {
          entered.complete();
          await release.future;
        }
      },
      peer: () async => _Peer(),
    );
    await share.allowReceive(enabled: true);
    await share.signal('push', _offer, owner: 'a', authorized: () => true);
    final disabling = share.allowReceive(enabled: false);
    await entered.future;
    await share.allowReceive(enabled: true);
    release.complete();
    await disabling;
    expect(share.receiveAllowed, isTrue);
    await share.close();
  });

  test('queued end from an old local track cannot stop a fresh capture', () async {
    final streams = [_Stream(), _Stream()];
    var next = 0;
    final share = ScreenShare(capture: () async => streams[next++], endCapture: () async {});
    await share.startCapture();
    final oldEnded = streams.first.track.onEnded!;
    await share.stop();
    await share.startCapture();
    oldEnded();
    final stillCapturing = share.capturing;
    await share.close();
    expect(stillCapturing, isTrue);
  });

  test('queued end from an old incoming track cannot stop a replacement mirror', () async {
    final peers = [_Peer(), _Peer()];
    var next = 0;
    final share = ScreenShare(capture: () async => _Stream(), endCapture: () async {}, peer: () async => peers[next++]);
    await share.allowReceive(enabled: true);
    await share.signal('push', _offer, owner: 'a', authorized: () => true);
    final oldEnded = peers.first.incoming.track.onEnded!;
    await share.stop();
    await share.signal('push', _offer, owner: 'b', authorized: () => true);
    oldEnded();
    final stillReceiving = share.receiving;
    await share.close();
    expect(stillReceiving, isTrue);
  });

  test('network requests cannot start local capture or arm incoming mirrors', () async {
    var captures = 0;
    final share = ScreenShare(
      capture: () async {
        captures++;
        return _Stream();
      },
      endCapture: () async {},
    );
    await expectLater(share.signal('view', {}, owner: 'a', authorized: () => true), throwsStateError);
    await expectLater(share.signal('push', _offer, owner: 'a', authorized: () => true), throwsStateError);
    expect(captures, 0);
    expect(share.capturing, isFalse);
    expect(share.receiving, isFalse);
    await share.close();
  });

  test('a second paired controller cannot answer or stop another owner', () async {
    final stream = _Stream();
    final peer = _Peer();
    final share = ScreenShare(capture: () async => stream, endCapture: () async {}, peer: () async => peer);
    await share.startCapture();
    final offer = await share.signal('view', {}, owner: 'a', authorized: () => true);
    final answer = {...offer, 'type': 'answer'};
    await expectLater(share.signal('answer', answer, owner: 'b', authorized: () => true), throwsStateError);
    await expectLater(share.signal('stop', {'id': offer['id']}, owner: 'b', authorized: () => true), throwsStateError);
    await share.signal('answer', answer, owner: 'a', authorized: () => true);
    await share.revokeOwner('a');
    expect(stream.track.stopped, isTrue);
    expect(stream.disposed, isTrue);
    expect(peer.closed && peer.disposed, isTrue);
    expect(share.capturing, isFalse);
    await share.close();
  });

  test('capture completing after cancel is released before any peer can see it', () async {
    final capture = Completer<MediaStream>();
    final entered = Completer<void>();
    final stream = _Stream();
    var peers = 0;
    final share = ScreenShare(
      capture: () {
        entered.complete();
        return capture.future;
      },
      endCapture: () async {},
      peer: () async {
        peers++;
        return _Peer();
      },
    );
    final pending = share.startCapture();
    await entered.future;
    await share.stop();
    capture.complete(stream);
    await pending;
    expect(stream.track.stopped && stream.disposed, isTrue);
    expect(share.capturing, isFalse);
    expect(peers, 0);
    await share.close();
  });

  test('incoming mirror releases its stream and restores the original room once', () async {
    final peer = _Peer();
    var restored = 0;
    final share = ScreenShare(capture: () async => _Stream(), endCapture: () async {}, peer: () async => peer)
      ..suspendPlayback = () async => () async {
        restored++;
      };
    await share.allowReceive(enabled: true);
    await share.signal('push', _offer, owner: 'a', authorized: () => true);
    expect(share.receiving, isTrue);
    expect(share.incoming, peer.incoming);
    await share.stop();
    await share.stop();
    expect(restored, 1);
    expect(peer.incoming.track.stopped, isTrue);
    expect(share.receiving, isFalse);
    await share.close();
  });

  test('late peer allocation after revocation cannot resurrect a closed capture', () async {
    final allocation = Completer<RTCPeerConnection>();
    final entered = Completer<void>();
    final stream = _Stream();
    final peer = _Peer();
    final share = ScreenShare(
      capture: () async => stream,
      endCapture: () async {},
      peer: () {
        entered.complete();
        return allocation.future;
      },
    );
    await share.startCapture();
    final pending = share.signal('view', {}, owner: 'a', authorized: () => true);
    final rejected = expectLater(pending, throwsStateError);
    await entered.future;
    await share.stop(revoke: true);
    allocation.complete(peer);
    await rejected;
    expect(peer.closed && peer.disposed, isTrue);
    expect(stream.track.stopped, isTrue);
    expect(share.connected, isFalse);
    await share.close();
  });

  test('platform cleanup failure does not skip original-room restoration', () async {
    var restored = 0;
    final share =
        ScreenShare(
            capture: () async => _Stream(),
            endCapture: () async {
              throw StateError('service gone');
            },
            peer: () async => _Peer(),
          )
          ..suspendPlayback = () async => () async {
            restored++;
          };
    await share.allowReceive(enabled: true);
    await share.signal('push', _offer, owner: 'a', authorized: () => true);
    await share.stop();
    expect(restored, 1);
    expect(share.receiving, isFalse);
    await share.close();
  });

  testWidgets('pair expiry closes a live media peer without another HTTP command', (tester) async {
    var authorized = true;
    final stream = _Stream();
    final peer = _Peer();
    final share = ScreenShare(capture: () async => stream, endCapture: () async {}, peer: () async => peer);
    await share.startCapture();
    await share.signal('view', {}, owner: 'a', authorized: () => authorized);
    authorized = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(peer.closed, isTrue);
    expect(stream.track.stopped, isTrue);
    expect(share.capturing, isFalse);
    await share.close();
  });

  testWidgets('a hung pause times out, and its later lease is still released', (tester) async {
    final suspension = Completer<ScreenResume>();
    var restored = 0;
    final share = ScreenShare(capture: () async => _Stream(), endCapture: () async {}, peer: () async => _Peer())
      ..suspendPlayback = () => suspension.future;
    await share.allowReceive(enabled: true);
    final pending = share.signal('push', _offer, owner: 'a', authorized: () => true);
    final rejected = expectLater(pending, throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 6));
    await rejected;
    expect(share.receiving, isFalse);
    suspension.complete(() async {
      restored++;
    });
    await tester.pump();
    expect(restored, 1);
    await share.close();
  });
}
