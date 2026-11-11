import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/downloads.dart';

// These tests intentionally use only the pre-Y02.3 download API so baseline
// failures demonstrate behavior, not missing new types or arguments.
final class ProtocolHttp implements LiveHttp {
  new(this.answer);
  final FutureOr<LiveStreamedResponse> Function(LiveRequest, int) answer;
  final List<LiveRequest> requests = [];
  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    requests.add(request);
    return await answer(request, requests.length);
  }

  @override
  Future<LiveResponse> send(LiveRequest request) async => await (await open(request)).collect();
  @override
  void close() {}
}

LiveStreamedResponse reply(
  LiveRequest request,
  int status,
  List<int> bytes, {
  int? length,
  Map<String, List<String>> headers = const {},
}) => LiveStreamedResponse(
  status: status,
  body: Stream.value(bytes),
  url: request.url,
  contentLength: length,
  headers: headers,
);

void main() {
  late Directory temp;
  late File target;
  final source = Uri.parse('https://origin.example/pkg.apk');
  setUp(() {
    temp = Directory.systemTemp.createTempSync('download_protocol_');
    target = File(p.join(temp.path, 'pkg.apk'));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  for (final range in [null, 'bytes */99']) {
    test('nonempty orphan plus 416 ($range) cannot be promoted', () async {
      FileDownloader.partOf(target).writeAsBytesSync([1, 2]);
      final http = ProtocolHttp(
        (request, _) => reply(
          request,
          416,
          [],
          headers: {
            if (range != null) 'content-range': [range],
          },
        ),
      );
      await expectLater(FileDownloader(http).download([source], target), throwsA(isA<DownloadException>()));
      expect(target.existsSync(), isFalse);
    });
  }

  test('200 body longer than Content-Length cannot replace prior target', () async {
    target.writeAsBytesSync([9]);
    final http = ProtocolHttp((request, _) => reply(request, 200, [1, 2, 3, 4], length: 3));
    await expectLater(FileDownloader(http).download([source], target), throwsA(isA<DownloadException>()));
    expect(target.readAsBytesSync(), [9]);
  });

  for (final status in [200, 204]) {
    test('empty $status cannot be promoted', () async {
      final http = ProtocolHttp((request, _) => reply(request, status, [], length: 0));
      await expectLater(FileDownloader(http).download([source], target), throwsA(isA<DownloadException>()));
      expect(target.existsSync(), isFalse);
    });
  }

  test('206 mismatching end/span is not a complete file', () async {
    final http = ProtocolHttp(
      (request, _) => reply(
        request,
        206,
        [1, 2, 3, 4],
        length: 4,
        headers: {
          'content-range': ['bytes 0-1/4'],
        },
      ),
    );
    await expectLater(FileDownloader(http).download([source], target), throwsA(isA<DownloadException>()));
    expect(target.existsSync(), isFalse);
  });

  test('206 matching start but conflicting span cannot append', () async {
    final http = ProtocolHttp((request, index) {
      if (index == 1) {
        return LiveStreamedResponse(
          status: 200,
          contentLength: 4,
          url: request.url,
          body: (() async* {
            yield [1, 2];
            throw const TransportFailure('app', TransportReason.protocol, 'dropped');
          })(),
        );
      }
      return reply(
        request,
        206,
        [3, 4],
        length: 2,
        headers: {
          'content-range': ['bytes 2-2/4'],
        },
      );
    });
    await expectLater(
      FileDownloader(http).download([source, Uri.parse('https://mirror.example/pkg.apk')], target),
      throwsA(isA<DownloadException>()),
    );
    expect(target.existsSync(), isFalse);
  });

  test('generic cross-mirror transfer restarts rather than mixing objects', () async {
    final http = ProtocolHttp((request, index) {
      if (index == 1) {
        return LiveStreamedResponse(
          status: 200,
          contentLength: 4,
          url: request.url,
          body: (() async* {
            yield [1, 1];
            throw const TransportFailure('app', TransportReason.protocol, 'dropped');
          })(),
        );
      }
      return request.headers.containsKey('range')
          ? reply(
              request,
              206,
              [2, 2],
              length: 2,
              headers: {
                'content-range': ['bytes 2-3/4'],
              },
            )
          : reply(request, 200, [2, 2, 2, 2], length: 4);
    });
    await FileDownloader(http).download([source, Uri.parse('https://mirror.example/pkg.apk')], target);
    expect(target.readAsBytesSync(), [2, 2, 2, 2]);
    expect(http.requests.last.headers['range'], isNull);
  });

  test('short 200 remains a rejected existing passing regression', () async {
    final http = ProtocolHttp((request, _) => reply(request, 200, [1, 2], length: 4));
    await expectLater(FileDownloader(http).download([source], target), throwsA(isA<DownloadException>()));
    expect(target.existsSync(), isFalse);
  });
}
