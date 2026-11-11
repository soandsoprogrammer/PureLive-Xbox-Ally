import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/downloads.dart';

import 'download_protocol_regression_test.dart' as fixture;

final class FaultOperations extends DownloadFileOperations {
  new({this.fail, this.cancel, this.cancelAt});
  final String? fail;
  final CancelToken? cancel;
  final String? cancelAt;
  final List<String> operations = [];
  void check(String operation) {
    operations.add(operation);
    if (operation == cancelAt) cancel?.cancel();
    if (operation == fail || (fail == 'restore' && operation == 'promote')) {
      throw FileSystemException('injected $operation');
    }
  }

  @override
  Future<bool> exists(File file) async {
    check('exists');
    return await super.exists(file);
  }

  @override
  Future<void> delete(File file) async {
    check('delete');
    await super.delete(file);
  }

  @override
  Future<void> writeText(File file, String text) async {
    check('sidecar');
    await super.writeText(file, text);
  }

  @override
  Future<RandomAccessFile> open(File file, FileMode mode) async {
    check('open');
    return await super.open(file, mode);
  }

  @override
  Future<void> write(RandomAccessFile file, List<int> bytes) async {
    check('write');
    await super.write(file, bytes);
  }

  @override
  Future<void> flush(RandomAccessFile file) async {
    check('flush');
    await super.flush(file);
  }

  @override
  Future<void> close(RandomAccessFile file) async {
    await super.close(file);
    check('close');
  }

  @override
  Stream<List<int>> read(File file) async* {
    check('hash');
    await for (final chunk in super.read(file)) {
      check('hash-chunk');
      yield chunk;
    }
  }

  @override
  Future<File> rename(File file, String path) async {
    if (file.path.endsWith('.part') && (fail == 'promote' || fail == 'restore')) {
      // Emulate a platform replacement that removes the old destination first.
      final target = File(path);
      if (target.existsSync()) await target.delete();
    }
    check(file.path.endsWith('.part') ? 'promote' : 'sidecar-rename');
    return await super.rename(file, path);
  }

  @override
  Future<File> copy(File file, String path) async {
    check(p.basename(file.path) == 'target' ? 'restore' : 'backup');
    return await super.copy(file, path);
  }
}

final class BarrierOperations extends DownloadFileOperations {
  new(this.point);
  final String point;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Stream<List<int>> read(File file) async* {
    if (point == 'hash') {
      entered.complete();
      await release.future;
    }
    yield* super.read(file);
  }

  @override
  Future<File> copy(File file, String path) async {
    final result = await super.copy(file, path);
    if (point == 'backup') {
      entered.complete();
      await release.future;
    }
    return result;
  }
}

final class FailingLookupFile implements File {
  @override
  Future<bool> exists() => Future.error(const FileSystemException('lookup failed'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory temp;
  late File target;
  final source = Uri.parse('https://origin.example/pkg.apk?asset=1');
  final mirror = Uri.parse('https://mirror.example/pkg.apk');
  const bytes = [1, 2, 3, 4, 5, 6];
  late DownloadIntegrity identity;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('download_integrity_');
    target = File(p.join(temp.path, 'pkg.apk'));
    identity = DownloadIntegrity(
      canonicalUrl: source,
      sizeBytes: bytes.length,
      sha256: crypto.sha256.convert(bytes).toString(),
      version: '9.0.0',
      buildNumber: 6000,
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  void seed(List<int> part, {DownloadIntegrity? asIdentity, String? metadata}) {
    final expected = asIdentity ?? identity;
    FileDownloader.partOf(target).writeAsBytesSync(part);
    FileDownloader.metadataOf(target).writeAsStringSync(
      metadata ??
          jsonEncode({
            'schema': 1,
            'url': expected.canonicalUrl.toString(),
            'size_bytes': expected.sizeBytes,
            'sha256': expected.sha256,
            'version': expected.version,
            'build_number': expected.buildNumber,
          }),
    );
  }

  fixture.ProtocolHttp validHttp() =>
      fixture.ProtocolHttp((request, _) => fixture.reply(request, 200, bytes, length: bytes.length));

  test('async file existence distinguishes missing file, regular file and directory', () async {
    const operations = DownloadFileOperations();
    expect(await operations.exists(target), isFalse);
    target.writeAsBytesSync([9]);
    expect(await operations.exists(target), isTrue);
    expect(await operations.exists(File(temp.path)), isFalse);
  });

  test('async existence adapter propagates lookup errors rather than claiming absence', () async {
    await expectLater(const DownloadFileOperations().exists(FailingLookupFile()), throwsA(isA<FileSystemException>()));
  });

  test('async file existence follows a symlink to a regular file', () async {
    const operations = DownloadFileOperations();
    target.writeAsBytesSync([9]);
    final link = Link(p.join(temp.path, 'alias'));
    await link.create(target.path);
    expect(await operations.exists(File(link.path)), isTrue);
    await target.delete();
    expect(await operations.exists(File(link.path)), isFalse);
  }, skip: Platform.isWindows ? 'Creating Windows symlinks may require OS privileges' : false);

  test('exact size and streamed SHA-256 succeed and remove partial identity', () async {
    final http = validHttp();
    final result = await FileDownloader(http).download([source], target, integrity: identity);
    expect(result.path, target.path);
    expect(target.readAsBytesSync(), bytes);
    expect(FileDownloader.partOf(target).existsSync(), isFalse);
    expect(FileDownloader.metadataOf(target).existsSync(), isFalse);
    expect(http.requests.single.headers['accept-encoding'], 'identity');
  });

  test('identity validates size, SHA and canonical origin', () {
    for (final size in [0, -1, 9007199254740992]) {
      expect(
        () => DownloadIntegrity(canonicalUrl: source, sizeBytes: size, sha256: identity.sha256),
        throwsArgumentError,
      );
    }
    for (final hash in ['', 'a' * 63, 'g' * 64, '${identity.sha256}\n']) {
      expect(() => DownloadIntegrity(canonicalUrl: source, sizeBytes: 6, sha256: hash), throwsArgumentError);
    }
    expect(
      () => DownloadIntegrity(canonicalUrl: Uri.parse('http://example.com/a'), sizeBytes: 6, sha256: identity.sha256),
      throwsArgumentError,
    );
    expect(
      DownloadIntegrity(canonicalUrl: source, sizeBytes: 6, sha256: identity.sha256.toUpperCase()).sha256,
      identity.sha256,
    );
  });

  test('verified replacement preserves then cleans the prior-target backup', () async {
    target.writeAsBytesSync([9]);
    await FileDownloader(validHttp()).download([source], target, integrity: identity);
    expect(target.readAsBytesSync(), bytes);
    expect(temp.listSync().whereType<Directory>(), isEmpty);
  });

  test('matching complete partial is rehashed and reused without HTTP', () async {
    seed(bytes);
    final http = validHttp();
    await FileDownloader(http).download([source], target, integrity: identity);
    expect(http.requests, isEmpty);
    expect(target.readAsBytesSync(), bytes);
  });

  test('matching bound partial resumes the complete remaining range', () async {
    seed(bytes.sublist(0, 2));
    final http = fixture.ProtocolHttp(
      (request, _) => fixture.reply(
        request,
        206,
        bytes.sublist(2),
        length: 4,
        headers: {
          'Content-Range': ['bytes 2-5/6'],
          'Content-Length': ['4'],
        },
      ),
    );
    await FileDownloader(http).download([source], target, integrity: identity);
    expect(target.readAsBytesSync(), bytes);
    expect(http.requests.single.headers['range'], 'bytes=2-');
  });

  test('200 ignoring Range truncates rather than appending', () async {
    seed(bytes.sublist(0, 2));
    final http = validHttp();
    await FileDownloader(http).download([source], target, integrity: identity);
    expect(http.requests.single.headers['range'], 'bytes=2-');
    expect(target.readAsBytesSync(), bytes);
  });

  test('zero-offset complete 206 is usable', () async {
    final http = fixture.ProtocolHttp(
      (request, _) => fixture.reply(
        request,
        206,
        bytes,
        length: 6,
        headers: {
          'content-range': ['bytes 0-5/6'],
        },
      ),
    );
    await FileDownloader(http).download([source], target, integrity: identity);
    expect(target.readAsBytesSync(), bytes);
  });

  for (final range in [
    'bytes 1-5/6',
    'bytes 2-4/6',
    'bytes 2-6/6',
    'bytes 2-5/7',
    'bytes 2-5/*',
    'bytes 2-1/6',
    'bytes 2-5/0',
    'bytes 2-5/9007199254740992',
    'bytes 2-5/6 junk',
    'bytes 2-5/6\n',
    'bytes 2-5/6, bytes 7-8/9',
  ]) {
    test('malformed or inconsistent range is rejected: $range', () async {
      seed(bytes.sublist(0, 2));
      final http = fixture.ProtocolHttp(
        (request, _) => fixture.reply(
          request,
          206,
          bytes.sublist(2),
          length: 4,
          headers: {
            'content-range': [range],
          },
        ),
      );
      await expectLater(
        FileDownloader(http).download([source], target, integrity: identity),
        throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.integrity)),
      );
      expect(target.existsSync(), isFalse);
      expect(http.requests, hasLength(2));
    });
  }

  for (final headers in [
    {
      'content-range': ['bytes 2-5/6'],
      'content-length': ['3'],
    },
    {
      'content-range': ['bytes 2-5/6'],
      'content-length': ['4\n'],
    },
    {
      'content-range': ['bytes 2-5/6'],
      'content-length': ['4', '4'],
    },
    {
      'content-range': ['bytes 2-5/6'],
      'content-type': ['multipart/byteranges'],
    },
    {
      'content-range': ['bytes 2-5/6'],
      'content-encoding': ['gzip'],
    },
  ]) {
    test('range header contradiction rejects ${headers.keys.join(',')}/${headers.values}', () async {
      seed(bytes.sublist(0, 2));
      final http = fixture.ProtocolHttp(
        (request, _) => fixture.reply(request, 206, bytes.sublist(2), length: 4, headers: headers),
      );
      await expectLater(
        FileDownloader(http).download([source], target, integrity: identity),
        throwsA(isA<DownloadException>()),
      );
      expect(target.existsSync(), isFalse);
    });
  }

  for (final range in [null, 'bytes */6', 'bytes */2', 'bytes */99', 'bytes */*']) {
    test('416 does not complete a truncated bound part ($range)', () async {
      seed(bytes.sublist(0, 2));
      final http = fixture.ProtocolHttp(
        (request, _) => fixture.reply(
          request,
          416,
          [],
          headers: {
            if (range != null) 'content-range': [range],
          },
        ),
      );
      await expectLater(
        FileDownloader(http).download([source], target, integrity: identity),
        throwsA(isA<DownloadException>()),
      );
      expect(target.existsSync(), isFalse);
      expect(http.requests.map((r) => r.headers['range']), ['bytes=2-', null]);
    });
  }

  test('bad range gets one clean retry and may succeed', () async {
    seed(bytes.sublist(0, 2));
    final http = fixture.ProtocolHttp(
      (request, index) => index == 1
          ? fixture.reply(
              request,
              416,
              [],
              headers: {
                'content-range': ['bytes */6'],
              },
            )
          : fixture.reply(request, 200, bytes, length: 6),
    );
    await FileDownloader(http).download([source, source], target, integrity: identity);
    expect(http.requests, hasLength(2));
    expect(target.readAsBytesSync(), bytes);
  });

  for (final variant in ['missing', 'corrupt', 'different-url', 'different-digest', 'different-build', 'oversized']) {
    test('partial is reset on $variant identity', () async {
      var old = identity;
      if (variant.startsWith('different-')) {
        old = DownloadIntegrity(
          canonicalUrl: variant == 'different-url' ? Uri.parse('https://origin.example/pkg.apk?asset=2') : source,
          sizeBytes: 6,
          sha256: variant == 'different-digest' ? 'a' * 64 : identity.sha256,
          version: '9.0.0',
          buildNumber: variant == 'different-build' ? 5999 : 6000,
        );
      }
      seed(
        variant == 'oversized' ? [...bytes, 7] : bytes.sublist(0, 2),
        asIdentity: old,
        metadata: variant == 'corrupt' ? '{broken' : null,
      );
      if (variant == 'missing') FileDownloader.metadataOf(target).deleteSync();
      final http = validHttp();
      await FileDownloader(http).download([source], target, integrity: identity);
      expect(http.requests.single.headers['range'], isNull);
      expect(target.readAsBytesSync(), bytes);
    });
  }

  test('stale complete partial wrong hash is discarded then downloaded afresh', () async {
    seed([9, 9, 9, 9, 9, 9]);
    final http = validHttp();
    await FileDownloader(http).download([source], target, integrity: identity);
    expect(http.requests.single.headers['range'], isNull);
    expect(target.readAsBytesSync(), bytes);
  });

  test('same-size wrong digest cannot replace valid target and retry is bounded', () async {
    target.writeAsBytesSync([9]);
    final http = fixture.ProtocolHttp((request, _) => fixture.reply(request, 200, [9, 9, 9, 9, 9, 9], length: 6));
    await expectLater(
      FileDownloader(http).download([source, source], target, integrity: identity),
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.integrity)),
    );
    expect(target.readAsBytesSync(), [9]);
    expect(http.requests, hasLength(2));
    expect(FileDownloader.partOf(target).existsSync(), isFalse);
  });

  test('wrong first source resets before valid origin', () async {
    final http = fixture.ProtocolHttp(
      (request, _) => fixture.reply(request, 200, request.url == source ? bytes : [9, 9, 9, 9, 9, 9], length: 6),
    );
    await FileDownloader(http).download([mirror, source], target, integrity: identity);
    expect(http.requests, hasLength(3));
    expect(http.requests.map((r) => r.headers['range']), everyElement(isNull));
    expect(target.readAsBytesSync(), bytes);
  });

  test('checked cross-mirror resume hashes the prefix as well as the suffix', () async {
    final http = fixture.ProtocolHttp((request, index) {
      if (index == 1) {
        return LiveStreamedResponse(
          status: 200,
          contentLength: 6,
          url: request.url,
          body: (() async* {
            yield bytes.sublist(0, 2);
            throw const TransportFailure('app', TransportReason.protocol, 'dropped');
          })(),
        );
      }
      return fixture.reply(
        request,
        206,
        bytes.sublist(2),
        length: 4,
        headers: {
          'content-range': ['bytes 2-5/6'],
        },
      );
    });
    await FileDownloader(http).download([mirror, source], target, integrity: identity);
    expect(http.requests.map((r) => r.headers['range']), [null, 'bytes=2-']);
    expect(target.readAsBytesSync(), bytes);
  });

  test('wrong resumed prefix is detected and origin clean retry succeeds', () async {
    final http = fixture.ProtocolHttp((request, index) {
      if (index == 1) {
        return LiveStreamedResponse(
          status: 200,
          contentLength: 6,
          url: request.url,
          body: (() async* {
            yield [9, 9];
            throw const TransportFailure('app', TransportReason.protocol, 'dropped');
          })(),
        );
      }
      return request.headers.containsKey('range')
          ? fixture.reply(
              request,
              206,
              bytes.sublist(2),
              length: 4,
              headers: {
                'content-range': ['bytes 2-5/6'],
              },
            )
          : fixture.reply(request, 200, bytes, length: 6);
    });
    await FileDownloader(http).download([mirror, source], target, integrity: identity);
    expect(http.requests.map((r) => r.headers['range']), [null, 'bytes=2-', null]);
    expect(target.readAsBytesSync(), bytes);
  });

  test('chunked body uses exact identity, not EOF as proof', () async {
    final http = fixture.ProtocolHttp((request, _) => fixture.reply(request, 200, bytes));
    await FileDownloader(http).download([source], target, integrity: identity);
    expect(target.readAsBytesSync(), bytes);
  });

  for (final body in [
    [1, 2],
    [...bytes, 7],
  ]) {
    test('short or overlong chunked body cannot promote (${body.length})', () async {
      final http = fixture.ProtocolHttp((request, _) => fixture.reply(request, 200, body));
      await expectLater(
        FileDownloader(http).download([source], target, integrity: identity),
        throwsA(isA<DownloadException>()),
      );
      expect(target.existsSync(), isFalse);
      if (FileDownloader.partOf(target).existsSync()) {
        expect(FileDownloader.partOf(target).lengthSync(), lessThanOrEqualTo(6));
      }
    });
  }

  test('right hash with wrong declared size cannot promote', () async {
    final wrong = DownloadIntegrity(canonicalUrl: source, sizeBytes: 7, sha256: identity.sha256);
    await expectLater(
      FileDownloader(validHttp()).download([source], target, integrity: wrong),
      throwsA(isA<DownloadException>()),
    );
    expect(target.existsSync(), isFalse);
  });

  test('downloader representation headers cannot be overridden; User-Agent survives', () async {
    final http = validHttp();
    await FileDownloader(http).download(
      [source],
      target,
      integrity: identity,
      headers: {'Range': 'bytes=999-', 'If-Range': 'untrusted', 'Accept-Encoding': 'gzip', 'User-Agent': 'font-client'},
    );
    final headers = http.requests.single.headers;
    expect(headers['range'], isNull);
    expect(headers['if-range'], isNull);
    expect(headers['accept-encoding'], 'identity');
    expect(headers['User-Agent'], 'font-client');
  });

  test('pre-cancelled call preserves orphan part and unrelated target', () async {
    target.writeAsBytesSync([9]);
    FileDownloader.partOf(target).writeAsBytesSync([8]);
    final http = validHttp();
    await expectLater(
      FileDownloader(http).download([source], target, integrity: identity, cancel: CancelToken()..cancel()),
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
    );
    expect(target.readAsBytesSync(), [9]);
    expect(FileDownloader.partOf(target).readAsBytesSync(), [8]);
    expect(http.requests, isEmpty);
  });

  test('mid-stream cancellation keeps a bound partial and stops retries', () async {
    final cancel = CancelToken();
    final http = fixture.ProtocolHttp(
      (request, _) => LiveStreamedResponse(
        status: 200,
        contentLength: 6,
        url: request.url,
        body: Stream.fromIterable([bytes.sublist(0, 2), bytes.sublist(2)]),
      ),
    );
    await expectLater(
      FileDownloader(http).download(
        [source, mirror],
        target,
        integrity: identity,
        cancel: cancel,
        onProgress: (received, _) {
          if (received == 2) cancel.cancel();
        },
      ),
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
    );
    expect(target.existsSync(), isFalse);
    expect(FileDownloader.partOf(target).readAsBytesSync(), bytes.sublist(0, 2));
    expect(FileDownloader.metadataOf(target).existsSync(), isTrue);
    expect(http.requests, hasLength(1));
  });

  test('cancel while waiting for headers closes a late response', () async {
    final cancel = CancelToken();
    final opened = Completer<void>();
    final response = Completer<LiveStreamedResponse>();
    var discarded = false;
    final http = fixture.ProtocolHttp((request, _) {
      opened.complete();
      return response.future;
    });
    final download = FileDownloader(http).download([source], target, integrity: identity, cancel: cancel);
    final assertion = expectLater(
      download,
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
    );
    await opened.future;
    cancel.cancel();
    await assertion;
    final body = StreamController<List<int>>(
      onCancel: () {
        discarded = true;
      },
    );
    response.complete(LiveStreamedResponse(status: 200, body: body.stream, url: source));
    await pumpEventQueue();
    expect(discarded, isTrue);
    await body.close();
    expect(target.existsSync(), isFalse);
  });

  test('cancellation simultaneous with acquired headers discards the body once', () async {
    final cancel = CancelToken();
    var discarded = 0;
    final body = StreamController<List<int>>(
      onCancel: () {
        discarded++;
      },
    );
    final http = fixture.ProtocolHttp((request, _) {
      cancel.cancel();
      return LiveStreamedResponse(status: 200, body: body.stream, url: source);
    });
    await expectLater(
      FileDownloader(http).download([source], target, integrity: identity, cancel: cancel),
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
    );
    await pumpEventQueue();
    expect(discarded, 1);
    await body.close();
    expect(target.existsSync(), isFalse);
  });

  test('cancel while waiting for body cancels subscription', () async {
    final cancel = CancelToken();
    final listened = Completer<void>();
    var discarded = false;
    final body = StreamController<List<int>>(
      onListen: listened.complete,
      onCancel: () {
        discarded = true;
      },
    );
    final http = fixture.ProtocolHttp(
      (request, _) => LiveStreamedResponse(status: 200, contentLength: 6, body: body.stream, url: source),
    );
    final assertion = expectLater(
      FileDownloader(http).download([source], target, integrity: identity, cancel: cancel),
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
    );
    await listened.future;
    cancel.cancel();
    await assertion;
    expect(discarded, isTrue);
    await body.close();
    expect(target.existsSync(), isFalse);
  });

  for (final diskError in [false, true]) {
    test('cancellation awaits body cleanup and preserves cleanup error ($diskError)', () async {
      final cancel = CancelToken();
      final listened = Completer<void>();
      final cleanup = Completer<void>();
      final controller = StreamController<List<int>>(onListen: listened.complete, onCancel: () => cleanup.future);
      final http = fixture.ProtocolHttp(
        (request, _) => LiveStreamedResponse(status: 200, contentLength: 6, body: controller.stream, url: source),
      );
      var finished = false;
      Object? failure;
      final result = FileDownloader(http)
          .download([source], target, integrity: identity, cancel: cancel)
          .then<void>(
            (_) {
              finished = true;
            },
            onError: (Object error) {
              failure = error;
              finished = true;
            },
          );
      await listened.future;
      cancel.cancel();
      await pumpEventQueue();
      expect(finished, isFalse, reason: 'must await the original cancellation future');
      if (diskError) {
        cleanup.completeError(const FileSystemException('cleanup failed'));
      } else {
        cleanup.complete();
      }
      await result;
      expect(
        failure,
        isA<DownloadException>().having(
          (e) => e.reason,
          'reason',
          diskError ? DownloadFailure.disk : DownloadFailure.cancelled,
        ),
      );
      await controller.close();
      expect(target.existsSync(), isFalse);
    });
  }

  for (final point in ['hash', 'hash-chunk', 'backup']) {
    test('cancel during $point keeps prior target and partial identity', () async {
      target.writeAsBytesSync([9]);
      final cancel = CancelToken();
      final operations = FaultOperations(cancel: cancel, cancelAt: point);
      await expectLater(
        FileDownloader(
          validHttp(),
          fileOperations: operations,
        ).download([source], target, integrity: identity, cancel: cancel),
        throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
      );
      expect(target.readAsBytesSync(), [9]);
      expect(FileDownloader.partOf(target).readAsBytesSync(), bytes);
      expect(FileDownloader.metadataOf(target).existsSync(), isTrue);
      expect(operations.operations, isNot(contains('promote')));
    });
  }

  for (final point in ['hash', 'backup']) {
    test('cancellation across delayed $point barrier is checked before commit', () async {
      target.writeAsBytesSync([9]);
      final cancel = CancelToken();
      final operations = BarrierOperations(point);
      final result = expectLater(
        FileDownloader(
          validHttp(),
          fileOperations: operations,
        ).download([source], target, integrity: identity, cancel: cancel),
        throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
      );
      await operations.entered.future;
      cancel.cancel();
      operations.release.complete();
      await result;
      expect(target.readAsBytesSync(), [9]);
      expect(FileDownloader.partOf(target).readAsBytesSync(), bytes);
      expect(FileDownloader.metadataOf(target).existsSync(), isTrue);
    });
  }

  test('cancel after verification progress but before promotion cannot return done', () async {
    target.writeAsBytesSync([9]);
    final cancel = CancelToken();
    var finishedProgress = 0;
    await expectLater(
      FileDownloader(validHttp()).download(
        [source],
        target,
        integrity: identity,
        cancel: cancel,
        onProgress: (received, _) {
          if (received == 6 && ++finishedProgress == 2) cancel.cancel();
        },
      ),
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
    );
    expect(target.readAsBytesSync(), [9]);
    expect(FileDownloader.metadataOf(target).existsSync(), isTrue);
  });

  for (final fault in [
    'exists',
    'sidecar',
    'sidecar-rename',
    'open',
    'write',
    'flush',
    'close',
    'hash',
    'backup',
    'promote',
  ]) {
    test('disk $fault failure preserves prior target and is not retried as network', () async {
      target.writeAsBytesSync([9]);
      final operations = FaultOperations(fail: fault);
      final http = validHttp();
      await expectLater(
        FileDownloader(http, fileOperations: operations).download([source, mirror], target, integrity: identity),
        throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.disk)),
      );
      expect(target.readAsBytesSync(), [9]);
      expect(http.requests.length, lessThanOrEqualTo(1));
      expect(operations.operations, contains(fault), reason: 'must reach the intended injected failure');
      if (fault == 'exists') {
        expect(operations.operations, isNot(contains('delete')));
        expect(operations.operations, isNot(contains('promote')));
      }
      if (fault == 'flush') expect(operations.operations, contains('close'));
    });
  }

  test('failed rollback retains recoverable prior bytes and reports disk failure', () async {
    target.writeAsBytesSync([9]);
    final operations = FaultOperations(fail: 'restore');
    await expectLater(
      FileDownloader(validHttp(), fileOperations: operations).download([source], target, integrity: identity),
      throwsA(
        isA<DownloadException>()
            .having((e) => e.reason, 'reason', DownloadFailure.disk)
            .having((e) => e.detail, 'detail', contains('previous target retained')),
      ),
    );
    final backup = temp.listSync().whereType<Directory>().single;
    expect(File(p.join(backup.path, 'target')).readAsBytesSync(), [9]);
    expect(target.existsSync(), isFalse, reason: 'rollback failed, recovery copy must remain');
  });

  test('one-second body gap timeout fails without promotion', () async {
    final controller = StreamController<List<int>>();
    final http = fixture.ProtocolHttp(
      (request, _) => LiveStreamedResponse(status: 200, contentLength: 6, body: controller.stream, url: source),
    );
    await expectLater(
      FileDownloader(http, gapTimeout: const Duration(seconds: 1)).download([source], target, integrity: identity),
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.network)),
    );
    await controller.close();
    expect(target.existsSync(), isFalse);
  });
}
