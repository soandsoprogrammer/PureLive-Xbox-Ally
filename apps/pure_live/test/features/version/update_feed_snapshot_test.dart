import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/update_feed.dart';

import '../../support.dart';

ReleaseFile _file(String version, int build, {String suffix = 'android-arm64-v8a-release.apk'}) {
  final name = 'PureLive-$version-$build-$suffix';
  return ReleaseFile(
    name: name,
    size: '1mb',
    downloads: 0,
    url: 'https://github.com/o/r/releases/download/v$version/$name',
  );
}

List<ReleaseInfo> _history(String version, int build) => [
  ReleaseInfo(version: version, date: '2026-10-27', files: [_file(version, build)]),
];

final class _Feed extends UpdateFeed {
  new({this.info, this.history}) : super(NoNetworkHttp(), githubOrigin: true, platform: 'android');

  UpdateInfo? info;
  List<ReleaseInfo>? history;
  Completer<List<ReleaseInfo>?>? historyGate;

  @override
  Future<UpdateInfo?> latest({Duration timeout = const Duration(seconds: 10)}) async => info;

  @override
  Future<List<ReleaseInfo>?> releases({Duration timeout = const Duration(seconds: 15), UpdateInfo? matching}) async {
    final gate = historyGate;
    return gate == null ? history : await gate.future;
  }
}

final class _Http implements LiveHttp {
  new(this.respond);

  final Future<Object?> Function(LiveRequest request) respond;

  @override
  Future<LiveResponse> send(LiveRequest request) async =>
      LiveResponse(status: 200, bytes: utf8.encode(jsonEncode(await respond(request))), url: request.url);

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

List<Object?> _jsonHistory(String version, int build) => [
  {
    'version': version,
    'date': '2026-10-27',
    'files': [
      {'name': _file(version, build).name, 'url': _file(version, build).url},
    ],
  },
];

void main() {
  test('an old version or same-version lower build never becomes a valid current snapshot', () async {
    for (final info in [
      const UpdateInfo(version: '1.0.0', buildNumber: 99999),
      UpdateInfo(version: appVersion, buildNumber: appBuild - 1),
      const UpdateInfo(version: '9.0.0', buildNumber: 1),
      UpdateInfo(version: '9.0.0', buildNumber: appBuild),
    ]) {
      expect(await _Feed(info: info, history: _history(info.version, info.buildNumber)).check(), isNull);
    }
  });

  test('an offline or stale refresh retains a coherent last-known snapshot, not a latest claim', () async {
    final feed = _Feed(
      info: const UpdateInfo(version: '9.0.0', buildNumber: 6000),
      history: _history('9.0.0', 6000),
    );
    final initial = (await feed.check())!;
    expect(initial.lastKnown, isFalse);
    expect(initial.files.single.name, contains('9.0.0-6000'));
    expect(initial.files.clear, throwsUnsupportedError);
    feed.info = null;
    final offline = (await feed.check())!;
    expect(offline.lastKnown, isTrue);
    expect(offline.info.skipToken, initial.info.skipToken);
    expect(offline.files.single, same(initial.files.single));
    feed.info = const UpdateInfo(version: '8.0.0', buildNumber: 9000);
    expect((await feed.check())!.info.version, '9.0.0');
  });

  test('a valid current snapshot is retained offline without turning into an upgrade', () async {
    final feed = _Feed(
      info: UpdateInfo(version: appVersion, buildNumber: appBuild),
    );
    expect((await feed.check())!.info.isNewer, isFalse);
    feed.info = null;
    final offline = (await feed.check())!;
    expect(offline.lastKnown, isTrue);
    expect(offline.info.version, appVersion);
    expect(offline.info.isNewer, isFalse);
  });

  test('missing history does not reuse another version or build of packages', () async {
    final feed = _Feed(
      info: const UpdateInfo(version: '9.0.0', buildNumber: 6001),
      history: _history('9.0.0', 6000),
    );
    expect((await feed.check())!.files, isEmpty);
    feed.history = _history('8.0.0', 6001);
    expect((await feed.check())!.files, isEmpty);
    feed.history = _history('9.0.0', 6001);
    final correct = (await feed.check())!;
    expect(correct.files.single.name, contains('9.0.0-6001'));
    feed.history = const [];
    expect((await feed.check())!.lastKnown, isTrue);
    feed.info = const UpdateInfo(version: '9.1.0', buildNumber: 6002);
    final newer = (await feed.check())!;
    expect(newer.info.version, '9.1.0');
    expect(newer.files, isEmpty);
    expect(newer.lastKnown, isFalse);
  });

  test('a late concurrent check cannot replace the newer cached identity', () async {
    final olderGate = Completer<List<ReleaseInfo>?>();
    final feed = _Feed(info: const UpdateInfo(version: '9.0.0', buildNumber: 6000))..historyGate = olderGate;
    final older = feed.check();
    await pumpEventQueue();
    feed
      ..info = const UpdateInfo(version: '9.1.0', buildNumber: 6001)
      ..historyGate = null
      ..history = _history('9.1.0', 6001);
    expect((await feed.check())!.info.version, '9.1.0');
    olderGate.complete(_history('9.0.0', 6000));
    final late = (await older)!;
    expect(late.info.version, '9.1.0');
    expect(late.files.single.name, contains('9.1.0-6001'));
    feed.info = null;
    expect((await feed.check())!.info.version, '9.1.0');
  });

  test('a newer valid identity learned by an earlier check is not forgotten offline', () async {
    final earlierGate = Completer<List<ReleaseInfo>?>();
    final feed = _Feed(info: const UpdateInfo(version: '9.1.0', buildNumber: 6001))..historyGate = earlierGate;
    final earlier = feed.check();
    await pumpEventQueue();
    feed
      ..info = const UpdateInfo(version: '9.0.0', buildNumber: 6000)
      ..historyGate = null
      ..history = _history('9.0.0', 6000);
    expect((await feed.check())!.info.version, '9.0.0');
    earlierGate.complete(_history('9.1.0', 6001));
    expect((await earlier)!.info.version, '9.1.0');
    feed.info = null;
    expect((await feed.check())!.info.version, '9.1.0');
  });

  test('targeted histories ignore missing, malformed, empty and wrong-build answers', () async {
    for (final bad in <Object?>[
      null,
      {'bad': true},
      [],
      _jsonHistory('8.0.0', 6000),
      _jsonHistory('9.0.0', 5999),
    ]) {
      final delayed = Completer<Object?>();
      final http = _Http((request) async {
        if (request.url.host == 'cdn.gh-proxy.org') return await delayed.future;
        return bad;
      });
      final feed = UpdateFeed(http, githubOrigin: false, platform: 'android');
      final pending = feed.releases(matching: const UpdateInfo(version: '9.0.0', buildNumber: 6000));
      await pumpEventQueue();
      delayed.complete(_jsonHistory('9.0.0', 6000));
      expect((await pending)!.single.files.single.name, contains('9.0.0-6000'));
    }
  });

  test('a partial history cannot hide the Android ABIs declared by the matching version', () async {
    final delayed = Completer<Object?>();
    const info = UpdateInfo(version: '9.0.0', buildNumber: 6000, androidAbis: {'arm64-v8a', 'armeabi-v7a'});
    final http = _Http((request) async {
      if (request.url.host == 'cdn.gh-proxy.org') return await delayed.future;
      return _jsonHistory('9.0.0', 6000);
    });
    final pending = UpdateFeed(http, githubOrigin: false, platform: 'android').releases(matching: info);
    await pumpEventQueue();
    final arm32 = _file('9.0.0', 6000, suffix: 'android-armeabi-v7a-release.apk');
    delayed.complete([
      {
        'version': '9.0.0',
        'files': [
          {'name': _file('9.0.0', 6000).name, 'url': _file('9.0.0', 6000).url},
          {'name': arm32.name, 'url': arm32.url},
        ],
      },
    ]);
    expect(filesForUpdate(info, (await pending)!), hasLength(2));
  });

  test('Windows x64 selectors never auto-pick an explicitly arm64 package', () {
    final setup = _file('9.0.0', 6000, suffix: 'windows-arm64-setup.exe');
    final portable = _file('9.0.0', 6000, suffix: 'windows-arm64-portable.zip');
    expect(PackageKind.windowsSetup.pick([setup]), isNull);
    expect(PackageKind.windowsPortable.pick([portable]), isNull);
    expect(PackageKind.windowsSetup.pick([setup, _file('9.0.0', 6000, suffix: 'windows-x64-setup.exe')]), isNotNull);
  });

  test('every current platform package binds to the effective feed version and build', () {
    final raw = jsonDecode(File('../../assets/version.json').readAsStringSync()) as Map<String, Object?>;
    final releases = parseReleases(jsonDecode(File('../../assets/releases.json').readAsStringSync()));
    for (final platform in ['android', 'windows', 'linux', 'macos', 'ios', 'default']) {
      final info = UpdateInfo.fromJson(raw, platform: platform);
      final release = releases.firstWhere((release) => release.version == info.version);
      final files = filesForUpdate(info, [release]);
      expect(
        files,
        hasLength(release.files.where((file) => file.name.startsWith('PureLive-')).length),
        reason: platform,
      );
      expect(files.any((file) => file.name == 'SHA256SUMS.txt'), isFalse);
    }
  });

  test('snapshot ABI availability cannot be mutated through the input or output', () {
    final abis = {'arm64-v8a'};
    final snapshot = UpdateSnapshot(
      info: UpdateInfo(version: '9.0.0', buildNumber: 6000, androidAbis: abis),
    );
    abis.clear();
    expect(snapshot.info.androidAbis, {'arm64-v8a'});
    expect(snapshot.info.androidAbis.clear, throwsUnsupportedError);
    final parsed = UpdateInfo.fromJson({
      'version': '9.0.0',
      'build_number': 6000,
      'android_abis': ['arm64-v8a'],
    }, platform: 'android');
    expect(parsed.androidAbis.clear, throwsUnsupportedError);
  });

  test('ambiguous legacy names and URL basename mismatches are not update candidates', () {
    const info = UpdateInfo(version: '9.0.0', buildNumber: 6000);
    const legacy = ReleaseFile(
      name: 'PureLive-9.0.0-android-arm64-v8a-release.apk',
      size: '',
      downloads: 0,
      url: 'https://x/a.apk',
    );
    expect(fileMatchesUpdate(info, legacy), isFalse);
    final correct = _file('9.0.0', 6000);
    expect(fileMatchesUpdate(info, correct), isTrue);
    final wrong = ReleaseFile(name: correct.name, size: '', downloads: 0, url: _file('8.0.0', 6000).url);
    expect(fileMatchesUpdate(info, wrong), isFalse);
    expect(fileMatchesUpdate(const UpdateInfo(version: 'v9.0.0', buildNumber: 6000), correct), isTrue);
  });
}
