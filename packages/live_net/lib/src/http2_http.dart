import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http2/http2.dart';
import 'package:live_net/src/io_http.dart';
import 'package:live_net/src/live_http.dart';
import 'package:live_net/src/proxy.dart';
import 'package:live_net/src/request.dart';
import 'package:live_net/src/response.dart';
import 'package:live_net/src/streamed_response.dart';
import 'package:live_net/src/transport_failure.dart';

/// HTTP/2 over TLS for hosts that refuse HTTP/1.1 (Kick's API answers
/// "Request blocked by security policy." to every HTTP/1.1 client since
/// 2026-10, `dart:io` and Android's `HttpURLConnection` alike).
///
/// One connection per request, through the request's [proxy] route (an
/// HTTP proxy is asked for a `CONNECT` tunnel first). Bodies are read
/// whole; redirects are followed up to five times. Only `https` URLs.
final class Http2LiveHttp implements LiveHttp {
  /// Creates the transport.
  new({this.proxy = const FixedProxyPolicy(), this.connectTimeout = defaultRequestTimeout, this.context});

  /// Route per platform.
  final ProxyPolicy proxy;

  /// Limit for opening a connection (and its tunnel and handshake).
  final Duration connectTimeout;

  /// Trusted certificates; the system's when null (tests trust their own).
  final SecurityContext? context;

  /// The longest proxy answer to a `CONNECT` read before giving up.
  static const int maxTunnelReply = 16 * 1024;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    if (request.cancel?.isCancelled ?? false) throw TransportFailure(request.site, TransportReason.cancelled);
    ClientTransportConnection? connection;
    final cancelled = request.cancel?.whenCancelled.then<LiveResponse>((_) {
      unawaited(connection?.terminate());
      throw TransportFailure(request.site, TransportReason.cancelled);
    });
    Future<LiveResponse> exchange(Uri url, int redirects) async {
      final open = connection = await _connect(request.site, url);
      try {
        final response = await _exchange(open, request, url);
        final location = response.header('location');
        if (request.followRedirects && response.status >= 300 && response.status < 400 && location != null) {
          if (redirects >= 5) throw TransportFailure(request.site, TransportReason.protocol, 'too many redirects');
          return await exchange(url.resolve(location), redirects + 1);
        }
        return response;
      } finally {
        unawaited(open.finish().catchError((Object _) {}));
      }
    }

    try {
      return await Future.any([exchange(request.url, 0).timeout(request.timeout), ?cancelled]);
    } on Object catch (error) {
      unawaited(connection?.terminate());
      throw failureOf(request.site, error, request.timeout);
    }
  }

  /// Streams nothing incrementally: the body arrives whole, then as one
  /// chunk (the hosts this serves answer small JSON).
  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final response = await send(request);
    return LiveStreamedResponse(
      status: response.status,
      headers: response.headers,
      body: Stream.value(response.bytes),
      url: response.url,
      contentLength: response.bytes.length,
    );
  }

  @override
  void close() {}

  Future<ClientTransportConnection> _connect(String site, Uri url) async {
    if (url.scheme != 'https') throw TransportFailure(site, TransportReason.protocol, 'HTTP/2 needs https');
    final port = url.hasPort ? url.port : 443;
    final route = proxy.routeFor(site, url);
    final Socket socket;
    final String? protocol;
    if (route is HttpProxyRoute) {
      final tunnel = await _tunnel(site, route, url.host, port);
      protocol = tunnel.selectedProtocol;
      socket = _RawSecureSocketAdapter.wrap(tunnel);
    } else {
      final direct = await SecureSocket.connect(
        url.host,
        port,
        context: context,
        supportedProtocols: const ['h2'],
        timeout: connectTimeout,
      );
      protocol = direct.selectedProtocol;
      socket = direct;
    }
    if (protocol != 'h2') {
      socket.destroy();
      throw TransportFailure(site, TransportReason.protocol, 'the server does not speak HTTP/2');
    }
    return ClientTransportConnection.viaSocket(socket);
  }

  /// TLS to [host]:[port] through a `CONNECT` tunnel of [route]: the proxy's
  /// answer is read without touching what follows it, then the handshake
  /// runs on the same socket.
  Future<RawSecureSocket> _tunnel(String site, HttpProxyRoute route, String host, int port) async {
    final raw = await RawSocket.connect(route.host, route.port, timeout: connectTimeout);
    final target = '${host.contains(':') ? '[$host]' : host}:$port';
    raw.write(latin1.encode('CONNECT $target HTTP/1.1\r\nHost: $target\r\n\r\n'));
    final reply = BytesBuilder(copy: false);
    final answered = Completer<void>();
    late final StreamSubscription<RawSocketEvent> events;
    bool complete() {
      final bytes = reply.toBytes();
      for (var i = 3; i < bytes.length; i++) {
        if (bytes[i - 3] == 13 && bytes[i - 2] == 10 && bytes[i - 1] == 13 && bytes[i] == 10) return true;
      }
      return false;
    }

    events = raw.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          // One byte at a time: the proxy sends nothing after its answer
          // until the TLS handshake starts, but nothing past the blank line
          // may be swallowed here.
          final byte = raw.read(1);
          if (byte != null) reply.add(byte);
          if (complete() && !answered.isCompleted) {
            // Read nothing more: the TLS upgrade takes the subscription
            // over (it must not be paused) and reads the handshake itself.
            raw.readEventsEnabled = false;
            answered.complete();
          } else if (reply.length > maxTunnelReply && !answered.isCompleted) {
            answered.completeError(TransportFailure(site, TransportReason.protocol, 'proxy answer too long'));
          }
        } else if (event == RawSocketEvent.readClosed && !answered.isCompleted) {
          answered.completeError(TransportFailure(site, TransportReason.connect, 'proxy closed the tunnel'));
        }
      },
      onError: (Object error) {
        if (!answered.isCompleted) answered.completeError(error);
      },
    );
    try {
      await answered.future.timeout(connectTimeout);
    } on Object {
      await events.cancel();
      await raw.close();
      rethrow;
    }
    final status = latin1.decode(reply.toBytes()).split('\r\n').first;
    if (!RegExp(r'^HTTP/1\.[01] 2\d\d').hasMatch(status)) {
      await events.cancel();
      await raw.close();
      throw TransportFailure(site, TransportReason.connect, 'proxy refused the tunnel: $status');
    }
    return await RawSecureSocket.secure(
      raw,
      subscription: events,
      host: host,
      context: context,
      supportedProtocols: const ['h2'],
    );
  }

  Future<LiveResponse> _exchange(ClientTransportConnection connection, LiveRequest request, Uri url) async {
    final path = url.hasQuery
        ? '${url.path.isEmpty ? '/' : url.path}?${url.query}'
        : (url.path.isEmpty ? '/' : url.path);
    final body = request.body;
    final headers = [
      Header.ascii(':method', request.method),
      Header.ascii(':path', path),
      Header.ascii(':scheme', 'https'),
      Header.ascii(':authority', url.hasPort && url.port != 443 ? '${url.host}:${url.port}' : url.host),
      for (final MapEntry(:key, :value) in request.headers.entries)
        if (!_connectionHeaders.contains(key.toLowerCase()))
          Header(ascii.encode(key.toLowerCase()), utf8.encode(value)),
      if (body != null) Header.ascii('content-length', '${body.length}'),
    ];
    final stream = connection.makeRequest(headers, endStream: body == null);
    if (body != null) stream.sendData(body, endStream: true);
    var status = 0;
    final responseHeaders = <String, List<String>>{};
    final bytes = BytesBuilder(copy: false);
    await for (final message in stream.incomingMessages) {
      if (message is HeadersStreamMessage) {
        for (final header in message.headers) {
          final name = ascii.decode(header.name, allowInvalid: true).toLowerCase();
          final value = utf8.decode(header.value, allowMalformed: true);
          if (name == ':status') {
            status = int.tryParse(value) ?? 0;
          } else if (!name.startsWith(':')) {
            (responseHeaders[name] ??= []).add(value);
          }
        }
      } else if (message is DataStreamMessage) {
        bytes.add(message.bytes);
      }
    }
    if (status == 0) throw TransportFailure(request.site, TransportReason.protocol, 'no status');
    var data = bytes.toBytes();
    final encoding = responseHeaders['content-encoding']?.first.toLowerCase();
    if (encoding == 'gzip') {
      data = Uint8List.fromList(gzip.decode(data));
    } else if (encoding == 'deflate') {
      data = Uint8List.fromList(zlib.decode(data));
    }
    return LiveResponse(status: status, headers: responseHeaders, bytes: data, url: url);
  }

  /// HTTP/1.1 connection headers HTTP/2 forbids.
  static const Set<String> _connectionHeaders = {
    'connection',
    'keep-alive',
    'proxy-connection',
    'transfer-encoding',
    'upgrade',
    'host',
  };
}

/// A [RawSecureSocket] seen as the [Socket] the HTTP/2 transport reads and
/// writes: incoming data as a stream, outgoing data queued until the socket
/// takes it.
final class _RawSecureSocketAdapter extends Stream<Uint8List> implements Socket {
  new _(this._raw);

  static Socket wrap(RawSecureSocket raw) => _RawSecureSocketAdapter._(raw).._start();

  final RawSecureSocket _raw;
  final StreamController<Uint8List> _incoming = StreamController<Uint8List>();
  final List<List<int>> _pending = [];
  final Completer<void> _closed = Completer<void>();
  StreamSubscription<RawSocketEvent>? _events;

  void _start() {
    _events = _raw.listen(
      (event) {
        switch (event) {
          case RawSocketEvent.read:
            final data = _raw.read();
            if (data != null && data.isNotEmpty) _incoming.add(data);
          case RawSocketEvent.write:
            _flush();
          case RawSocketEvent.readClosed:
          case RawSocketEvent.closed:
            _finish();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_incoming.isClosed) _incoming.addError(error, stack);
        _finish();
      },
      onDone: _finish,
    );
  }

  void _finish() {
    if (!_incoming.isClosed) unawaited(_incoming.close());
    if (!_closed.isCompleted) _closed.complete();
  }

  void _flush() {
    while (_pending.isNotEmpty) {
      final chunk = _pending.first;
      final written = _raw.write(chunk);
      if (written < chunk.length) {
        _pending[0] = chunk.sublist(written);
        _raw.writeEventsEnabled = true;
        return;
      }
      _pending.removeAt(0);
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _incoming.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  void add(List<int> data) {
    _pending.add(data);
    _flush();
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> flush() async => _flush();

  @override
  Future<void> close() async {
    _flush();
    await _raw.close();
    await _events?.cancel();
    _finish();
  }

  @override
  Future<void> get done => _closed.future;

  @override
  void destroy() {
    unawaited(_raw.close());
    unawaited(_events?.cancel());
    _finish();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  void write(Object? object) => add(utf8.encode('$object'));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) => write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  Encoding encoding = utf8;

  @override
  InternetAddress get address => _raw.address;

  @override
  int get port => _raw.port;

  @override
  InternetAddress get remoteAddress => _raw.remoteAddress;

  @override
  int get remotePort => _raw.remotePort;

  @override
  bool setOption(SocketOption option, bool enabled) => _raw.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _raw.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _raw.setRawOption(option);
}
