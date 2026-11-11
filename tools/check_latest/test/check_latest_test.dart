import 'package:check_latest/check_latest.dart';
import 'package:test/test.dart';

void main() {
  test('Android stable selection ignores numeric preview package paths', () async {
    final http = _FixtureFetcher();
    final findings = await collect(env: const {'MEDIA_KIT_UPSTREAM_REPO': 'owner/fork'}, pub: const {}, fetcher: http);
    http.close();
    expect(findings.singleWhere((f) => f.name == 'Android NDK').latest, '30.0.1');
    expect(findings.singleWhere((f) => f.name == 'Android cmdline-tools').latest, '23.0');
  });

  test('incomplete official responses fail instead of reporting up to date', () {
    const unknown = Finding('toolchain', 'Flutter', '3.47.8', '');
    const behind = Finding('toolchain', 'Gradle', '9.8.1', '9.8.2');
    expect(findingsExitCode([unknown]), 2);
    expect(findingsExitCode([behind, unknown]), 2);
    expect(findingsExitCode([behind]), 1);
    expect(findingsExitCode([unknown], reportOnly: true), 0);
    expect(findingsExitCode([const Finding('toolchain', 'Gradle', '9.8.2', '9.8.2')]), 0);
  });

  test('Xcode stable feed excludes newer RC and beta releases', () {
    expect(
      latestStableXcode('''
<rss><channel>
<item><title>Xcode 27.2 RC (27B48)</title></item>
<item><title>Xcode 27.2 beta 3 (27B40)</title></item>
<item><title>Xcode 27.1 (27A9275)</title></item>
<item><title>Xcode 27 (27A266a)</title></item>
</channel></rss>'''),
      '27.1',
    );
  });

  test('readEnvFile skips comments and blank lines', () {
    final env = readEnvFile('# pinned\nFLUTTER_VERSION=3.47.5\n\n  GRADLE_VERSION = 9.8.0 \nbroken\n');
    expect(env, {'FLUTTER_VERSION': '3.47.5', 'GRADLE_VERSION': '9.8.0'});
  });

  test('readDirectHostedDependencies keeps hosted direct dependencies only', () {
    const lock = '''
packages:
  args:
    dependency: "direct main"
    source: hosted
    version: "2.7.0"
  lints:
    dependency: "direct dev"
    source: hosted
    version: "6.0.0"
  collection:
    dependency: transitive
    source: hosted
    version: "1.19.1"
  media_kit:
    dependency: "direct main"
    source: path
    version: "1.2.0"
''';
    expect(readDirectHostedDependencies(lock), {'args': '2.7.0', 'lints': '6.0.0'});
  });

  test('highestStable ignores prefixes that do not match and pre-releases', () {
    expect(highestStable(['n8.1', 'n9.0.2', 'n9.1-dev', 'n10.0-rc1', 'v99.0']), '');
    expect(highestStable(['n8.1', 'n9.0.2', 'n9.1-dev', 'n10.0.0-rc1', 'v99.0'], prefix: 'n'), '9.0.2');
    expect(highestStable(['9.4.1', '9.5.0-alpha01', '9.3.0']), '9.4.1');
  });

  test('isBehind compares versions, not strings', () {
    expect(const Finding('toolchain', 'NDK', '27.3.13750724', '30.0.16248370').isBehind, isTrue);
    expect(const Finding('toolchain', 'JDK', '27', '27').isBehind, isFalse);
    expect(const Finding('toolchain', 'JDK', '26', '27').isBehind, isTrue);
    expect(const Finding('toolchain', 'Gradle', '9.8', '9.8.0').isBehind, isFalse);
    expect(const Finding('fork', 'media_kit', 'abc', 'def').isBehind, isTrue);
    expect(const Finding('pub', 'args', '2.7.0', '').isBehind, isFalse);
  });

  test('workspace direct dependencies come from member pubspecs, versions from the lock', () {
    const lock = '''
packages:
  args:
    dependency: transitive
    source: hosted
    version: "2.7.0"
  media_kit:
    dependency: "direct overridden"
    source: path
    version: "1.1.11"
  crypto:
    dependency: transitive
    source: hosted
    version: "3.0.7"
''';
    final result = readWorkspaceDirectDependencies(lock, [
      'name: a\ndependencies:\n  args: ^2.7.0\n  media_kit:\n    path: x\n',
      'name: b\ndev_dependencies:\n  crypto: any\n',
    ]);
    expect(result, {'args': '2.7.0', 'crypto': '3.0.7'});
    expect(readWorkspaceMembers('name: w\nworkspace:\n  - legacy\n  - packages/live_core\n'), [
      'legacy',
      'packages/live_core',
    ]);
  });
}

class _FixtureFetcher extends Fetcher {
  @override
  Future<String> get(String url) async {
    if (url.endsWith('repository2-3.xml')) {
      return '''
<repository>
<remotePackage path="ndk;30.0.1"><revision><major>30</major><minor>0</minor><micro>1</micro></revision><channelRef ref="channel-0"/></remotePackage>
<remotePackage path="ndk;31.0.9"><revision><major>31</major><minor>0</minor><micro>9</micro><preview>1</preview></revision><channelRef ref="channel-1"/></remotePackage>
<remotePackage path="cmdline-tools;23.0"><revision><major>23</major></revision><channelRef ref="channel-0"/></remotePackage>
<remotePackage path="cmdline-tools;24.0"><revision><major>24</major></revision><channelRef ref="channel-1"/></remotePackage>
<remotePackage path="platforms;android-37.2"><channelRef ref="channel-0"/></remotePackage>
<remotePackage path="build-tools;37.0.0"><channelRef ref="channel-0"/></remotePackage>
<remotePackage path="platform-tools"><revision><major>37</major><minor>0</minor><micro>1</micro></revision><channelRef ref="channel-0"/></remotePackage>
<remotePackage path="cmake;4.1.2"><channelRef ref="channel-0"/></remotePackage>
</repository>''';
    }
    if (url.endsWith('maven-metadata.xml')) return '<version>9.4.1</version>';
    throw StateError('Unexpected fixture URL: $url');
  }

  @override
  Future<Object?> json(String url) async {
    if (url.contains('releases_linux.json')) {
      return {
        'current_release': {'stable': 'stable'},
        'releases': [
          {'hash': 'stable', 'version': '3.47.8', 'dart_sdk_version': '3.13.7'},
        ],
      };
    }
    if (url.contains('gradle.org')) return {'version': '9.8.2'};
    if (url.contains('available_releases')) return {'most_recent_feature_release': 27};
    if (url.contains('/tags?')) {
      return [
        {'name': 'n9.0.2'},
      ];
    }
    if (url.contains('/commits?')) {
      return [
        {'sha': 'abc'},
      ];
    }
    return {'tag_name': 'v1.0.0'};
  }
}
