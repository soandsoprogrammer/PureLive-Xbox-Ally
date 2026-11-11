import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The repository the update files are read from (3.x `AppConfig`). From
/// 5.0.0 the app lives in its own repository; the old fork (`wzgrx/pure_live`)
/// keeps its update files pointing here, so 3.x and 4.x still find 5.x.
const GitHubMirror updateRepository = GitHubMirror(owner: 'wzgrx', repo: 'PureLive');

/// The project page (3.x `VersionUtil.projectUrl`).
final Uri projectUrl = Uri.parse('https://github.com/${updateRepository.owner}/${updateRepository.repo}');

/// The newer version the start-up check or the version page last found;
/// null when there is none or nothing was checked. The about page shows it
/// as "新版本 v…" (docs/A-界面设计/A15-小页面/A15.2-关于和版本 c3).
final ValueNotifier<UpdateInfo?> foundUpdate = ValueNotifier<UpdateInfo?>(null);

/// The version of [info] as shown: with its build when the version is the
/// installed one (`4.0.0（构建号 5002）`, Y02.1).
String updateVersionLabel(UpdateInfo info) => info.sameVersion(appVersion)
    ? i18n('version_with_build', args: {'version': info.version, 'build': '${info.buildNumber}'})
    : info.version;

/// Keeps [info] in [foundUpdate] when it is newer, clears it otherwise.
void noteCheckedUpdate(UpdateInfo info) => foundUpdate.value = info.isNewer ? info : null;

/// The Android ABIs 3.x builds (3.x `AppConsts.supportAndroidAbis`).
const Set<String> supportedAndroidAbis = {'arm64-v8a', 'armeabi-v7a', 'x86_64'};

/// The newest version for this platform, from the repository's
/// `assets/version.json` (3.x `VersionUtil._applyVersionData`; the file's
/// format is shared with the installed 3.x apps and must not change).
final class UpdateInfo {
  /// Creates the information.
  const new({
    required this.version,
    required this.buildNumber,
    this.log = '',
    this.prerelease = false,
    this.releaseUrl = '',
    this.androidAbis = const {'arm64-v8a'},
    this.windowsMsixAvailable = false,
  });

  /// Reads `version.json`: the top level, overridden by `platforms.<platform>`.
  /// Throws [FormatException] without a version or a positive build number.
  factory fromJson(Map<String, Object?> json, {required String platform}) {
    final platforms = json['platforms'];
    final own = platforms is Map ? platforms[platform] : null;
    final data = {...json, if (own is Map) ...own.cast<String, Object?>()};
    final version = data['version']?.toString().trim() ?? '';
    final build = _positiveInt(data['build_number']);
    if (versionParts(version) == null || build == null || build <= 0) {
      throw const FormatException('Incomplete release identity');
    }
    final abis = data['android_abis'];
    return UpdateInfo(
      version: version,
      buildNumber: build,
      log: data['version_desc']?.toString() ?? '',
      prerelease: data['prerelease'] == true,
      releaseUrl: data['download_url']?.toString() ?? '',
      androidAbis: abis is List
          ? Set.unmodifiable({for (final abi in abis) abi.toString()}.intersection(supportedAndroidAbis))
          : const {'arm64-v8a'},
      windowsMsixAvailable: data['windows_msix_available'] == true,
    );
  }

  /// Version name.
  final String version;

  /// Build number.
  final int buildNumber;

  /// What changed (Markdown).
  final String log;

  /// Whether it is a pre-release.
  final bool prerelease;

  /// The release page.
  final String releaseUrl;

  /// The Android ABIs this release has packages for.
  final Set<String> androidAbis;

  /// Whether this release has a Windows MSIX package.
  final bool windowsMsixAvailable;

  /// Whether it is newer than the installed version.
  bool get isNewer => newerThan(appVersion, appBuild);

  /// A newer identity with a monotonically higher installer build.
  /// PROCESS section 11 requires both to advance for every new package.
  bool get isInstallableUpdate => isNewer && buildNumber > appBuild;

  /// Whether it is newer than [installed] built as [build]: a newer version,
  /// or the same version with a newer build (Y02.1: 4.0.0 was re-released as
  /// build 5001, which the version alone never offered).
  bool newerThan(String installed, int build) =>
      isNewerVersion(version, installed) || (sameVersion(installed) && buildNumber > build);

  /// Whether this release is older than [installed] built as [build].
  bool olderThan(String installed, int build) =>
      isNewerVersion(installed, version) || (sameVersion(installed) && buildNumber < build);

  /// Whether [other] names the same version (a `v` and a `+build` aside).
  bool sameVersion(String other) =>
      versionParts(version) != null &&
      versionParts(other) != null &&
      !isNewerVersion(version, other) &&
      !isNewerVersion(other, version);

  /// What "不再提醒这个版本" keeps: the version and its build (`4.0.0+5002`).
  String get skipToken => '${version.replaceFirst(RegExp('^[vV]'), '')}+$buildNumber';

  /// Whether [skipped] (`skippedUpdateVersion`) is this release: its version
  /// and build, or, as kept before builds counted, its version alone.
  bool skippedAs(String skipped) {
    final value = skipped.trim();
    if (value.isEmpty) return false;
    if (!value.contains('+')) return sameVersion(value);
    final build = int.tryParse(value.split('+').last.trim());
    return sameVersion(value) && build == buildNumber;
  }
}

/// One downloadable file of a release.
final class ReleaseFile {
  /// Creates the file.
  const new({
    required this.name,
    required this.size,
    required this.downloads,
    required this.url,
    this.sizeBytes,
    this.sha256,
    this.integrityMalformed = false,
  });

  /// Reads one entry of `files` (or GitHub's `assets`).
  factory fromJson(Map<String, Object?> json) {
    final present = json.containsKey('size_bytes') || json.containsKey('sha256');
    final bytes = _exactPositiveInt(json['size_bytes']);
    final digest = _sha256(json['sha256']);
    return ReleaseFile(
      name: _string(json['name']),
      size: _size(json['size']),
      downloads: _int(json['downloads'] ?? json['downloadCount']) ?? 0,
      url: _string(json['url'] ?? json['browser_download_url']),
      sizeBytes: bytes,
      sha256: digest,
      integrityMalformed: present && (bytes == null || digest == null),
    );
  }

  /// File name.
  final String name;

  /// Size as shown (`137.77mb`).
  final String size;

  /// Download count.
  final int downloads;

  /// Download address; this is the canonical identity, not a selected mirror.
  final String url;

  /// Exact final artifact bytes, never derived from the rounded display size.
  final int? sizeBytes;

  /// SHA-256 of the complete final artifact, normalized by the feed parser.
  final String? sha256;

  /// Explicit but incomplete or malformed metadata must not become legacy mode.
  final bool integrityMalformed;

  /// Whether metadata declares a complete, strictly valid byte identity.
  bool get hasIntegrity => !integrityMalformed && _exactPositiveInt(sizeBytes) != null && _sha256(sha256) != null;

  /// Whether fields were supplied but do not form a valid byte identity.
  bool get hasInvalidIntegrity => integrityMalformed || ((sizeBytes != null || sha256 != null) && !hasIntegrity);
}

/// Whether [file] identifies the exact version and build being offered.
/// Current release packages on every platform include both in their name.
/// Older ambiguous names remain available in the explicit release history.
bool fileMatchesUpdate(UpdateInfo info, ReleaseFile file) {
  final version = info.version.trim().replaceFirst(RegExp('^[vV]'), '');
  final match = RegExp('^PureLive-${RegExp.escape(version)}-(\\d+)-').firstMatch(file.name);
  final uri = updateDownloadUri(file.url);
  return !file.hasInvalidIntegrity &&
      match != null &&
      int.tryParse(match.group(1)!) == info.buildNumber &&
      uri != null &&
      uri.scheme == 'https' &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.last == file.name;
}

/// Only the assets belonging to [info], never an independently raced release.
List<ReleaseFile> filesForUpdate(UpdateInfo info, Iterable<ReleaseInfo> releases) => List.unmodifiable([
  for (final release in releases)
    if (release.version.trim().replaceFirst(RegExp('^[vV]'), '') ==
            info.version.trim().replaceFirst(RegExp('^[vV]'), '') &&
        !release.buildNumberMalformed &&
        (release.buildNumber == null || release.buildNumber == info.buildNumber))
      ...release.files.where((file) => fileMatchesUpdate(info, file)),
]);

/// One coherent check result; its package list cannot change under the page.
final class UpdateSnapshot {
  /// Captures only files matching [info]. [lastKnown] does not claim freshness.
  new({required UpdateInfo info, Iterable<ReleaseFile> files = const [], this.lastKnown = false})
    : info = UpdateInfo(
        version: info.version,
        buildNumber: info.buildNumber,
        log: info.log,
        prerelease: info.prerelease,
        releaseUrl: info.releaseUrl,
        androidAbis: Set.unmodifiable(info.androidAbis),
        windowsMsixAvailable: info.windowsMsixAvailable,
      ),
      files = List.unmodifiable(files.where((file) => fileMatchesUpdate(info, file)));

  /// The version and build observed together.
  final UpdateInfo info;

  /// Its matching packages, or an empty list when history is unavailable.
  final List<ReleaseFile> files;

  /// A failed or stale refresh retained this previous valid result.
  final bool lastKnown;

  /// Retains a usable result without describing it as a fresh check.
  UpdateSnapshot asLastKnown() => UpdateSnapshot(info: info, files: files, lastKnown: true);
}

/// One release of `assets/releases.json` (3.x `ReleaseModel`).
final class ReleaseInfo {
  /// Creates the release.
  const new({
    required this.version,
    required this.date,
    this.title = '',
    this.github = '',
    this.authorName = '',
    this.authorAvatar = '',
    this.changelog = '',
    this.files = const [],
    this.buildNumber,
    this.buildNumberMalformed = false,
  });

  /// Reads one entry; GitHub API names are accepted too (3.x).
  factory fromJson(Map<String, Object?> json) {
    final files = json['files'] ?? json['assets'];
    final author = json['author'] is Map ? (json['author']! as Map).cast<String, Object?>() : const <String, Object?>{};
    final build = _exactPositiveInt(json['build_number']);
    return ReleaseInfo(
      buildNumber: build,
      buildNumberMalformed: json.containsKey('build_number') && build == null,
      version: _string(json['version'] ?? json['tagName']),
      title: _string(json['title'] ?? json['name']),
      date: _string(json['date'] ?? json['publishedAt']),
      github: _string(json['github'] ?? json['url']),
      authorName: _string(author['name'] ?? author['login']),
      authorAvatar: _string(author['avatar'] ?? author['avatar_url']),
      changelog: _string(json['changelog'] ?? json['body']),
      files: [
        if (files is List)
          for (final file in files.whereType<Map<Object?, Object?>>()) ReleaseFile.fromJson(file.cast()),
      ],
    );
  }

  /// Version name.
  final String version;

  /// Title.
  final String title;

  /// Publication date (`2026-09-27`).
  final String date;

  /// The release page.
  final String github;

  /// Who published it.
  final String authorName;

  /// The publisher's avatar.
  final String authorAvatar;

  /// What changed (Markdown).
  final String changelog;

  /// Downloadable files.
  final List<ReleaseFile> files;

  /// Optional additive build identity; old feed readers ignore this field.
  final int? buildNumber;

  /// A supplied invalid build cannot fall back to the legacy filename rule.
  final bool buildNumberMalformed;

  /// Whether [file] agrees with a supplied release-level build identity.
  /// Historical records without this field retain their original access.
  bool matchesFileBuild(ReleaseFile file) =>
      !buildNumberMalformed &&
      (buildNumber == null || fileMatchesUpdate(UpdateInfo(version: version, buildNumber: buildNumber!), file));
}

/// The releases of `releases.json` (a list, or `{releases: [...]}`), newest
/// first: by date, then by version (3.x `ReleaseHistoryRepository.parse`).
List<ReleaseInfo> parseReleases(Object? json) {
  final raw = switch (json) {
    final List<Object?> values => values,
    {'releases': final List<Object?> values} => values,
    _ => throw const FormatException('Invalid release history payload'),
  };
  final releases =
      [
        for (final entry in raw.whereType<Map<Object?, Object?>>())
          if (ReleaseInfo.fromJson(entry.cast()) case final release when release.version.isNotEmpty) release,
      ]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : compareVersions(b.version, a.version);
      });
  return List.unmodifiable(releases);
}

/// A web address the update pages may open or copy: http(s), with a host
/// and no user info (3.x `updateDownloadUri`).
Uri? updateDownloadUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

/// Kinds of installation packages a release offers (3.x
/// `ReleaseAssetUrls`; the keys are 3.x's).
enum PackageKind {
  /// Android arm64-v8a APK.
  androidArm64('android-arm64-v8a', ['android', 'arm64-v8a'], ['.apk']),

  /// Android armeabi-v7a APK.
  androidArm32('android-armeabi-v7a', ['android', 'armeabi-v7a'], ['.apk']),

  /// Android x86_64 APK.
  androidX64('android-x86_64', ['android', 'x86_64'], ['.apk']),

  /// Windows x64 installer.
  windowsSetup('windows-x64-setup.exe', ['windows', 'x64', 'setup'], ['.exe']),

  /// Windows x64 MSIX.
  windowsMsix('windows-x64.msix', ['windows', 'x64'], ['.msix']),

  /// Windows x64 portable ZIP.
  windowsPortable('windows-x64-portable.zip', ['windows', 'x64', 'portable'], ['.zip']),

  /// Linux x64 tarball (3.x's name; X02.1).
  linuxTarball('linux-x64.tar.gz', ['linux', 'x64'], ['.tar.gz']),

  /// macOS universal disk image.
  macosDmg('macos-universal.dmg', ['macos', 'universal'], ['.dmg']),

  /// macOS universal ZIP.
  macosZip('macos-universal.zip', ['macos', 'universal'], ['.zip']);

  new(this.key, this.required, this.extensions);

  /// 3.x's key.
  final String key;

  /// Words the file name must contain.
  final List<String> required;

  /// Allowed endings of the name or the address.
  final List<String> extensions;

  /// The best file of [files] for this kind (https only; release builds and
  /// shorter names win), or null.
  ReleaseFile? pick(Iterable<ReleaseFile> files) {
    ReleaseFile? best;
    var bestScore = -1;
    for (final file in files) {
      if (file.hasInvalidIntegrity) continue;
      final name = file.name.trim().toLowerCase();
      final url = file.url.trim().toLowerCase();
      final uri = Uri.tryParse(file.url.trim());
      if (name.isEmpty || uri == null || uri.scheme != 'https' || !uri.hasAuthority) continue;
      if (!extensions.any((ending) => name.endsWith(ending) || url.endsWith(ending))) continue;
      if (!required.every(name.contains)) continue;
      final score = name.contains('release') ? 1 : 0;
      final better =
          best == null ||
          score > bestScore ||
          (score == bestScore &&
              (name.length < best.name.length ||
                  (name.length == best.name.length && name.compareTo(best.name.toLowerCase()) < 0)));
      if (better) {
        best = file;
        bestScore = score;
      }
    }
    return best;
  }
}

/// Download mirrors put in front of a GitHub download address (3.x
/// `plugins/update.dart`; resumable ones first).
const List<String> downloadMirrorPrefixes = [
  'https://cdn.gh-proxy.org/',
  'https://edgeone.gh-proxy.org/',
  'https://hk.gh-proxy.org/',
  'https://gh.noki.eu.org/',
  'https://gh-proxy.com/',
  'https://slink.ltd/',
  'https://gh.catmak.name/',
  'https://proxy.gitwarp.top/',
  'https://github.ednovas.xyz/',
  'https://ghproxy.monkeyray.net/',
  'https://fastgit.cc/',
  'https://ghfile.geekertao.top/',
  'https://gh-proxy.org/',
  'https://ghproxy.net/',
  'https://wget.la/',
  'https://git.yylx.win/',
  'https://g.blfrp.cn/',
];

/// The download sources of [url]: only the address itself with
/// [githubOrigin], else every mirror and then the address (3.x
/// `getMirrorUrls`).
List<String> downloadSources(String url, {required bool githubOrigin}) {
  final uri = updateDownloadUri(url);
  if (uri == null) return const [];
  final plain = uri.toString();
  if (githubOrigin) return [plain];
  return List.unmodifiable({for (final prefix in downloadMirrorPrefixes) '$prefix$plain', plain});
}

/// At most [limit] distinct allowed attempts, retaining the canonical origin.
/// A fastest-source probe changes order only, never the asset's identity.
List<Uri> boundedDownloadSources(Iterable<Uri> sources, {required Uri canonical, Uri? fastest, int limit = 6}) {
  if (limit < 1) return const [];
  final allowed = sources.toSet();
  final ordered = <Uri>[
    if (fastest != null && allowed.contains(fastest)) fastest,
    ...allowed.where((uri) => uri != fastest),
  ];
  if (ordered.length <= limit) return List.unmodifiable(ordered);
  final selected = ordered.take(limit).toList();
  if (allowed.contains(canonical) && !selected.contains(canonical)) selected[limit - 1] = canonical;
  return List.unmodifiable(selected);
}

/// The update platform key of this device (3.x `_currentPlatformKey`).
String currentUpdatePlatform() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isIOS) return 'ios';
  if (Platform.isLinux) return 'linux';
  return 'default';
}

/// Reads the update files from the repository through the mirrors (3.x
/// `VersionUtil.checkUpdate` and `ReleaseHistoryRepository`).
class UpdateFeed {
  /// A feed over [http]; [githubOrigin] reads GitHub only (setting
  /// `useGitHubOriginForUpdates`), [now] stamps the addresses past caches.
  new(this.http, {required this.githubOrigin, String? platform, DateTime Function()? now})
    : platform = platform ?? currentUpdatePlatform(),
      _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  /// Whether only GitHub itself is asked.
  final bool githubOrigin;

  /// The `platforms` key of `version.json`.
  final String platform;

  final DateTime Function() _now;
  UpdateSnapshot? _lastSnapshot;
  int _generation = 0;
  bool _active = true;
  final Set<CancelToken> _requests = {};

  /// Whether this feed still owns the selected source policy.
  bool get isActive => _active;

  /// Retires a replaced feed without closing the app's shared transport.
  void deactivate() {
    _active = false;
    _generation++;
    for (final cancel in _requests.toList()) {
      cancel.cancel();
    }
  }

  static const Map<String, String> _headers = {
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/151.0.0.0 Safari/537.36',
    'accept': 'application/json,text/plain,*/*',
  };

  List<Uri> _sources(String path) {
    final stamp = '${_now().millisecondsSinceEpoch}';
    final urls = githubOrigin ? [updateRepository.raw(path)] : updateRepository.mirrors(path);
    return [
      for (final url in urls) url.replace(queryParameters: {...url.queryParameters, 'ts': stamp}),
    ];
  }

  /// Best valid version observed before all sources finish or [timeout].
  /// Validation is inside each request: a fast malformed object cannot cancel
  /// good answers, and a fast stale mirror cannot defeat a newer response.
  /// This is not proof that an unreachable origin has no newer publication.
  Future<UpdateInfo?> latest({Duration timeout = const Duration(seconds: 10)}) async {
    if (!isActive) return null;
    final sources = _sources('assets/version.json');
    final tokens = [for (final _ in sources) CancelToken()];
    _requests.addAll(tokens);
    final finished = Completer<void>();
    var pending = sources.length;
    UpdateInfo? best;
    var accepting = true;
    for (final (index, source) in sources.indexed) {
      unawaited(() async {
        try {
          final response = await http.send(
            LiveRequest(site: 'update', url: source, headers: _headers, timeout: timeout, cancel: tokens[index]),
          );
          if (!isActive || !accepting || response.status != 200) return;
          final json = response.json;
          if (json is! Map<String, Object?>) return;
          final info = UpdateInfo.fromJson(json, platform: platform);
          if (info.olderThan(appVersion, appBuild) || (info.isNewer && !info.isInstallableUpdate)) return;
          final previous = best;
          if (previous == null || info.newerThan(previous.version, previous.buildNumber)) best = info;
        } on Object {
          // Another mirror may still supply valid metadata.
        } finally {
          if (--pending == 0 && !finished.isCompleted) finished.complete();
        }
      }());
    }
    final timer = Timer(timeout, () {
      if (!finished.isCompleted) finished.complete();
    });
    await finished.future;
    accepting = false;
    timer.cancel();
    for (final token in tokens) {
      token.cancel();
    }
    _requests.removeAll(tokens);
    return isActive ? best : null;
  }

  /// Every release, newest first; null when no source answered. A targeted
  /// [matching] check ignores empty/stale histories until matching assets
  /// arrive; the unfiltered history browser retains its original behavior.
  Future<List<ReleaseInfo>?> releases({Duration timeout = const Duration(seconds: 15), UpdateInfo? matching}) async {
    if (!isActive) return null;
    final result = await raceFirst<List<ReleaseInfo>>(_sources('assets/releases.json'), (url, cancel) async {
      if (!isActive) return null;
      _requests.add(cancel);
      try {
        final response = await http.send(
          LiveRequest(site: 'update', url: url, headers: _headers, timeout: timeout, cancel: cancel),
        );
        if (!isActive || response.status != 200) return null;
        final releases = parseReleases(response.json);
        if (matching != null && !_hasPlatformPackages(matching, filesForUpdate(matching, releases))) return null;
        return releases;
      } finally {
        _requests.remove(cancel);
      }
    }, timeout: timeout);
    return isActive ? result : null;
  }

  bool _hasPlatformPackages(UpdateInfo info, List<ReleaseFile> files) => switch (platform) {
    'android' =>
      info.androidAbis.isNotEmpty &&
          info.androidAbis.every(
            (abi) => switch (abi) {
              'arm64-v8a' => PackageKind.androidArm64.pick(files) != null,
              'armeabi-v7a' => PackageKind.androidArm32.pick(files) != null,
              'x86_64' => PackageKind.androidX64.pick(files) != null,
              _ => false,
            },
          ),
    'windows' => PackageKind.windowsSetup.pick(files) != null || PackageKind.windowsPortable.pick(files) != null,
    'linux' => PackageKind.linuxTarball.pick(files) != null,
    'macos' => PackageKind.macosDmg.pick(files) != null || PackageKind.macosZip.pick(files) != null,
    'ios' => files.any((file) => file.name.endsWith('.ipa')),
    _ => files.isNotEmpty,
  };

  /// Resolves a version and its exact assets as one immutable result.
  /// At most the existing 10-second version and 15-second history budgets
  /// are used. The last valid in-memory result survives offline/stale checks,
  /// but is explicitly marked last-known rather than newly confirmed.
  Future<UpdateSnapshot?> check() async {
    if (!isActive) return null;
    final generation = ++_generation;
    UpdateInfo? info;
    try {
      info = await latest();
    } on Object {
      info = null;
    }
    if (!isActive) return null;
    final previous = _lastSnapshot;
    if (info == null ||
        info.olderThan(appVersion, appBuild) ||
        (info.isNewer && !info.isInstallableUpdate) ||
        (previous != null && previous.info.newerThan(info.version, info.buildNumber))) {
      return previous?.asLastKnown();
    }
    var files = const <ReleaseFile>[];
    if (info.isNewer) {
      try {
        files = filesForUpdate(info, await releases(matching: info) ?? const []);
      } on Object {
        // The release page remains usable when matching packages are absent.
      }
    }
    if (!isActive) return null;
    final current = _lastSnapshot;
    if (current != null && current.info.newerThan(info.version, info.buildNumber)) return current.asLastKnown();
    if (files.isEmpty &&
        current != null &&
        current.info.sameVersion(info.version) &&
        current.info.buildNumber == info.buildNumber &&
        current.files.isNotEmpty) {
      return current.asLastKnown();
    }
    final snapshot = UpdateSnapshot(info: info, files: files);
    if (generation == _generation ||
        current == null ||
        info.newerThan(current.info.version, current.info.buildNumber)) {
      _lastSnapshot = snapshot;
    }
    return snapshot;
  }
}

/// The update feed of the pages (tests replace it).
final Provider<UpdateFeed> updateFeedProvider = Provider<UpdateFeed>((ref) {
  final services = ref.watch(appServicesProvider);
  final origin = ref.watch(
    settingProvider(Settings.useGitHubOriginForUpdates).select((value) {
      final selected = value.value;
      return selected is bool ? selected : services.store.settings.get(Settings.useGitHubOriginForUpdates);
    }),
  );
  final feed = UpdateFeed(services.http, githubOrigin: origin);
  ref.onDispose(feed.deactivate);
  return feed;
});

// JSON integers are bounded to the exact range shared by native and web Dart.
int? _exactPositiveInt(Object? value) => switch (value) {
  final int number when number > 0 && number <= 9007199254740991 => number,
  _ => null,
};

String? _sha256(Object? value) =>
    value is String && value.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value) ? value.toLowerCase() : null;

int? _positiveInt(Object? value) => switch (value) {
  final int number when number > 0 => number,
  final String text => int.tryParse(text.trim()),
  _ => null,
};

String _string(Object? value) => value?.toString().trim() ?? '';

int? _int(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text.trim()),
  _ => null,
};

String _size(Object? value) => switch (value) {
  null => '0.0mb',
  final String text when text.trim().isEmpty => '0.0mb',
  final String text => text.trim(),
  final num bytes => '${(bytes / (1024 * 1024)).toStringAsFixed(2)}mb',
  _ => value.toString(),
};
