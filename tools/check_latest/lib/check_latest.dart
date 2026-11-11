/// Compares the pinned toolchain (`toolchain.env`), the self-maintained forks and
/// the direct pub dependencies (`pubspec.lock`) with the latest official stable
/// releases (docs/specs/ENGINEERING.md §3).
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

/// One compared item.
class Finding {
  /// Creates a finding.
  const new(this.group, this.name, this.pinned, this.latest, {this.note = ''});

  /// `toolchain`, `fork` or `pub`.
  final String group;

  /// Tool or package name.
  final String name;

  /// Version or commit in the repository.
  final String pinned;

  /// Latest official stable version or upstream commit; empty when unknown.
  final String latest;

  /// Why the lookup failed or what to do.
  final String note;

  /// Whether [pinned] is older than [latest].
  bool get isBehind => latest.isNotEmpty && pinned != latest && !_pinnedIsNewer;

  bool get _pinnedIsNewer {
    final a = _tryVersion(pinned);
    final b = _tryVersion(latest);
    return a != null && b != null && a >= b;
  }

  /// JSON form.
  Map<String, Object> toJson() => {
    'group': group,
    'name': name,
    'pinned': pinned,
    'latest': latest,
    'behind': isBehind,
    if (note.isNotEmpty) 'note': note,
  };
}

Version? _tryVersion(String value) {
  try {
    return Version.parse(value);
  } on FormatException {
    final parts = value.split('.');
    if (parts.length == 2) return _tryVersion('$value.0');
    if (parts.length == 1 && int.tryParse(value) != null) return Version(int.parse(value), 0, 0);
    return null;
  }
}

/// Reads `KEY=VALUE` lines, ignoring comments and blank lines.
Map<String, String> readEnvFile(String text) {
  final values = <String, String>{};
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator).trim()] = line.substring(separator + 1).trim();
  }
  return values;
}

/// Hosted direct dependencies (`direct main`, `direct dev`) from a pubspec.lock.
Map<String, String> readDirectHostedDependencies(String lockText) {
  final lock = loadYaml(lockText) as YamlMap;
  final packages = lock['packages'] as YamlMap? ?? YamlMap();
  final result = <String, String>{};
  for (final entry in packages.entries) {
    final info = entry.value as YamlMap;
    final dependency = info['dependency']?.toString() ?? '';
    if (info['source'] != 'hosted' || !dependency.startsWith('direct')) continue;
    result[entry.key.toString()] = info['version'].toString();
  }
  return result;
}

/// Hosted packages that any workspace member lists under `dependencies` or
/// `dev_dependencies`, with the version resolved in the shared lock file.
/// [pubspecs] are the members' pubspec.yaml texts.
Map<String, String> readWorkspaceDirectDependencies(String lockText, Iterable<String> pubspecs) {
  final lock = loadYaml(lockText) as YamlMap;
  final packages = lock['packages'] as YamlMap? ?? YamlMap();
  final names = <String>{
    for (final text in pubspecs)
      for (final section in const ['dependencies', 'dev_dependencies'])
        ...(((loadYaml(text) as YamlMap)[section] as YamlMap?)?.keys.map((key) => key.toString()) ?? const <String>[]),
  };
  return {
    for (final name in names.toList()..sort())
      if (packages[name] case final YamlMap info when info['source'] == 'hosted') name: info['version'].toString(),
  };
}

/// Workspace member directories listed in the root pubspec.yaml.
List<String> readWorkspaceMembers(String rootPubspec) => [
  for (final member in ((loadYaml(rootPubspec) as YamlMap)['workspace'] as YamlList?) ?? YamlList()) member.toString(),
];

/// Picks the highest stable version from candidate strings such as `n9.0.2` or `v0.41.0`.
String highestStable(Iterable<String> candidates, {String prefix = ''}) {
  Version? best;
  var bestRaw = '';
  for (final raw in candidates) {
    if (!raw.startsWith(prefix)) continue;
    final version = _tryVersion(raw.substring(prefix.length));
    if (version == null || version.isPreRelease) continue;
    if (best == null || version > best) {
      best = version;
      bestRaw = raw.substring(prefix.length);
    }
  }
  return bestRaw;
}

/// Selects an Android package only from the stable channel, without a preview
/// revision. Numeric paths alone do not distinguish a preview NDK from stable.
String latestAndroidPackage(String xml, String prefix, {bool revision = false}) {
  final versions = <String>[];
  for (final package in XmlDocument.parse(xml).findAllElements('remotePackage')) {
    final path = package.getAttribute('path') ?? '';
    if (!path.startsWith(prefix)) continue;
    if (package.getElement('channelRef')?.getAttribute('ref') != 'channel-0') continue;
    final rev = package.getElement('revision');
    if (rev?.getElement('preview') != null) continue;
    if (revision) {
      if (path != prefix || rev == null) continue;
      versions.add(
        [
          for (final part in ['major', 'minor', 'micro']) rev.getElement(part)?.innerText ?? '0',
        ].join('.'),
      );
    } else {
      versions.add(path.substring(prefix.length));
    }
  }
  return highestStable(versions);
}

/// Selects final Xcode releases from Apple's release feed, excluding beta/RC.
String latestStableXcode(String rss) => highestStable([
  for (final title in XmlDocument.parse(rss).findAllElements('title'))
    if (RegExp(r'^Xcode ([0-9.]+)(?: \([A-Za-z0-9]+\))?$').firstMatch(title.innerText.trim()) case final match?)
      match.group(1)!,
]);

/// A failed lookup is not evidence that a pin is current.
int findingsExitCode(Iterable<Finding> findings, {bool reportOnly = false}) {
  if (reportOnly) return 0;
  if (findings.any((finding) => finding.latest.isEmpty)) return 2;
  return findings.any((finding) => finding.isBehind) ? 1 : 0;
}

/// Minimal HTTP GET that honours HTTPS_PROXY / HTTP_PROXY and GITHUB_TOKEN.
class Fetcher {
  /// Creates a fetcher.
  new() : _client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;

  final HttpClient _client;

  /// Returns the body, or throws [HttpException] on a non-200 status.
  Future<String> get(String url) => _get(url).timeout(const Duration(seconds: 60));

  Future<String> _get(String url) async {
    final request = await _client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, 'pure_live-check_latest');
    final token = Platform.environment['GITHUB_TOKEN'];
    if (token != null && token.isNotEmpty && url.startsWith('https://api.github.com/')) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) throw HttpException('HTTP ${response.statusCode} for $url');
    return body;
  }

  /// Parses the body as JSON.
  Future<Object?> json(String url) async => jsonDecode(await get(url));

  /// Closes the client.
  void close() => _client.close(force: true);
}

/// Runs every lookup; a failed lookup becomes a finding with an empty [Finding.latest].
Future<List<Finding>> collect({
  required Map<String, String> env,
  required Map<String, String> pub,
  Fetcher? fetcher,
}) async {
  final http = fetcher ?? Fetcher();
  final findings = <Finding>[];

  Future<void> check(String group, String name, String pinned, Future<String> Function() latest) async {
    try {
      final version = await latest();
      if (version.isEmpty) throw const FormatException('No stable release in the official response');
      findings.add(Finding(group, name, pinned, version));
    } on Object catch (error) {
      findings.add(Finding(group, name, pinned, '', note: 'lookup failed: $error'));
    }
  }

  await check('toolchain', 'Flutter', env['FLUTTER_VERSION'] ?? '', () async {
    final data =
        (await http.json('https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json'))!
            as Map<String, Object?>;
    final hash = (data['current_release']! as Map<String, Object?>)['stable'];
    final releases = (data['releases']! as List<Object?>).cast<Map<String, Object?>>();
    return releases.firstWhere((release) => release['hash'] == hash)['version']! as String;
  });
  await check('toolchain', 'Dart (Flutter stable bundle)', env['DART_VERSION'] ?? '', () async {
    final data =
        (await http.json('https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json'))!
            as Map<String, Object?>;
    final hash = (data['current_release']! as Map<String, Object?>)['stable'];
    final releases = (data['releases']! as List<Object?>).cast<Map<String, Object?>>();
    return releases.firstWhere((release) => release['hash'] == hash)['dart_sdk_version']! as String;
  });
  await check('toolchain', 'Gradle', env['GRADLE_VERSION'] ?? '', () async {
    final data = (await http.json('https://services.gradle.org/versions/current'))! as Map<String, Object?>;
    return data['version']! as String;
  });
  await check('toolchain', 'Android Gradle Plugin', env['AGP_VERSION'] ?? '', () async {
    final xml = await http.get(
      'https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml',
    );
    return highestStable(RegExp('<version>([^<]+)</version>').allMatches(xml).map((m) => m.group(1)!));
  });
  await check('toolchain', 'Kotlin', env['KOTLIN_VERSION'] ?? '', () async {
    final data =
        (await http.json('https://api.github.com/repos/JetBrains/kotlin/releases/latest'))! as Map<String, Object?>;
    return (data['tag_name']! as String).replaceFirst('v', '');
  });
  await check('toolchain', 'JDK (Temurin feature release)', env['JDK_FEATURE_VERSION'] ?? '', () async {
    final data = (await http.json('https://api.adoptium.net/v3/info/available_releases'))! as Map<String, Object?>;
    return '${data['most_recent_feature_release']}';
  });
  if (env['JDK_VERSION'] case final pinned?) {
    await check('toolchain', 'JDK (Temurin full release)', pinned, () async {
      final feature = env['JDK_FEATURE_VERSION'];
      final data =
          (await http.json('https://api.github.com/repos/adoptium/temurin$feature-binaries/releases/latest'))!
              as Map<String, Object?>;
      return (data['tag_name']! as String).replaceFirst('jdk-', '');
    });
  }
  final androidRepository = http.get('https://dl.google.com/android/repository/repository2-3.xml');
  if (env['CLANG_VERSION'] case final pinned?) {
    await check('toolchain', 'Clang (official Linux release)', pinned, () async {
      final data =
          (await http.json('https://api.github.com/repos/llvm/llvm-project/releases/latest'))! as Map<String, Object?>;
      return (data['tag_name']! as String).replaceFirst('llvmorg-', '');
    });
  }
  if (env['WINDOW_MANAGER_UPSTREAM_VERSION'] case final pinned?) {
    await check('fork', 'window_manager (published base)', pinned, () async {
      final data = (await http.json('https://pub.dev/api/packages/window_manager'))! as Map<String, Object?>;
      return (data['latest']! as Map<String, Object?>)['version']! as String;
    });
  }
  await check('toolchain', 'Android NDK', env['ANDROID_NDK_VERSION'] ?? '', () async {
    final xml = await androidRepository;
    return latestAndroidPackage(xml, 'ndk;');
  });
  await check('toolchain', 'Android platform (compileSdk)', env['ANDROID_COMPILE_SDK'] ?? '', () async {
    final xml = await androidRepository;
    return latestAndroidPackage(xml, 'platforms;android-');
  });
  await check('toolchain', 'Android build-tools', env['ANDROID_BUILD_TOOLS'] ?? '', () async {
    final xml = await androidRepository;
    return latestAndroidPackage(xml, 'build-tools;');
  });
  await check('toolchain', 'Android platform-tools', env['ANDROID_PLATFORM_TOOLS'] ?? '', () async {
    final xml = await androidRepository;
    return latestAndroidPackage(xml, 'platform-tools', revision: true);
  });
  await check('toolchain', 'Android cmdline-tools', env['ANDROID_CMDLINE_TOOLS'] ?? '', () async {
    final xml = await androidRepository;
    return latestAndroidPackage(xml, 'cmdline-tools;');
  });
  await check('toolchain', 'Android CLI', env['ANDROID_CLI_VERSION'] ?? '', () async {
    final notes = await http.get('https://developer.android.com/tools/agents/android-cli/release-notes');
    return highestStable(RegExp(r'Version\s+(\d+\.\d+\.\d+)').allMatches(notes).map((match) => match[1]!));
  });
  await check('toolchain', 'Android CMake', env['ANDROID_CMAKE_VERSION'] ?? '', () async {
    final xml = await androidRepository;
    return latestAndroidPackage(xml, 'cmake;');
  });
  for (final (key, name, repository, prefix) in [
    ('CMAKE_VERSION', 'CMake (standalone)', 'Kitware/CMake', 'v'),
    ('NINJA_VERSION', 'Ninja', 'ninja-build/ninja', 'v'),
    ('INNO_SETUP_VERSION', 'Inno Setup', 'jrsoftware/issrc', 'is-'),
  ]) {
    if (env[key] case final pinned?) {
      await check('toolchain', name, pinned, () async {
        final data =
            (await http.json('https://api.github.com/repos/$repository/releases/latest'))! as Map<String, Object?>;
        return (data['tag_name']! as String).replaceFirst(prefix, '').replaceAll('_', '.');
      });
    }
  }
  if (env['VISUAL_STUDIO_VERSION'] case final pinned?) {
    await check('toolchain', 'Visual Studio (stable)', pinned, () async {
      final data = (await http.json('https://aka.ms/vs/18/stable/channel'))! as Map<String, Object?>;
      return (data['info']! as Map<String, Object?>)['productDisplayVersion']! as String;
    });
  }
  if (env['XCODE_VERSION'] case final pinned?) {
    await check('toolchain', 'Xcode', pinned, () async {
      return latestStableXcode(await http.get('https://developer.apple.com/news/releases/rss/releases.rss'));
    });
  }
  if (env['COCOAPODS_VERSION'] case final pinned?) {
    await check('toolchain', 'CocoaPods', pinned, () async {
      final data = (await http.json('https://rubygems.org/api/v1/gems/cocoapods.json'))! as Map<String, Object?>;
      return data['version']! as String;
    });
  }
  if (env['PYTHON_VERSION'] case final pinned?) {
    await check('toolchain', 'Python', pinned, () async {
      final tags = (await http.json('https://api.github.com/repos/python/cpython/tags?per_page=100'))! as List<Object?>;
      return highestStable(tags.map((tag) => (tag! as Map<String, Object?>)['name']! as String), prefix: 'v');
    });
  }
  await check('toolchain', 'mpv', env['MPV_VERSION'] ?? '', () async {
    final data =
        (await http.json('https://api.github.com/repos/mpv-player/mpv/releases/latest'))! as Map<String, Object?>;
    return (data['tag_name']! as String).replaceFirst('v', '');
  });
  await check('toolchain', 'FFmpeg', env['FFMPEG_VERSION'] ?? '', () async {
    final tags = (await http.json('https://api.github.com/repos/FFmpeg/FFmpeg/tags?per_page=100'))! as List<Object?>;
    return highestStable(tags.map((tag) => (tag! as Map<String, Object?>)['name']! as String), prefix: 'n');
  });
  final forkRepository = env['MEDIA_KIT_UPSTREAM_REPO'] ?? '';
  await check('fork', 'media_kit ($forkRepository)', env['MEDIA_KIT_UPSTREAM_COMMIT'] ?? '', () async {
    final data = (await http.json('https://api.github.com/repos/$forkRepository/commits?per_page=1'))! as List<Object?>;
    return (data.first! as Map<String, Object?>)['sha']! as String;
  });

  for (final entry in pub.entries) {
    await check('pub', entry.key, entry.value, () async {
      final data = (await http.json('https://pub.dev/api/packages/${entry.key}'))! as Map<String, Object?>;
      return (data['latest']! as Map<String, Object?>)['version']! as String;
    });
  }
  if (fetcher == null) http.close();
  return findings;
}

/// A Markdown table of the findings, behind items first.
String renderMarkdown(List<Finding> findings) {
  final sorted = [...findings]..sort((a, b) => (b.isBehind ? 1 : 0) - (a.isBehind ? 1 : 0));
  final buffer = StringBuffer()
    ..writeln('| 类别 | 名称 | 仓库版本 | 最新稳定版 | 状态 |')
    ..writeln('|---|---|---|---|---|');
  for (final finding in sorted) {
    final state = finding.latest.isEmpty
        ? '查询失败：${finding.note}'
        : finding.isBehind
        ? '**落后**'
        : '最新';
    buffer.writeln('| ${finding.group} | ${finding.name} | ${finding.pinned} | ${finding.latest} | $state |');
  }
  return buffer.toString();
}
