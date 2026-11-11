import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/version/update_feed.dart';

const _digest = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _version = '5.4.18';
const _build = 5122;
const _info = UpdateInfo(version: _version, buildNumber: _build);
const _names = [
  'PureLive-5.4.18-5122-debug-signed-android-arm64-v8a-release.apk',
  'PureLive-5.4.18-5122-debug-signed-android-armeabi-v7a-release.apk',
  'PureLive-5.4.18-5122-debug-signed-android-x86_64-release.apk',
  'PureLive-5.4.18-5122-ios-trollstore.ipa',
  'PureLive-5.4.18-5122-ios-unsigned.ipa',
  'PureLive-5.4.18-5122-linux-x64.tar.gz',
  'PureLive-5.4.18-5122-macos-universal.dmg',
  'PureLive-5.4.18-5122-macos-universal.zip',
  'PureLive-5.4.18-5122-windows-x64-portable.zip',
  'PureLive-5.4.18-5122-windows-x64-setup.exe',
];

Map<String, Object?> _file({String? name, Map<String, Object?> metadata = const {}}) {
  final filename = name ?? _names.first;
  return {
    'name': filename,
    'size': '123.45mb',
    'downloads': 7,
    'url': 'https://github.com/wzgrx/PureLive/releases/download/v$_version/$filename',
    ...metadata,
  };
}

Map<String, Object?> _release({Map<String, Object?> metadata = const {}, List<Object?>? files}) => {
  'version': _version,
  'date': '2026-10-25',
  'title': 'fixture',
  'files':
      files ??
      [
        _file(metadata: {'size_bytes': 12345, 'sha256': _digest}),
      ],
  ...metadata,
};

void main() {
  group('additive release integrity metadata', () {
    test('all ten current package names retain version/build identity', () {
      final release = ReleaseInfo.fromJson(
        _release(
          metadata: {'build_number': _build},
          files: [
            for (final name in _names) _file(name: name, metadata: {'size_bytes': 12345, 'sha256': _digest}),
          ],
        ),
      );
      expect(release.buildNumber, _build);
      expect(filesForUpdate(_info, [release]), hasLength(10));
      for (final file in release.files) {
        expect(file.hasIntegrity, isTrue, reason: file.name);
        expect(release.matchesFileBuild(file), isTrue, reason: file.name);
        expect(file.size, '123.45mb');
      }
    });

    test('legacy fields remain readable and do not claim integrity', () {
      final original = _release(files: [_file()]);
      final release = parseReleases([original]).single;
      expect(release.buildNumber, isNull);
      expect(release.buildNumberMalformed, isFalse);
      expect(release.files.single.hasIntegrity, isFalse);
      expect(release.files.single.hasInvalidIntegrity, isFalse);
      expect(release.files.single.sizeBytes, isNull, reason: 'rounded display size is not exact bytes');
      expect(filesForUpdate(_info, [release]), hasLength(1), reason: 'legacy identity stays readable');
    });

    test('additive fields preserve a representative 3.x known-field reader', () {
      final original = _release(files: [_file()]);
      final extended = _release(metadata: {'build_number': _build});
      Map<String, Object?> legacyRead(Map<String, Object?> record) => {
        for (final key in ['version', 'date', 'title']) key: record[key],
        'files': [
          for (final file in (record['files']! as List).cast<Map<String, Object?>>())
            {
              for (final key in ['name', 'size', 'downloads', 'url']) key: file[key],
            },
        ],
      };
      expect(legacyRead(extended), legacyRead(original));
      expect([extended], isA<List<Object?>>(), reason: 'the published history stays a root list');
    });

    test('uppercase SHA is normalized without accepting decorated digests', () {
      final file = ReleaseFile.fromJson(_file(metadata: {'size_bytes': 12345, 'sha256': _digest.toUpperCase()}));
      expect(file.sha256, _digest);
      expect(file.hasIntegrity, isTrue);
      for (final digest in [null, '', 'abc', '${_digest}0', 'g${_digest.substring(1)}', ' $_digest', '$_digest\n']) {
        final bad = ReleaseFile.fromJson(_file(metadata: {'size_bytes': 12345, 'sha256': digest}));
        expect(bad.hasInvalidIntegrity, isTrue, reason: '$digest');
        expect(bad.hasIntegrity, isFalse);
        expect(fileMatchesUpdate(_info, bad), isFalse);
      }
    });

    test('exact size accepts only a positive bounded JSON integer', () {
      for (final value in <Object?>[null, true, false, 0, -1, 1.0, 1.5, '12345', 9007199254740992]) {
        final file = ReleaseFile.fromJson(_file(metadata: {'size_bytes': value, 'sha256': _digest}));
        expect(file.hasInvalidIntegrity, isTrue, reason: '$value');
        expect(file.hasIntegrity, isFalse);
        expect(fileMatchesUpdate(_info, file), isFalse);
      }
      expect(
        ReleaseFile.fromJson(_file(metadata: {'size_bytes': 9007199254740991, 'sha256': _digest})).hasIntegrity,
        isTrue,
      );
    });

    test('incomplete pairs remain invalid, including null explicit fields', () {
      for (final pair in [
        {'size_bytes': 12345},
        {'sha256': _digest},
        {'size_bytes': null},
        {'sha256': null},
      ]) {
        final file = ReleaseFile.fromJson(_file(metadata: pair));
        expect(file.hasInvalidIntegrity, isTrue);
        expect(file.hasIntegrity, isFalse);
      }
      final numericDisplay = ReleaseFile.fromJson({..._file(), 'size': 1024});
      expect(numericDisplay.size, '0.00mb');
      expect(numericDisplay.sizeBytes, isNull, reason: 'GitHub size remains display-only');
    });

    test('malformed or conflicting release builds cannot fall back to filenames', () {
      for (final value in <Object?>[null, true, 0, -1, 5122.0, '5122', 9007199254740992, 5121, 5123]) {
        final release = ReleaseInfo.fromJson(_release(metadata: {'build_number': value}));
        expect(filesForUpdate(_info, [release]), isEmpty, reason: '$value');
        expect(release.matchesFileBuild(release.files.single), isFalse, reason: '$value');
      }
      final filenameMismatch = ReleaseInfo.fromJson(
        _release(
          metadata: {'build_number': _build},
          files: [_file(name: _names.first.replaceFirst('-5122-', '-5121-'))],
        ),
      );
      expect(filesForUpdate(_info, [filenameMismatch]), isEmpty);
      expect(filenameMismatch.matchesFileBuild(filenameMismatch.files.single), isFalse);
    });

    test('one malformed file does not hide valid files or other history records', () {
      final releases = parseReleases([
        _release(
          files: [
            _file(metadata: {'size_bytes': 12345, 'sha256': 'bad'}),
            _file(name: _names.last, metadata: {'size_bytes': 12345, 'sha256': _digest}),
          ],
        ),
        _release(metadata: {'version': '5.4.17'}),
      ]);
      expect(releases, hasLength(2));
      expect(releases.first.files, hasLength(2));
      expect(filesForUpdate(_info, releases).single.name, _names.last);
    });

    test('public package picker skips malformed metadata even without a snapshot', () {
      final malformed = ReleaseFile.fromJson(_file(metadata: {'size_bytes': 12345, 'sha256': 'bad'}));
      final legacy = ReleaseFile.fromJson(_file());
      final verified = ReleaseFile.fromJson(_file(metadata: {'size_bytes': 12345, 'sha256': _digest}));
      expect(PackageKind.androidArm64.pick([malformed]), isNull);
      expect(PackageKind.androidArm64.pick([malformed, legacy]), same(legacy));
      expect(PackageKind.androidArm64.pick([malformed, verified]), same(verified));
    });

    test('platform override build must agree with additive release metadata', () {
      final info = UpdateInfo.fromJson({
        'version': '9.0.0',
        'build_number': 6000,
        'platforms': {
          'macos': {'version': _version, 'build_number': _build},
        },
      }, platform: 'macos');
      final release = ReleaseInfo.fromJson(
        _release(
          metadata: {'build_number': _build},
          files: [
            _file(name: _names[6], metadata: {'size_bytes': 12345, 'sha256': _digest}),
          ],
        ),
      );
      expect(filesForUpdate(info, [release]).single.name, _names[6]);
      expect(filesForUpdate(const UpdateInfo(version: _version, buildNumber: 6000), [release]), isEmpty);
    });
  });

  group('bounded update sources', () {
    final origin = Uri.parse('https://github.com/fixture/app.apk');
    final mirrors = [for (var i = 0; i < 12; i++) Uri.parse('https://mirror$i.example/app.apk')];

    test('five mirrors plus canonical origin survive the six-source cap', () {
      final selected = boundedDownloadSources([...mirrors, origin], canonical: origin, fastest: mirrors[8]);
      expect(selected, [mirrors[8], mirrors[0], mirrors[1], mirrors[2], mirrors[3], origin]);
    });

    test('fast origin is attempted once at its fast position', () {
      final selected = boundedDownloadSources([...mirrors, origin, origin], canonical: origin, fastest: origin);
      expect(selected.first, origin);
      expect(selected.where((uri) => uri == origin), hasLength(1));
      expect(selected, hasLength(6));
    });

    test('origin-only and deliberately selected source do not synthesize mirrors', () {
      expect(boundedDownloadSources([origin], canonical: origin, fastest: mirrors.first), [origin]);
      expect(boundedDownloadSources([mirrors.first], canonical: origin), [mirrors.first]);
      expect(boundedDownloadSources([], canonical: origin), isEmpty);
      expect(boundedDownloadSources([...mirrors, origin], canonical: origin, limit: 1), [origin]);
    });
  });
}
