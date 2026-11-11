import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// A local, authenticated signaling exchange; no public STUN or relay server.
typedef ScreenSignal = Future<Map<String, dynamic>> Function(String action, Map<String, Object?> data);

/// An original room's owned suspension, released after the mirror disappears.
typedef ScreenResume = Future<void> Function();

/// One explicitly authorized screen stream or incoming mirror per app instance.
/// Screen pixels never enter settings, application logs or a feedback upload.
final class ScreenShare extends ChangeNotifier {
  /// Capture and peer factories are replaceable for cancellation/ownership tests.
  new({
    required this.capture,
    required this.endCapture,
    Future<RTCPeerConnection> Function()? peer,
    DateTime Function()? now,
  }) : _makePeer =
           peer ??
           (() => createPeerConnection({'iceServers': <Map<String, Object?>>[], 'sdpSemantics': 'unified-plan'})),
       _now = now ?? DateTime.now;

  /// Runs only after a local button press and local system consent.
  final Future<MediaStream> Function() capture;

  /// Releases platform capture support, including Android's foreground service.
  final Future<void> Function() endCapture;

  final Future<RTCPeerConnection> Function() _makePeer;
  final DateTime Function() _now;
  MediaStream? _capture;
  MediaStream? _incoming;
  RTCPeerConnection? _peer;
  RTCDataChannel? _presence;
  Timer? _watchdog;
  late DateTime _lastSeen;
  late bool _seenPresence;
  Future<void>? _stopping;
  Future<void>? _startingCapture;
  ScreenResume? _resume;
  String? _owner;
  String? _session;
  bool Function()? _authorized;
  bool _receiveAllowed = false;
  bool _receiving = false;
  bool _consenting = false;
  bool _working = false;
  bool _disposed = false;
  Object? _outgoingOwner;
  int _epoch = 0;
  int _revision = 0;

  /// Optional room suspension before accepting an incoming mirror.
  Future<ScreenResume> Function()? suspendPlayback;

  /// Native sender keeps its paired client alive while the user returns to live.
  Future<void> Function()? closeOutgoingClient;

  /// The incoming visual stream, never a platform live-media URL.
  MediaStream? get incoming => _incoming;

  /// Capture remains a visible, locally stoppable system session.
  bool get capturing => _capture != null;

  /// True while requesting local permission/source selection.
  bool get consenting => _consenting;

  /// The mirror overlay owns focus while preparing and displaying video.
  bool get receiving => _receiving;

  /// Whether this receiver has locally enabled incoming mirrors.
  bool get receiveAllowed => _receiveAllowed;

  /// Whether a peer currently owns the single media slot.
  bool get connected => _peer != null;

  /// Changes on every overlay and capture state transition.
  int get revision => _revision;

  /// Local controller ownership survives leaving the settings page.
  Object? get outgoingOwner => _outgoingOwner;

  /// Public capabilities only; no SDP, addresses, credentials or screen data.
  Map<String, Object?> get snapshot => {
    'captureReady': capturing && !_working && _peer == null,
    'capturing': capturing,
    'receiving': receiving,
    'receiveAllowed': receiveAllowed,
    'busy': _working || _peer != null,
    'videoOnly': true,
  };

  void _changed() {
    if (_disposed) return;
    _revision++;
    notifyListeners();
  }

  /// A local-only receiving switch. Pairing by itself does not arm mirrors.
  Future<void> allowReceive({required bool enabled}) async {
    _receiveAllowed = enabled;
    _changed();
    if (!enabled && receiving) await stop();
  }

  /// Begins a new OS capture session from a local action, never from HTTP.
  Future<void> startCapture() => _startingCapture ??= _startCapture().whenComplete(() => _startingCapture = null);

  Future<void> _startCapture() async {
    await stop();
    if (_disposed) throw StateError('screen sharing closed');
    final epoch = ++_epoch;
    _consenting = true;
    _changed();
    MediaStream? stream;
    try {
      stream = await capture();
      if (epoch != _epoch || _disposed) {
        await _releaseStream(stream);
        await endCapture();
        return;
      }
      if (stream.getVideoTracks().isEmpty) throw StateError('screen video unavailable');
      _capture = stream;
      for (final track in stream.getVideoTracks()) {
        track.onEnded = () {
          if (identical(_capture, stream)) unawaited(stop());
        };
      }
      // Local capture without any viewer is bounded and remains stoppable.
      _watchdog = Timer(const Duration(minutes: 1), () => unawaited(stop()));
    } on Object {
      if (stream != null && !identical(stream, _capture)) await _releaseStream(stream);
      if (epoch == _epoch) await stop();
      rethrow;
    } finally {
      if (epoch == _epoch) {
        _consenting = false;
        _changed();
      }
    }
  }

  String _nonce() => List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  void _check(int epoch) {
    if (_disposed || epoch != _epoch || (_authorized != null && !_authorized!())) {
      throw StateError('screen session no longer authorized');
    }
  }

  RTCSessionDescription _description(Map<String, dynamic> data, String expectedType) {
    final sdp = data['sdp'];
    if (data['type'] != expectedType ||
        sdp is! String ||
        sdp.length > 60000 ||
        !(sdp.startsWith('v=0\r\n') || sdp.startsWith('v=0\n')) ||
        sdp.contains('\u0000')) {
      throw const FormatException('invalid screen description');
    }
    return RTCSessionDescription(sdp, expectedType);
  }

  Future<RTCPeerConnection> _openPeer(int epoch, {required bool sending}) async {
    final peer = await _makePeer();
    try {
      _check(epoch);
    } on Object {
      await peer.close();
      await peer.dispose();
      rethrow;
    }
    _peer = peer;
    peer
      ..onConnectionState = (state) {
        if (epoch != _epoch) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          unawaited(stop());
        }
      }
      ..onDataChannel = (channel) {
        if (epoch == _epoch) _bindPresence(channel, epoch);
      }
      ..onTrack = (event) {
        if (epoch != _epoch || !_receiving || event.track.kind != 'video') return;
        if (event.streams.isNotEmpty) {
          _incoming = event.streams.first;
          event.track.onEnded = () {
            if (epoch == _epoch) unawaited(stop());
          };
          _changed();
        }
      };
    if (sending) {
      final stream = _capture!;
      for (final track in stream.getVideoTracks()) {
        await peer.addTrack(track, stream);
        _check(epoch);
      }
      _bindPresence(await peer.createDataChannel('purelive-presence', RTCDataChannelInit()), epoch);
    }
    return peer;
  }

  void _bindPresence(RTCDataChannel channel, int epoch) {
    _presence = channel;
    channel.onMessage = (message) {
      if (epoch != _epoch || message.isBinary) return;
      if (message.text == 'pong' || message.text == 'ping') {
        _lastSeen = _now();
        _seenPresence = true;
      }
      if (message.text == 'ping') unawaited(channel.send(RTCDataChannelMessage('pong')));
    };
  }

  void _watch(int epoch) {
    _watchdog?.cancel();
    _lastSeen = _now();
    _seenPresence = false;
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (epoch != _epoch) return;
      if ((_authorized != null && !_authorized!()) ||
          _now().difference(_lastSeen) > Duration(seconds: _seenPresence ? 16 : 35)) {
        unawaited(stop());
        return;
      }
      final channel = _presence;
      if (channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
        unawaited(channel!.send(RTCDataChannelMessage('ping')).catchError((Object _) {}));
      }
    });
  }

  Future<Map<String, Object?>> _localDescription(RTCPeerConnection peer, int epoch, {required bool offer}) async {
    final gathered = Completer<void>();
    peer.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete && !gathered.isCompleted) gathered.complete();
    };
    final description = offer ? await peer.createOffer() : await peer.createAnswer();
    _check(epoch);
    await peer.setLocalDescription(description);
    if (await peer.getIceGatheringState() == RTCIceGatheringState.RTCIceGatheringStateComplete &&
        !gathered.isCompleted) {
      gathered.complete();
    }
    await gathered.future.timeout(const Duration(seconds: 10));
    _check(epoch);
    final result = await peer.getLocalDescription();
    _check(epoch);
    if (result?.sdp == null) throw StateError('screen description unavailable');
    return {'id': _session, 'type': result!.type, 'sdp': result.sdp};
  }

  /// Accepts only the fixed screen actions of an already paired controller.
  Future<Map<String, Object?>> signal(
    String action,
    Map<String, dynamic> data, {
    required String owner,
    required bool Function() authorized,
  }) async {
    if (!authorized() || _disposed) throw StateError('screen controller revoked');
    if (action == 'stop') {
      if (owner != _owner || data['id'] != _session) throw StateError('screen session mismatch');
      await stop();
      return {};
    }
    if (action == 'answer') {
      if (_peer == null || owner != _owner || data['id'] != _session) throw StateError('screen session mismatch');
      final epoch = _epoch;
      final description = _description(data, 'answer');
      await _peer!.setRemoteDescription(description);
      _check(epoch);
      return {};
    }
    // Old teardown owns its original room until restoration completes.
    // A replacement cannot pause that room ahead of the old resume callback.
    await _stopping;
    if (!authorized() || _disposed) throw StateError('screen controller revoked');
    if (!{'view', 'push'}.contains(action) || _working || _peer != null || _consenting || _startingCapture != null) {
      throw StateError('screen session busy');
    }
    if (action == 'view' && _capture == null) throw StateError('local capture consent required');
    if (action == 'push' && (!_receiveAllowed || _capture != null)) {
      throw StateError('local mirror permission required');
    }
    final description = action == 'push' ? _description(data, 'offer') : null;
    final epoch = ++_epoch;
    _owner = owner;
    _session = _nonce();
    _authorized = authorized;
    _working = true;
    // Capture the old room synchronously before the mirror's route covers it.
    final suspension = action == 'push' && suspendPlayback != null ? Future<ScreenResume>.sync(suspendPlayback!) : null;
    var waitingForSuspension = suspension != null;
    _receiving = action == 'push';
    _changed();
    try {
      if (_receiving) {
        final resume = await suspension?.timeout(const Duration(seconds: 5));
        waitingForSuspension = false;
        if (epoch != _epoch) {
          await resume?.call();
          throw StateError('mirror canceled while suspending playback');
        }
        _resume = resume;
      }
      final peer = await _openPeer(epoch, sending: action == 'view');
      if (description != null) await peer.setRemoteDescription(description);
      final result = await _localDescription(peer, epoch, offer: action == 'view');
      _check(epoch);
      _watch(epoch);
      return result;
    } on Object {
      if (waitingForSuspension && suspension != null) {
        unawaited(suspension.then((resume) => resume()).catchError((Object _) {}));
      }
      if (epoch == _epoch) await stop();
      rethrow;
    } finally {
      if (epoch == _epoch) {
        _working = false;
        _changed();
      }
    }
  }

  /// Sends this locally selected screen to an explicitly armed paired app.
  Future<void> sendTo(
    ScreenSignal signal, {
    required Object clientOwner,
    required Future<void> Function() closeClient,
  }) async {
    if (_peer != null || _working) throw StateError('screen session busy');
    if (_capture == null) await startCapture();
    if (_capture == null) throw StateError('screen permission canceled');
    final epoch = ++_epoch;
    _working = true;
    _session = _nonce();
    closeOutgoingClient = closeClient;
    _outgoingOwner = clientOwner;
    _changed();
    try {
      final peer = await _openPeer(epoch, sending: true);
      final offer = await _localDescription(peer, epoch, offer: true);
      final answer = await signal('push', offer);
      _check(epoch);
      await peer.setRemoteDescription(_description(answer, 'answer'));
      _check(epoch);
      _watch(epoch);
    } on Object {
      if (epoch == _epoch) await stop();
      rethrow;
    } finally {
      if (epoch == _epoch) {
        _working = false;
        _changed();
      }
    }
  }

  /// Revoking a paired owner also stops its media channel, not just HTTP input.
  Future<void> revokeOwner(String owner) async {
    if (_owner == owner) await stop();
  }

  Future<void> _releaseStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      track.onEnded = null;
      try {
        await track.stop().timeout(const Duration(seconds: 2));
      } on Object {
        // Continue releasing remaining tracks and the foreground service.
      }
    }
    try {
      await stream.dispose().timeout(const Duration(seconds: 2));
    } on Object {
      // A platform may already have disposed an OS-revoked capture.
    }
  }

  /// Stops first, then restores only the original room owned by this mirror.
  Future<void> stop({bool revoke = false}) {
    if (revoke) _receiveAllowed = false;
    return _stopping ??= _stop().whenComplete(() => _stopping = null);
  }

  Future<void> _stop() async {
    _epoch++;
    final peer = _peer;
    final capture = _capture;
    final incoming = _incoming;
    final resume = _resume;
    final closeClient = closeOutgoingClient;
    _peer = null;
    _capture = null;
    _incoming = null;
    _resume = null;
    closeOutgoingClient = null;
    _outgoingOwner = null;
    _owner = null;
    _session = null;
    _authorized = null;
    _presence = null;
    _working = false;
    _receiving = false;
    _consenting = false;
    _watchdog?.cancel();
    _watchdog = null;
    _changed();
    try {
      if (peer != null) {
        peer
          ..onConnectionState = null
          ..onTrack = null;
        await peer.close().timeout(const Duration(seconds: 2));
        await peer.dispose().timeout(const Duration(seconds: 2));
      }
    } on Object {
      // Track and service cleanup still runs after a failed peer close.
    } finally {
      if (capture != null) await _releaseStream(capture);
      if (incoming != null && !identical(incoming, capture)) await _releaseStream(incoming);
      try {
        await endCapture().timeout(const Duration(seconds: 3));
      } on Object {
        // Restoration still runs if an OS service has already disappeared.
      }
      try {
        await resume?.call().timeout(const Duration(seconds: 10));
      } on Object {
        // The original room exposes its own retry UI if restoration fails.
      }
      try {
        await closeClient?.call().timeout(const Duration(seconds: 5));
      } on Object {
        // The peer may already be offline; local capture is already released.
      }
    }
  }

  /// Final app shutdown; callers await media cleanup before disposing listeners.
  Future<void> close() async {
    await stop(revoke: true);
    _disposed = true;
    super.dispose();
  }
}
