import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/launch_args.dart';

/// A random identifier for a window or a local control capability.
String projectionNonce() {
  final random = Random.secure();
  return base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256))).replaceAll('=', '');
}

/// The room and physical display selected by the wall. An empty display leaves
/// the receiver on its current monitor and virtual desktop.
final class ProjectionSelection {
  /// Creates a selection.
  const new(this.room, {this.display = ''});

  /// Public card fields only; platform responses and credentials never travel.
  final LiveRoom room;

  /// A copied display geometry's persistence key.
  final String display;
}

/// The authenticated receiver of one explicitly launched projection window.
/// It listens only on loopback, with no browser origin or CORS permission.
final class ProjectionReceiver {
  new _(this._server, this._file, this._token, this._open, this._close);

  final HttpServer _server;
  final File _file;
  final String _token;
  final Future<void> Function(ProjectionSelection) _open;
  final Future<void> Function() _close;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  /// Starts a receiver and atomically advertises its endpoint in this window's
  /// own runtime folder. The capability is never put in a URL or log.
  static Future<ProjectionReceiver> start({
    required File file,
    required Future<void> Function(ProjectionSelection) onOpen,
    required Future<void> Function() onClose,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final receiver = ProjectionReceiver._(server, file, projectionNonce(), onOpen, onClose);
    server.listen((request) => unawaited(receiver._handle(request)));
    try {
      await file.parent.create(recursive: true);
      final pending = File('${file.path}.pending');
      await pending.writeAsString(jsonEncode({'port': server.port, 'token': receiver._token}), flush: true);
      await pending.rename(file.path);
    } on Object {
      await server.close(force: true);
      rethrow;
    }
    return receiver;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.persistentConnection = false;
    try {
      final bytes = <int>[];
      if (request.method == 'POST') {
        await for (final chunk in request.timeout(const Duration(seconds: 10))) {
          bytes.addAll(chunk);
          if (bytes.length > 16384) throw const FormatException('oversized');
        }
      }
      if (_disposed ||
          request.headers.value('origin') != null ||
          request.headers.value(HttpHeaders.authorizationHeader) != 'Bearer $_token') {
        response.statusCode = HttpStatus.forbidden;
      } else if (request.method == 'GET' && request.uri.path == '/ready') {
        response.write('ready');
      } else if (request.method == 'POST' && request.uri.path == '/room') {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) throw const FormatException('invalid selection');
        final argument = decoded['room'];
        final display = decoded['display'];
        if (argument is! String || display is! String || display.length > 2048) {
          throw const FormatException('invalid selection');
        }
        final room = LaunchArgs.roomFromArgs([argument]);
        if (room == null || !SiteIds.isSupported(room.platform)) throw const FormatException('invalid room');
        // Requests are applied in arrival order even if window positioning awaits
        // a native result. A failed callback does not poison the next request.
        final done = Completer<void>();
        _tail = _tail.then((_) async {
          try {
            if (!_disposed) await _open(ProjectionSelection(room, display: display));
            done.complete();
          } on Object catch (error, stack) {
            done.completeError(error, stack);
          }
        });
        await done.future;
        response.write('ok');
      } else if (request.method == 'POST' && request.uri.path == '/close') {
        response.write('ok');
        await response.close();
        await _close();
        return;
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } on FormatException {
      response.statusCode = HttpStatus.badRequest;
    } on TimeoutException {
      response.statusCode = HttpStatus.requestTimeout;
    } on Object {
      response.statusCode = HttpStatus.serviceUnavailable;
    }
    try {
      await response.close();
    } on Object {
      // A wall can close while a native window operation is pending.
    }
  }

  /// Stops this receiver and removes only its own advertisement.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _server.close(force: true);
    try {
      if (_file.existsSync()) await _file.delete();
    } on FileSystemException {
      // Shutdown may race removal of the temporary runtime directory.
    }
  }
}

/// Owns one projection process. Rapid choices collapse to the newest pending
/// room, and closing/reopening a receiver never spawns a process per cell tap.
final class ProjectionChannel {
  /// Creates a channel under the shared data folder.
  new(this._root, {this._launch});

  final Directory _root;
  final Future<void> Function(List<String>)? _launch;
  File? _file;
  ProjectionSelection? _pending;
  Future<void>? _drain;
  bool _closed = false;
  Process? _process;
  bool _exited = false;

  Future<void> _launchProcess(List<String> args) async {
    final process = await Process.start(Platform.resolvedExecutable, args);
    _process = process;
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.then((_) {
        if (identical(_process, process)) _exited = true;
      }),
    );
  }

  /// Sends [selection], starting a receiver only when the old one is gone.
  Future<void> select(ProjectionSelection selection) {
    if (_closed) return Future<void>.value();
    _pending = selection;
    return _drain ??= _run().whenComplete(() => _drain = null);
  }

  Future<void> _run() async {
    while (!_closed && _pending != null) {
      final selection = _pending!;
      _pending = null;
      if (_file == null || _exited) {
        await _start();
      } else if (!await _request('GET', '/ready')) {
        // A temporarily unreachable or still-starting owned process is not
        // evidence that it exited. Never multiply windows on ambiguous failure.
        throw const SocketException('Projection receiver unavailable');
      }
      if (_closed) break;
      if (!await _request(
        'POST',
        '/room',
        body: {'room': LaunchArgs.encodeRoomArgument(selection.room), 'display': selection.display},
      )) {
        // Do not retry ambiguous mutations by spawning another window. A user
        // can retry; the next readiness probe detects an exited receiver.
        throw const SocketException('Projection receiver unavailable');
      }
    }
  }

  Future<void> _start() async {
    final id = 'projection_${projectionNonce()}';
    _file = File(p.join(_root.path, 'instances', id, 'projection.json'));
    _exited = false;
    await (_launch ?? _launchProcess)([...LaunchArgs.build(instanceId: id), '--projection']);
    for (var attempt = 0; attempt < 30; attempt++) {
      if (await _request('GET', '/ready')) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw const SocketException('Projection startup timed out');
  }

  Future<bool> _request(String method, String path, {Map<String, Object?>? body}) async {
    final file = _file;
    if (file == null) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      if (await file.length() > 1024) return false;
      final endpoint = jsonDecode(await file.readAsString());
      if (endpoint is! Map) return false;
      final port = endpoint['port'];
      final token = endpoint['token'];
      if (port is! int || port < 1 || port > 65535 || token is! String || token.length != 43) return false;
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 10));
      await response.drain<void>().timeout(const Duration(seconds: 2));
      return response.statusCode == HttpStatus.ok;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Closes only this wall's receiver, including one still starting.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pending = null;
    try {
      await _drain;
    } on Object {
      // Still attempt to close a late receiver after a startup failure.
    }
    await _request('POST', '/close');
  }
}
