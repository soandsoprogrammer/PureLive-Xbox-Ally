import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/downloads.dart';

import 'download_protocol_regression_test.dart' as fixture;

class _TracedOperations extends DownloadFileOperations {
  new(this.label, this.trace);
  final String label;
  final List<String> trace;
  bool started = false;

  @override
  Future<void> createDirectory(Directory directory) async {
    started = true;
    trace.add('$label:first');
    await super.createDirectory(directory);
  }
}

final class _HeldWriteOperations extends _TracedOperations {
  new(super.label, super.trace, {this.fail = false});
  final bool fail;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(RandomAccessFile file, List<int> bytes) async {
    entered.complete();
    await release.future;
    if (fail) throw const FileSystemException('injected held write failure');
    await super.write(file, bytes);
  }

  @override
  Future<void> close(RandomAccessFile file) async {
    await super.close(file);
    trace.add('$label:closed');
  }
}

void main() {
  test('cancel and reopen cannot let a held old write corrupt a newly verified target', () async {
    final folder = Directory.systemTemp.createTempSync('download_owner_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final target = File(p.join(folder.path, 'pkg.apk'))..writeAsBytesSync([8]);
    final source = Uri.parse('https://origin.example/pkg.apk');
    const good = [1, 2, 3, 4, 5, 6];
    final identity = DownloadIntegrity(
      canonicalUrl: source,
      sizeBytes: good.length,
      sha256: crypto.sha256.convert(good).toString(),
    );
    fixture.ProtocolHttp http(List<int> bytes) =>
        fixture.ProtocolHttp((request, _) => fixture.reply(request, 200, bytes, length: good.length));
    final trace = <String>[];
    final held = _HeldWriteOperations('old', trace);
    final cancel = CancelToken();
    final old = FileDownloader(
      http([9, 9]),
      fileOperations: held,
    ).download([source], target, integrity: identity, cancel: cancel);
    final oldStopped = expectLater(
      old,
      throwsA(isA<DownloadException>().having((error) => error.reason, 'reason', DownloadFailure.cancelled)),
    );
    await held.entered.future.timeout(const Duration(seconds: 5));
    cancel.cancel();
    final nextOperations = _TracedOperations('next', trace);
    final nextHttp = http(good);
    final next = FileDownloader(
      nextHttp,
      fileOperations: nextOperations,
    ).download([source], File(target.path), integrity: identity);
    late bool overlapped;
    try {
      // A different target completes while the first write is held. This is a
      // progress handshake, not an arbitrary delay or a global download lock.
      await FileDownloader(http(good)).download([source], File(p.join(folder.path, 'other.apk')), integrity: identity);
      overlapped = nextOperations.started;
      if (overlapped) await next; // Expose the old open handle's post-rename write.
    } finally {
      held.release.complete();
      await oldStopped;
      await next;
    }
    expect(target.readAsBytesSync(), good, reason: 'a cancelled old handle must not modify verified replacement bytes');
    expect(overlapped, isFalse, reason: 'the next owner must not touch the target before old I/O settles');
    expect(trace, containsAll(['old:closed', 'next:first']));
    expect(trace.indexOf('old:closed'), lessThan(trace.indexOf('next:first')));
    expect(nextHttp.requests, hasLength(1));
  });

  test('cancelled queued owner cannot let a third caller bypass a held predecessor', () async {
    final folder = Directory.systemTemp.createTempSync('download_waiters_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final target = File(p.join(folder.path, 'pkg.apk'));
    final source = Uri.parse('https://origin.example/pkg.apk');
    const bytes = [1, 2, 3];
    final identity = DownloadIntegrity(
      canonicalUrl: source,
      sizeBytes: 3,
      sha256: crypto.sha256.convert(bytes).toString(),
    );
    fixture.ProtocolHttp http() => fixture.ProtocolHttp((request, _) => fixture.reply(request, 200, bytes, length: 3));
    final trace = <String>[];
    final held = _HeldWriteOperations('old', trace);
    final oldCancel = CancelToken();
    final old = FileDownloader(
      http(),
      fileOperations: held,
    ).download([source], target, integrity: identity, cancel: oldCancel);
    final oldStopped = expectLater(
      old,
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
    );
    await held.entered.future.timeout(const Duration(seconds: 5));
    oldCancel.cancel();
    final waitingOps = _TracedOperations('waiting', trace);
    final waitingHttp = http();
    final waitingCancel = CancelToken();
    var waitingSettled = false;
    final waiting = FileDownloader(waitingHttp, fileOperations: waitingOps)
        .download([source], File('${folder.path}/./pkg.apk'), integrity: identity, cancel: waitingCancel)
        .whenComplete(() => waitingSettled = true);
    final waitingStopped = expectLater(
      waiting,
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.cancelled)),
    );
    waitingCancel.cancel();
    final thirdOps = _TracedOperations('third', trace);
    final third = FileDownloader(http(), fileOperations: thirdOps).download([source], target, integrity: identity);
    late bool bypassed;
    try {
      await FileDownloader(http()).download([source], File(p.join(folder.path, 'other.apk')), integrity: identity);
      bypassed = waitingSettled || waitingOps.started || thirdOps.started;
    } finally {
      held.release.complete();
      await oldStopped;
      await waitingStopped;
      await third;
    }
    expect(bypassed, isFalse);
    expect(waitingOps.started, isFalse);
    expect(waitingHttp.requests, isEmpty);
    expect(trace, containsAll(['old:closed', 'third:first']));
    expect(trace.indexOf('old:closed'), lessThan(trace.indexOf('third:first')));
    expect(target.readAsBytesSync(), bytes);
  });

  test('failed predecessor releases its target without poisoning the next owner', () async {
    final folder = Directory.systemTemp.createTempSync('download_failed_owner_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final target = File(p.join(folder.path, 'pkg.apk'))..writeAsBytesSync([8]);
    final source = Uri.parse('https://origin.example/pkg.apk');
    const bytes = [1, 2, 3];
    final identity = DownloadIntegrity(
      canonicalUrl: source,
      sizeBytes: 3,
      sha256: crypto.sha256.convert(bytes).toString(),
    );
    fixture.ProtocolHttp http() => fixture.ProtocolHttp((request, _) => fixture.reply(request, 200, bytes, length: 3));
    final trace = <String>[];
    final held = _HeldWriteOperations('failed', trace, fail: true);
    final failed = FileDownloader(http(), fileOperations: held).download([source], target, integrity: identity);
    final failure = expectLater(
      failed,
      throwsA(isA<DownloadException>().having((e) => e.reason, 'reason', DownloadFailure.disk)),
    );
    await held.entered.future.timeout(const Duration(seconds: 5));
    final nextOps = _TracedOperations('next', trace);
    final next = FileDownloader(http(), fileOperations: nextOps).download([source], target, integrity: identity);
    late bool overlapped;
    try {
      await FileDownloader(http()).download([source], File(p.join(folder.path, 'other.apk')), integrity: identity);
      overlapped = nextOps.started;
      expect(target.readAsBytesSync(), [8]);
    } finally {
      held.release.complete();
      await failure;
      await next;
    }
    expect(overlapped, isFalse);
    expect(trace, containsAll(['failed:closed', 'next:first']));
    expect(trace.indexOf('failed:closed'), lessThan(trace.indexOf('next:first')));
    expect(target.readAsBytesSync(), bytes);
    // A subsequent caller also proves that the settled tail is not poisoned.
    await FileDownloader(http()).download([source], target, integrity: identity);
    expect(target.readAsBytesSync(), bytes);
  });
}
