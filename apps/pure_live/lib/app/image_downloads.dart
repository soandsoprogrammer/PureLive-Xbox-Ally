import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

/// Image downloads on an isolate of their own (R01.3).
///
/// flutter_cache_manager fetched covers with an `HttpClient` on the UI
/// isolate: on the K90 a first visit to four platform tabs spent about
/// 120 ms of UI time in TLS handshakes, socket reads and buffering, in the
/// middle of the page turns. Here a worker isolate opens the connections
/// and reads the whole body; the UI isolate gets the bytes in one message.
///
/// [directiveFor] is read for each request (the app proxy as
/// `HttpClient.findProxy` takes it), so a changed proxy applies to the next
/// image. With `HttpOverrides` in force (tests) the downloads stay on this
/// isolate, through them.
final class IsolateImageFileService extends FileService {
  /// Creates the service.
  new({required this.directiveFor, this.connectTimeout = const Duration(seconds: 15)});

  /// The proxy directive for an image URL ("DIRECT", "PROXY host:port").
  final String Function(Uri url) directiveFor;

  /// How long a connection may take.
  final Duration connectTimeout;

  /// How long a whole download may take.
  static const Duration timeout = Duration(seconds: 60);

  _Worker? _worker;

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    final uri = Uri.parse(url);
    final directive = directiveFor(uri);
    if (HttpOverrides.current != null) {
      return HttpGetResponse(await _fetchHere(uri, headers ?? const {}, directive));
    }
    final worker = _worker ??= _Worker(connectTimeout);
    final reply = await worker.fetch(url, headers ?? const {}, directive);
    final bytes = reply.bytes.materialize().asUint8List();
    return HttpGetResponse(
      http.StreamedResponse(
        Stream.value(bytes),
        reply.status,
        contentLength: bytes.length,
        headers: reply.headers,
        request: http.Request('GET', uri),
      ),
    );
  }

  Future<http.StreamedResponse> _fetchHere(Uri uri, Map<String, String> headers, String directive) async {
    final client = HttpClient()
      ..connectionTimeout = connectTimeout
      ..findProxy = (_) => directive;
    try {
      final reply = await _download(client, uri, headers).timeout(timeout);
      final bytes = reply.bytes.materialize().asUint8List();
      return http.StreamedResponse(
        Stream.value(bytes),
        reply.status,
        contentLength: bytes.length,
        headers: reply.headers,
        request: http.Request('GET', uri),
      );
    } finally {
      client.close();
    }
  }
}

/// A finished download.
typedef _Reply = ({int status, Map<String, String> headers, TransferableTypedData bytes});

/// Reads [uri] whole with [client].
Future<_Reply> _download(HttpClient client, Uri uri, Map<String, String> headers) async {
  final request = await client.getUrl(uri);
  headers.forEach(request.headers.set);
  final response = await request.close();
  final body = await response.fold(BytesBuilder(copy: false), (all, chunk) => all..add(chunk));
  final names = <String, String>{};
  response.headers.forEach((name, values) => names[name.toLowerCase()] = values.join(','));
  return (status: response.statusCode, headers: names, bytes: TransferableTypedData.fromList([body.takeBytes()]));
}

/// The worker isolate and the requests waiting on it.
final class _Worker {
  new(this.connectTimeout);

  final Duration connectTimeout;
  final Map<int, Completer<_Reply>> _waiting = {};
  int _next = 0;
  Future<SendPort>? _port;
  ReceivePort? _inbox;

  Future<_Reply> fetch(String url, Map<String, String> headers, String directive) async {
    final port = await (_port ??= _spawn());
    final id = _next++;
    final done = _waiting[id] = Completer<_Reply>();
    port.send((id, url, headers, directive));
    return await done.future.timeout(
      IsolateImageFileService.timeout,
      onTimeout: () {
        _waiting.remove(id);
        throw TimeoutException('image download', IsolateImageFileService.timeout);
      },
    );
  }

  Future<SendPort> _spawn() async {
    final inbox = _inbox = ReceivePort();
    final ready = Completer<SendPort>();
    inbox.listen((message) {
      switch (message) {
        case final SendPort port:
          ready.complete(port);
        case (final int id, final int status, final Map<String, String> headers, final TransferableTypedData bytes):
          _waiting.remove(id)?.complete((status: status, headers: headers, bytes: bytes));
        case (final int id, final String error):
          _waiting.remove(id)?.completeError(HttpException(error));
        case null:
          // The isolate ended: fail what waits, start a new one next time.
          _fail('image worker ended');
      }
    });
    await Isolate.spawn(_main, (inbox.sendPort, connectTimeout), onExit: inbox.sendPort, debugName: 'image downloads');
    return await ready.future;
  }

  void _fail(String why) {
    final waiting = [..._waiting.values];
    _waiting.clear();
    for (final done in waiting) {
      done.completeError(HttpException(why));
    }
    _port = null;
    _inbox?.close();
    _inbox = null;
  }

  /// The worker: one client per proxy directive, idle connections kept
  /// 30 s for the next images of the same host.
  static void _main((SendPort, Duration) setup) {
    final (reply, connectTimeout) = setup;
    final inbox = ReceivePort();
    final clients = <String, HttpClient>{};
    reply.send(inbox.sendPort);
    inbox.listen((message) async {
      final (int id, String url, Map<String, String> headers, String directive) =
          message as (int, String, Map<String, String>, String);
      final client = clients[directive] ??= HttpClient()
        ..idleTimeout = const Duration(seconds: 30)
        ..connectionTimeout = connectTimeout
        ..findProxy = (_) => directive;
      try {
        final result = await _download(client, Uri.parse(url), headers);
        reply.send((id, result.status, result.headers, result.bytes));
      } on Object catch (error) {
        reply.send((id, '$error'));
      }
    });
  }
}
