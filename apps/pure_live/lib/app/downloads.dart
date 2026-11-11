import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Bytes received so far and the whole size when known.
typedef DownloadProgress = void Function(int received, int? total);

/// The folder update packages go to (3.x `CacheController.resolveDownloadDirectory`):
/// the folder chosen on the cache page ([Settings.downloadDirectoryPath]),
/// else the platform default ([defaultDownloadDirectory]).
Future<Directory> resolveDownloadDirectory(SettingsStore settings, {required Directory dataRoot}) async {
  final custom = settings.get(Settings.downloadDirectoryPath).trim();
  if (custom.isNotEmpty) return Directory(custom);
  return await defaultDownloadDirectory(dataRoot: dataRoot);
}

/// The default download folder: Android's app download folder
/// (`Android/data/<package>/files/Download/pure_live`, no permission needed,
/// as 3.x), elsewhere `downloads` in the data folder (3.x's `DOWNLOADS`).
Future<Directory> defaultDownloadDirectory({required Directory dataRoot}) async {
  if (Platform.isAndroid) {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return Directory(p.join(downloads.path, 'pure_live'));
    } on Object {
      // Falls back to the data folder.
    }
  }
  return Directory(p.join(dataRoot.path, 'downloads'));
}

/// Whether [directory] exists or can be made and takes a file (3.x
/// `isCustomDownloadDirectoryUsable`; Android may leave a picked folder
/// readable but not writable).
Future<bool> canWriteDirectory(Directory directory) async {
  try {
    await directory.create(recursive: true);
    final probe = File(p.join(directory.path, '.pure_live_write_probe'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } on Object {
    return false;
  }
}

/// A file name safe on every platform from [url] or [suggested] (3.x
/// `safeDownloadFileName`).
String safeDownloadFileName(String url, {String? suggested}) {
  var name = suggested?.trim() ?? '';
  if (name.isEmpty) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    name = segments.where((segment) => segment.isNotEmpty).lastOrNull ?? '';
  }
  name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  if (name.isEmpty || name == '.' || name == '..') name = 'download';
  return name;
}

/// Why a download stopped.
enum DownloadFailure {
  /// Every source failed (network, server, bad answer).
  network,

  /// The bytes did not match the declared artifact identity.
  integrity,

  /// A file operation failed.
  disk,

  /// The user cancelled.
  cancelled,
}

/// A failed download.
final class DownloadException implements Exception {
  /// Creates the failure.
  const new(this.reason, [this.detail]);

  /// What went wrong.
  final DownloadFailure reason;

  /// Diagnostic detail.
  final String? detail;

  @override
  String toString() => 'DownloadException(${reason.name}${detail == null ? '' : ': $detail'})';
}

/// Exact identity from one release snapshot, not from a transport mirror.
///
/// A matching digest establishes byte coherence, not publisher authenticity.
final class DownloadIntegrity {
  /// Validates an identity. No display-size strings or rounded numbers are used.
  factory({
    required Uri canonicalUrl,
    required int sizeBytes,
    required String sha256,
    String? version,
    int? buildNumber,
  }) {
    if (canonicalUrl.scheme != 'https' ||
        canonicalUrl.host.isEmpty ||
        sizeBytes <= 0 ||
        sizeBytes > _maxExactInteger ||
        !_digestPattern.hasMatch(sha256) ||
        sha256.length != 64 ||
        (buildNumber != null && (buildNumber <= 0 || buildNumber > _maxExactInteger))) {
      throw ArgumentError('Invalid download identity');
    }
    return DownloadIntegrity._(canonicalUrl, sizeBytes, sha256.toLowerCase(), version, buildNumber);
  }

  const new _(this.canonicalUrl, this.sizeBytes, this.sha256, this.version, this.buildNumber);

  /// Original release URL, including its query; never the fastest mirror.
  final Uri canonicalUrl;

  /// Exact representation size.
  final int sizeBytes;

  /// Normalized SHA-256 of the final packaged bytes.
  final String sha256;

  /// Version selected by the update snapshot.
  final String? version;

  /// Build selected by the update snapshot.
  final int? buildNumber;

  Map<String, Object?> get _metadata => {
    'schema': 1,
    'url': canonicalUrl.toString(),
    'size_bytes': sizeBytes,
    'sha256': sha256,
    'version': version,
    'build_number': buildNumber,
  };
}

const _maxExactInteger = 9007199254740991;
final _digestPattern = RegExp(r'^[a-fA-F0-9]{64}$');

/// File operations used by downloads; injectable for deterministic disk faults.
class DownloadFileOperations {
  /// Uses the local filesystem.
  const new();

  /// Creates the destination directory.
  Future<void> createDirectory(Directory directory) => directory.create(recursive: true);

  /// Whether a file exists.
  // Keep lookup errors distinct from absence without blocking the UI thread.
  // ignore: avoid_slow_async_io
  Future<bool> exists(File file) => file.exists();

  /// Exact current file length.
  Future<int> length(File file) => file.length();

  /// Reads the small identity sidecar.
  Future<String> readText(File file) => file.readAsString();

  /// Writes and flushes a new identity sidecar.
  Future<void> writeText(File file, String text) => file.writeAsString(text, flush: true);

  /// Opens a partial for full replacement or append.
  Future<RandomAccessFile> open(File file, FileMode mode) => file.open(mode: mode);

  /// Writes a chunk, awaiting disk errors before requesting another chunk.
  Future<void> write(RandomAccessFile file, List<int> bytes) => file.writeFrom(bytes);

  /// Flushes all downloaded bytes before verification.
  Future<void> flush(RandomAccessFile file) => file.flush();

  /// Closes the partial even if a flush fails.
  Future<void> close(RandomAccessFile file) => file.close();

  /// Streams the whole partial, including a resumed prefix, for verification.
  Stream<List<int>> read(File file) => file.openRead();

  /// Moves a file within its destination directory.
  Future<File> rename(File file, String path) => file.rename(path);

  /// Copies a prior valid target for bounded rollback.
  Future<File> copy(File file, String path) => file.copy(path);

  /// Removes only a downloader-owned file.
  Future<void> delete(File file) => file.delete();

  /// Allocates a unique, same-directory recovery location.
  Future<Directory> backupDirectory(File target) => target.parent.createTemp('${p.basename(target.path)}.previous-');

  /// Removes a successfully recovered or committed backup directory.
  Future<void> deleteDirectory(Directory directory) => directory.delete(recursive: true);
}

/// Downloads one file with strict HTTP framing and bounded retries.
///
/// Installer partials are bound to [DownloadIntegrity] by a versioned sidecar.
/// They may resume across mirrors only because the entire file is hashed before
/// promotion. Generic callers (fonts) start fresh on every source/invocation:
/// without an exact identity, neither a filename nor an ETag proves equivalence.
final class FileDownloader {
  /// Creates a downloader over [http].
  new(
    this.http, {
    this.site = 'app',
    this.gapTimeout = const Duration(seconds: 30),
    this.fileOperations = const DownloadFileOperations(),
  });

  /// Transport (the app's client, so the app proxy applies).
  final LiveHttp http;

  /// The request's site id (proxy route and throttle).
  final String site;

  /// Longest wait for the headers and between chunks.
  final Duration gapTimeout;

  /// Disk operations; defaults to the local filesystem.
  final DownloadFileOperations fileOperations;

  /// The unfinished part of [target].
  static File partOf(File target) => File('${target.path}.part');

  /// Versioned identity of the unfinished part; old orphan parts are not trusted.
  static File metadataOf(File target) => File('${target.path}.part.meta');

  // Successful-only tails serialize one lexical target across downloader
  // instances in this isolate. This is not a cross-process or symlink lock.
  static final Map<String, Future<void>> _targetOwners = {};

  /// Returns [target] only after complete framing and, when supplied, integrity
  /// verification. Each unique source gets at most one clean protocol retry.
  /// Cancellation before promotion keeps a bound part, never returns success.
  /// A queued cancellation waits for its predecessor to settle, then performs
  /// no file or network work. Different normalized absolute targets may proceed.
  Future<File> download(
    List<Uri> sources,
    File target, {
    DownloadProgress? onProgress,
    CancelToken? cancel,
    Map<String, String> headers = const {},
    DownloadIntegrity? integrity,
  }) async {
    _checkCancelled(cancel);
    if (sources.isEmpty) throw const DownloadException(DownloadFailure.network, 'no source');
    final absolute = p.normalize(target.absolute.path);
    // Conservatively fold Windows casing for ordinary case-insensitive targets.
    final key = Platform.isWindows ? absolute.toLowerCase() : absolute;
    final previous = _targetOwners[key];
    final released = Completer<void>();
    final tail = released.future;
    _targetOwners[key] = tail;
    try {
      if (previous != null) await previous;
      _checkCancelled(cancel);
      return await _download(
        sources,
        target,
        onProgress: onProgress,
        cancel: cancel,
        headers: headers,
        integrity: integrity,
      );
    } finally {
      // Always settle successfully: the caller observes its own failure, and a
      // failed/cancelled predecessor must neither poison nor bypass successors.
      released.complete();
      if (identical(_targetOwners[key], tail)) unawaited(_targetOwners.remove(key));
    }
  }

  Future<File> _download(
    List<Uri> sources,
    File target, {
    required DownloadProgress? onProgress,
    required CancelToken? cancel,
    required Map<String, String> headers,
    required DownloadIntegrity? integrity,
  }) async {
    final part = partOf(target);
    final metadata = metadataOf(target);
    Object? lastError;
    var integrityFailed = false;
    try {
      await fileOperations.createDirectory(target.parent);
      for (final source in sources.toSet()) {
        for (var attempt = 0; attempt < 2; attempt++) {
          _checkCancelled(cancel);
          try {
            await _prepare(part, metadata, integrity);
            _checkCancelled(cancel);
            final complete =
                integrity != null &&
                await fileOperations.exists(part) &&
                await fileOperations.length(part) == integrity.sizeBytes;
            if (!complete) {
              await _fetch(
                source,
                part,
                integrity: integrity,
                headers: headers,
                onProgress: onProgress,
                cancel: cancel,
              );
            }
            _checkCancelled(cancel);
            if (integrity != null) await _verify(part, integrity, cancel);
            _checkCancelled(cancel);
            if (integrity != null) onProgress?.call(integrity.sizeBytes, integrity.sizeBytes);
            _checkCancelled(cancel);
            return await _promote(part, metadata, target, cancel);
          } on _InvalidDownload catch (error) {
            lastError = error;
            integrityFailed = integrityFailed || integrity != null;
            await _reset(part, metadata);
            // One reset/full retry, then the next source. Never loop forever.
          } on DownloadException catch (error) {
            if (error.reason != DownloadFailure.network) rethrow;
            lastError = error;
            break;
          } on TransportFailure catch (error) {
            _checkCancelled(cancel);
            if (error.reason == TransportReason.cancelled) {
              throw const DownloadException(DownloadFailure.cancelled);
            }
            lastError = error;
            break;
          } on TimeoutException catch (error) {
            _checkCancelled(cancel);
            lastError = error;
            break;
          }
        }
      }
    } on FileSystemException catch (error) {
      throw DownloadException(DownloadFailure.disk, error.message);
    }
    _checkCancelled(cancel);
    throw DownloadException(integrityFailed ? DownloadFailure.integrity : DownloadFailure.network, '$lastError');
  }

  Future<void> _prepare(File part, File metadata, DownloadIntegrity? integrity) async {
    var matches = false;
    if (integrity != null && await fileOperations.exists(metadata) && await fileOperations.exists(part)) {
      try {
        final decoded = jsonDecode(await fileOperations.readText(metadata));
        final expected = integrity._metadata;
        matches =
            decoded is Map<String, dynamic> &&
            decoded.length == expected.length &&
            decoded['schema'] is int &&
            decoded['size_bytes'] is int &&
            (decoded['build_number'] == null || decoded['build_number'] is int) &&
            expected.entries.every((entry) => decoded[entry.key] == entry.value) &&
            await fileOperations.length(part) <= integrity.sizeBytes;
      } on FormatException {
        // A corrupt sidecar can lose resumability, never gain unverified success.
      }
    }
    if (matches) return;
    await _reset(part, metadata);
    if (integrity != null) {
      final temporary = File('${metadata.path}.tmp');
      await fileOperations.writeText(temporary, jsonEncode(integrity._metadata));
      await fileOperations.rename(temporary, metadata.path);
    }
  }

  Future<void> _reset(File part, File metadata) async {
    for (final file in [part, metadata, File('${metadata.path}.tmp')]) {
      if (await fileOperations.exists(file)) await fileOperations.delete(file);
    }
  }

  Future<void> _verify(File part, DownloadIntegrity integrity, CancelToken? cancel) async {
    _checkCancelled(cancel);
    if (await fileOperations.length(part) != integrity.sizeBytes) {
      throw const _InvalidDownload('size mismatch');
    }
    final digest = await crypto.sha256.bind(_checkedChunks(fileOperations.read(part), cancel)).first;
    _checkCancelled(cancel);
    if (digest.toString() != integrity.sha256) throw const _InvalidDownload('SHA-256 mismatch');
  }

  Future<File> _promote(File part, File metadata, File target, CancelToken? cancel) async {
    _checkCancelled(cancel);
    Directory? recovery;
    File? backup;
    try {
      if (await fileOperations.exists(target)) {
        recovery = await fileOperations.backupDirectory(target);
        backup = await fileOperations.copy(target, p.join(recovery.path, 'target'));
      }
      _checkCancelled(cancel);
      try {
        // Entering rename is the commit boundary: the filesystem operation
        // cannot be interrupted by a later cancellation. The same-directory
        // backup protects replacements that first remove the old destination.
        final promoted = await fileOperations.rename(part, target.path);
        try {
          if (await fileOperations.exists(metadata)) await fileOperations.delete(metadata);
        } on FileSystemException {
          // The rename committed. An orphan sidecar cannot bind a missing part;
          // report success rather than hide a complete verified replacement.
        }
        return promoted;
      } on FileSystemException catch (error) {
        if (backup != null) {
          try {
            await fileOperations.copy(backup, target.path);
          } on FileSystemException {
            final saved = backup.path;
            recovery = null; // Retain the old bytes if rollback itself fails.
            throw FileSystemException('${error.message}; previous target retained at $saved', target.path);
          }
        }
        rethrow;
      }
    } finally {
      if (recovery != null) {
        try {
          await fileOperations.deleteDirectory(recovery);
        } on FileSystemException {
          // Backup cleanup is post-commit/best effort; it must not turn a valid
          // replacement into a reported failure or erase a recovery copy.
        }
      }
    }
  }

  Future<void> _fetch(
    Uri source,
    File part, {
    required DownloadIntegrity? integrity,
    required Map<String, String> headers,
    required DownloadProgress? onProgress,
    required CancelToken? cancel,
  }) async {
    final have = await fileOperations.exists(part) ? await fileOperations.length(part) : 0;
    _checkCancelled(cancel);
    final requestHeaders = <String, String>{
      for (final entry in headers.entries)
        if (!const {'range', 'if-range', 'accept-encoding', 'cache-control'}.contains(entry.key.toLowerCase()))
          entry.key: entry.value,
      'cache-control': 'no-cache',
      'accept-encoding': 'identity',
      if (have > 0) 'range': 'bytes=$have-',
    };
    final response = await _open(
      LiveRequest(site: site, url: source, headers: requestHeaders, timeout: gapTimeout, cancel: cancel),
      cancel,
    );
    var subscribed = false;
    try {
      _checkCancelled(cancel);
      final encoding = _header(response, 'content-encoding');
      if (encoding != null && encoding.toLowerCase() != 'identity') {
        throw const _InvalidDownload('unexpected content encoding');
      }
      final contentLength = _contentLength(response);
      var received = 0;
      int? total;
      var mode = FileMode.write;
      if (response.status == 200) {
        total = integrity?.sizeBytes ?? contentLength;
        if (integrity != null && contentLength != null && contentLength != integrity.sizeBytes) {
          throw const _InvalidDownload('Content-Length differs from artifact');
        }
      } else if (response.status == 206) {
        final value = _header(response, 'content-range') ?? '';
        final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value);
        if (match == null || match.end != value.length) throw const _InvalidDownload('invalid Content-Range');
        final start = _number(match.group(1)!);
        final end = _number(match.group(2)!);
        total = _number(match.group(3)!);
        if (start != have ||
            total == 0 ||
            end < start ||
            end != total - 1 ||
            (integrity != null && total != integrity.sizeBytes) ||
            (contentLength != null && contentLength != end - start + 1) ||
            (_header(response, 'content-type') ?? '').toLowerCase().startsWith('multipart/')) {
          throw const _InvalidDownload('unexpected range');
        }
        received = have;
        mode = have == 0 ? FileMode.write : FileMode.append;
      } else if (response.status == 416) {
        // Complete bound parts were already rehashed before opening HTTP. No
        // server response can turn an incomplete/unbound local part into one.
        throw const _InvalidDownload('range not satisfiable');
      } else if (response.isSuccess) {
        throw const _InvalidDownload('unsupported success status');
      } else {
        throw DownloadException(DownloadFailure.network, 'HTTP ${response.status}');
      }
      onProgress?.call(received, total);
      _checkCancelled(cancel);
      final file = await fileOperations.open(part, mode);
      try {
        subscribed = true;
        await for (final chunk in _checkedChunks(response.body, cancel, timeout: gapTimeout)) {
          if (total != null && chunk.length > total - received) {
            throw const _InvalidDownload('overlong body');
          }
          await fileOperations.write(file, chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await fileOperations.flush(file);
      } finally {
        await fileOperations.close(file);
      }
      _checkCancelled(cancel);
      if (received == 0) throw const _InvalidDownload('empty body');
      if (total != null && received != total) {
        throw DownloadException(DownloadFailure.network, 'short body $received/$total');
      }
    } finally {
      if (!subscribed) await response.discard();
    }
  }

  Future<LiveStreamedResponse> _open(LiveRequest request, CancelToken? cancel) async {
    var abandoned = false;
    var discarded = false;
    LiveStreamedResponse? acquired;
    Future<void> discardAcquired() async {
      final response = acquired;
      if (response == null || discarded) return;
      discarded = true;
      await response.discard();
    }

    final pending = http.open(request).then((response) async {
      acquired = response;
      if (abandoned) await discardAcquired();
      return response;
    });
    try {
      return await _cancellable(pending.timeout(gapTimeout), cancel);
    } on Object {
      abandoned = true;
      await discardAcquired();
      rethrow;
    }
  }
}

void _checkCancelled(CancelToken? cancel) {
  if (cancel?.isCancelled ?? false) throw const DownloadException(DownloadFailure.cancelled);
}

Future<T> _cancellable<T>(Future<T> future, CancelToken? cancel) => cancel == null
    ? future
    : Future.any([
        future,
        cancel.whenCancelled.then<T>((_) => throw const DownloadException(DownloadFailure.cancelled)),
      ]);

Stream<List<int>> _checkedChunks(Stream<List<int>> stream, CancelToken? cancel, {Duration? timeout}) async* {
  final iterator = StreamIterator(stream);
  var active = true;
  Future<void>? stopping;
  Future<void> stop() => stopping ??= iterator.cancel();
  // One cancellation listener per stream, not one retained future per chunk.
  if (cancel != null) {
    unawaited(
      cancel.whenCancelled.then((_) async {
        if (!active) return;
        try {
          await stop();
        } on Object {
          // The same memoized future is awaited below to observe cleanup errors.
        }
      }),
    );
  }
  try {
    while (true) {
      _checkCancelled(cancel);
      final next = iterator.moveNext();
      final hasNext = await (timeout == null ? next : next.timeout(timeout));
      _checkCancelled(cancel);
      if (!hasNext) break;
      yield iterator.current;
    }
  } finally {
    active = false;
    await stop();
  }
}

String? _header(LiveStreamedResponse response, String name) {
  final values = [
    for (final entry in response.headers.entries)
      if (entry.key.toLowerCase() == name) ...entry.value,
  ];
  if (values.length > 1) throw _InvalidDownload('repeated $name');
  return values.firstOrNull;
}

int _number(String value) {
  if (value.isEmpty || RegExp('[^0-9]').hasMatch(value)) throw const _InvalidDownload('invalid length');
  final result = int.tryParse(value);
  if (result == null || result < 0 || result > _maxExactInteger) throw const _InvalidDownload('length overflow');
  return result;
}

int? _contentLength(LiveStreamedResponse response) {
  final header = _header(response, 'content-length');
  final length = header == null ? response.contentLength : _number(header);
  if (length != null &&
      (length < 0 ||
          length > _maxExactInteger ||
          (response.contentLength != null && length != response.contentLength))) {
    throw const _InvalidDownload('conflicting Content-Length');
  }
  return length;
}

final class _InvalidDownload implements Exception {
  const new(this.detail);
  final String detail;
  @override
  String toString() => detail;
}
