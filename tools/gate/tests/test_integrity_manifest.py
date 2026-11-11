"""Offline release integrity fixtures; no real installers, feeds or networking."""
import contextlib
import copy
import hashlib
import io
import json
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'release'))

import integrity_manifest as manifest  # noqa: E402


class IntegrityManifestTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.artifacts = self.root / 'final'
        self.artifacts.mkdir()
        self.version = '9.0.0'
        self.build = 6000
        self.tag = 'v9.0.0'
        self.base = f'https://github.com/example/PureLive/releases/download/{self.tag}/'
        suffixes = [
            'debug-signed-android-arm64-v8a-release.apk',
            'debug-signed-android-armeabi-v7a-release.apk',
            'debug-signed-android-x86_64-release.apk',
            'windows-x64-setup.exe',
            'windows-x64-portable.zip',
            'linux-x64.tar.gz',
            'macos-universal.dmg',
            'macos-universal.zip',
            'ios-trollstore.ipa',
            'ios-unsigned.ipa',
        ]
        self.names = [f'PureLive-{self.version}-{self.build}-{suffix}' for suffix in suffixes]
        for index, name in enumerate(self.names):
            (self.artifacts / name).write_bytes(f'final fixture {index}: {name}'.encode())
        self.sums = self.artifacts / 'SHA256SUMS.txt'
        self.write_sums()
        self.releases = [{
            'version': self.version,
            'title': 'Fixture release',
            'date': '2026-01-01',
            'github': f'https://github.com/example/PureLive/releases/tag/{self.tag}',
            'author': {'name': 'fixture'},
            'changelog': 'Synthetic final bytes, not installable artifacts.',
            'files': [self.file_record(name) for name in ['SHA256SUMS.txt', *self.names]],
        }, {
            'version': '3.2.11',
            'title': 'Legacy history',
            'files': [{'name': 'legacy.apk', 'size': '12.34mb', 'downloads': 2,
                       'url': 'https://example.invalid/legacy.apk'}],
        }]
        self.pointer = {'version': self.version, 'build_number': self.build, 'version_num': 900006000,
                        'download_url': f'https://github.com/example/PureLive/releases/tag/{self.tag}',
                        'android_abis': ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
                        'platforms': {platform: {'version': self.version, 'build_number': self.build,
                                                'retained_setting': True}
                                      for platform in ('android', 'windows', 'linux', 'macos', 'ios')}}

    def file_record(self, name):
        return {'name': name, 'size': '12.34mb', 'downloads': 7, 'url': self.base + name,
                'retained_field': 'unchanged'}

    def write_sums(self):
        self.sums.write_text(''.join(f'{self.hash_of(name)}  {name}\n' for name in self.names), encoding='utf-8')

    def hash_of(self, name):
        return hashlib.sha256((self.artifacts / name).read_bytes()).hexdigest()

    def prepare(self, *, generate=True):
        return manifest.prepare_manifest(self.releases, self.pointer, self.artifacts, self.sums,
                                         self.tag, generate=generate)

    def expect_invalid(self, *, generate=True):
        with self.assertRaises(manifest.ManifestError):
            self.prepare(generate=generate)

    def test_generates_all_ten_final_byte_identities_without_mutating_legacy_fields(self):
        original_releases, original_pointer = copy.deepcopy(self.releases), copy.deepcopy(self.pointer)
        result = self.prepare()
        self.assertEqual(self.releases, original_releases)
        self.assertEqual(self.pointer, original_pointer)
        self.assertIsInstance(result, list)
        self.assertEqual(result[1], original_releases[1])
        self.assertEqual(result[0]['build_number'], self.build)
        self.assertEqual(result[0]['files'][0], original_releases[0]['files'][0])
        for before, after in zip(original_releases[0]['files'][1:], result[0]['files'][1:]):
            self.assertEqual({key: after[key] for key in before}, before)
            self.assertEqual(after['size_bytes'], (self.artifacts / before['name']).stat().st_size)
            self.assertEqual(after['sha256'], self.hash_of(before['name']))
        self.releases = result
        self.assertEqual(self.prepare(generate=False), result)

    def test_representative_legacy_reader_ignores_additive_fields(self):
        def read_legacy(releases):
            return [(release['version'], [(f['name'], f['size'], f['downloads'], f['url'])
                                         for f in release['files']]) for release in releases]
        self.assertEqual(read_legacy(self.prepare()), read_legacy(self.releases))

    def test_validate_requires_release_build_and_every_installer_pair(self):
        result = self.prepare()
        for mutation in ('release_build', 'all_pairs', 'one_pair'):
            with self.subTest(mutation=mutation):
                self.releases = copy.deepcopy(result)
                if mutation == 'release_build':
                    del self.releases[0]['build_number']
                else:
                    records = self.releases[0]['files'][1:] if mutation == 'all_pairs' else self.releases[0]['files'][1:2]
                    for record in records:
                        del record['size_bytes']
                        del record['sha256']
                self.expect_invalid(generate=False)

    def test_present_invalid_pairs_do_not_become_absent_legacy_metadata(self):
        original = copy.deepcopy(self.releases)
        invalid = [
            {'size_bytes': 20}, {'sha256': 'a' * 64},
            {'size_bytes': None, 'sha256': 'a' * 64},
            {'size_bytes': 20, 'sha256': None},
            *[{'size_bytes': size, 'sha256': 'a' * 64}
              for size in (True, False, 0, -1, 3.2, '20', manifest.MAX_EXACT_INTEGER + 1)],
            *[{'size_bytes': 20, 'sha256': digest}
              for digest in ('', 'a' * 63, 'g' * 64, 'a' * 65, 'a' * 64 + '\n', 'a' * 64 + ' file')],
        ]
        for fields in invalid:
            with self.subTest(fields=fields):
                self.releases = copy.deepcopy(original)
                self.releases[0]['files'][1].update(fields)
                self.expect_invalid()

    def test_malformed_historical_explicit_metadata_is_not_silently_published(self):
        self.releases[1]['files'][0]['sha256'] = 'invalid'
        self.expect_invalid()

    def test_uppercase_hex_is_normalized_not_rejected(self):
        self.releases = self.prepare()
        for record in self.releases[0]['files'][1:]:
            record['sha256'] = record['sha256'].upper()
        self.sums.write_text(self.sums.read_text().replace('  ', ' *'), encoding='utf-8')
        result = self.prepare(generate=False)
        for record in result[0]['files'][1:]:
            self.assertEqual(record['sha256'], self.hash_of(record['name']))

    def test_metadata_conflicts_with_final_bytes_are_not_overwritten(self):
        result = self.prepare()
        for key, value in [('size_bytes', 1), ('sha256', '0' * 64)]:
            with self.subTest(key=key):
                self.releases = copy.deepcopy(result)
                self.releases[0]['files'][1][key] = value
                self.expect_invalid()
                self.expect_invalid(generate=False)

    def test_modified_final_bytes_fail_against_sums(self):
        self.releases = self.prepare()
        path = self.artifacts / self.names[0]
        path.write_bytes(b'x' * path.stat().st_size)
        self.expect_invalid()

    def test_artifacts_are_hashed_as_streams(self):
        with mock.patch.object(Path, 'read_bytes', side_effect=AssertionError('whole-file allocation')):
            result = self.prepare()
        self.assertEqual(len(result[0]['files']), 11)

    def test_changed_during_hash_read_is_rejected(self):
        path = self.artifacts / self.names[0]
        original_sha = hashlib.sha256

        class ChangingDigest:
            def __init__(self):
                self.inner = original_sha()

            def update(self, chunk):
                self.inner.update(chunk)
                path.write_bytes(b'replaced during verification')

            def hexdigest(self):
                return self.inner.hexdigest()

        with mock.patch.object(manifest.hashlib, 'sha256', ChangingDigest):
            with self.assertRaises(manifest.ManifestError):
                manifest._file_identity(path)

    def test_empty_artifact_fails_even_with_matching_sums(self):
        (self.artifacts / self.names[0]).write_bytes(b'')
        self.write_sums()
        self.expect_invalid()

    def test_symlink_artifact_is_not_a_final_file(self):
        path = self.artifacts / self.names[0]
        outside = self.root / 'intermediate.apk'
        path.rename(outside)
        path.symlink_to(outside)
        self.expect_invalid()

    def test_missing_or_unrecognized_directory_artifact_fails(self):
        path = self.artifacts / self.names[0]
        contents = path.read_bytes()
        path.unlink()
        self.expect_invalid()
        path.write_bytes(contents)
        (self.artifacts / 'unlisted.apk').write_bytes(b'unlisted')
        self.expect_invalid()

    def test_omitted_manifest_asset_is_not_declared_verified(self):
        self.releases[0]['files'].pop()
        self.expect_invalid()

    def test_malformed_root_and_duplicate_version_fail(self):
        original = copy.deepcopy(self.releases)
        self.releases = {'releases': original}
        self.expect_invalid()
        self.releases = [*original, copy.deepcopy(original[0])]
        self.expect_invalid()
        self.releases[-1]['version'] = 'v9.0.0'
        self.expect_invalid()

    def test_duplicate_file_fails_even_when_identical(self):
        self.releases[0]['files'].append(copy.deepcopy(self.releases[0]['files'][1]))
        self.expect_invalid()

    def test_missing_or_wrong_selected_version_fails(self):
        self.releases[0]['version'] = '9.0.1'
        self.expect_invalid()

    def test_strict_version_and_build_fields(self):
        original = copy.deepcopy(self.releases)
        for value in (True, None, 0, -1, 6000.0, '6000', manifest.MAX_EXACT_INTEGER + 1, 6001):
            with self.subTest(build=value):
                self.releases = copy.deepcopy(original)
                self.releases[0]['build_number'] = value
                self.expect_invalid()
        for value in (' 9.0.0', '9.0.0\n', '9..0', '09.0.0', '9.0.0-beta', '9.' + '9' * 5000, 9):
            with self.subTest(version=value):
                self.releases = copy.deepcopy(original)
                self.releases[0]['version'] = value
                self.expect_invalid()

    def test_release_page_and_tag_must_agree(self):
        original = self.releases[0]['github']
        for url in (original.replace('v9.0.0', 'v9.0.1'), original.replace('https:', 'http:'),
                    original + '?cache=1', original + '#tag', original + '\n',
                    original.replace('/example/', '/exa\nmple/'), original.replace('/example/', '/../'),
                    original.replace('github.com', 'example.invalid')):
            with self.subTest(url=url):
                self.releases[0]['github'] = url
                self.expect_invalid()
        self.releases[0]['github'] = original
        for tag in ('9.0.0', 'V9.0.0', 'v9.0.1', 'v9.0.0\n'):
            with self.subTest(tag=tag):
                self.tag = tag
                self.expect_invalid()

    def test_url_basename_source_and_tag_cannot_conflict(self):
        record = self.releases[0]['files'][1]
        original = record['url']
        for url in (original + '?download=1', original + '#asset', original.replace('6000', '6001'),
                    original.replace('v9.0.0/', 'v9.0.1/'), original.replace('github.com', 'example.invalid'),
                    original.replace('https:', 'http:')):
            with self.subTest(url=url):
                record['url'] = url
                self.expect_invalid()

    def test_unrecognized_and_mixed_build_installers_fail(self):
        original = self.names[0]
        for name in (original.replace('-6000-', '-6001-'), original.replace('-9.0.0-', '-9.0.1-'),
                     original.replace('-6000-', '-06000-'), original.replace('arm64-v8a', 'mystery'),
                     'release-notes.txt'):
            with self.subTest(name=name):
                record = self.releases[0]['files'][1]
                record.update(name=name, url=self.base + name)
                self.expect_invalid()

    def test_filename_cannot_be_path_or_control_text(self):
        for name in ('../artifact.apk', 'folder/artifact.apk', 'folder\\artifact.apk', '.', '', 'file\n.apk'):
            with self.subTest(name=name):
                with self.assertRaises(manifest.ManifestError):
                    manifest.basename(name, 'fixture')

    def test_all_current_platform_names_and_plain_android_names_parse(self):
        platforms = [manifest.package_identity(name)[2] for name in self.names]
        self.assertEqual(platforms, ['android'] * 3 + ['windows'] * 2 + ['linux'] + ['macos'] * 2 + ['ios'] * 2)
        for name in self.names[:3]:
            version, build, platform = manifest.package_identity(name.replace('debug-signed-', ''))
            self.assertEqual((version, build, platform), (self.version, self.build, 'android'))

    def test_effective_platform_overrides_are_used_and_preserved(self):
        self.pointer['version'] = '8.0.0'
        self.pointer['build_number'] = 5000
        before = copy.deepcopy(self.pointer)
        self.prepare()
        self.assertEqual(self.pointer, before)
        self.pointer['platforms']['ios']['build_number'] = 5999
        self.expect_invalid()

    def test_missing_platform_override_falls_back_to_root(self):
        del self.pointer['platforms']['windows']
        self.prepare()
        self.pointer['build_number'] = True
        self.expect_invalid()

    def omit_artifacts(self, names):
        for name in names:
            (self.artifacts / name).unlink()
        self.names = [name for name in self.names if name not in names]
        self.releases[0]['files'] = [record for record in self.releases[0]['files'] if record['name'] not in names]
        self.write_sums()

    def test_consistently_omitted_current_platform_fails_pointer_coverage(self):
        self.omit_artifacts([name for name in self.names if '-ios-' in name])
        self.expect_invalid()

    def test_consistently_omitted_declared_android_abi_fails_pointer_coverage(self):
        self.omit_artifacts([name for name in self.names if '-android-armeabi-v7a-' in name])
        self.expect_invalid()

    def test_intentionally_older_platform_override_does_not_require_new_artifacts(self):
        self.omit_artifacts([name for name in self.names if '-ios-' in name])
        self.pointer['platforms']['ios'].update(version='8.0.0', build_number=5000)
        result = self.prepare()
        self.assertEqual(len(result[0]['files']), 9)

    def test_effective_download_page_must_match_selected_release(self):
        self.pointer['platforms']['macos']['download_url'] = self.pointer['download_url'].replace('v9.0.0', 'v8.0.0')
        self.expect_invalid()

    def test_abi_metadata_must_be_nonempty_known_unique_list(self):
        for abis in ([], None, 'arm64-v8a', ['arm64-v8a', 'arm64-v8a'], ['unknown'], [True]):
            with self.subTest(abis=abis):
                self.pointer['android_abis'] = abis
                self.expect_invalid()

    def test_missing_android_abis_keeps_client_arm64_default(self):
        del self.pointer['android_abis']
        self.omit_artifacts([name for name in self.names if '-android-arm64-v8a-' in name])
        self.expect_invalid()

    def test_unsupported_msix_pointer_is_not_validated_as_exe_only(self):
        for value in (True, 'true', 1):
            with self.subTest(value=value):
                self.pointer['platforms']['windows']['windows_msix_available'] = value
                self.expect_invalid()

    def test_malformed_platform_override_fails(self):
        for value in (None, [], '9.0.0', 6000):
            with self.subTest(value=value):
                self.pointer['platforms']['macos'] = value
                self.expect_invalid()

    def test_sums_is_not_an_installer_and_has_no_self_hash(self):
        generated = self.prepare()
        self.assertNotIn('sha256', generated[0]['files'][0])
        with self.assertRaises(manifest.ManifestError):
            manifest.package_identity('SHA256SUMS.txt')
        self.sums.write_text(self.sums.read_text() + 'a' * 64 + '  SHA256SUMS.txt\n')
        self.expect_invalid()

    def test_sums_rejects_duplicate_missing_extra_and_malformed_entries(self):
        original = self.sums.read_text()
        for text in (original + original.splitlines()[0] + '\n', '\n'.join(original.splitlines()[1:]),
                     original + 'a' * 64 + '  unrecognized.apk\n', 'a' * 63 + '  ' + self.names[0],
                     'a' * 64 + '  ../' + self.names[0], 'a' * 64 + '  ' + self.names[0] + ' ', ''):
            with self.subTest(text=text[:80]):
                self.sums.write_text(text, encoding='utf-8')
                self.expect_invalid()

    def test_sums_file_in_manifest_is_exactly_the_verified_file(self):
        alternate = self.root / 'SHA256SUMS.txt'
        alternate.write_text(self.sums.read_text(), encoding='utf-8')
        self.sums = alternate
        self.expect_invalid()

    def test_legacy_size_and_download_fields_are_not_reinterpreted(self):
        original = copy.deepcopy(self.releases)
        for fields in ({'size': 12}, {'size': None}, {'downloads': -1}, {'downloads': True}):
            with self.subTest(fields=fields):
                self.releases = copy.deepcopy(original)
                self.releases[0]['files'][1].update(fields)
                self.expect_invalid()

    def test_json_loader_rejects_duplicate_keys_and_non_json_numbers(self):
        path = self.root / 'input.json'
        for text in ('{"size_bytes":1,"size_bytes":2}', '{"size_bytes":NaN}', '{"size_bytes":Infinity}'):
            with self.subTest(text=text):
                path.write_text(text, encoding='utf-8')
                with self.assertRaises(manifest.ManifestError):
                    manifest.read_json(path)

    def cli_args(self, command, releases):
        pointer_path = self.root / 'pointer.json'
        pointer_path.write_text(json.dumps(self.pointer), encoding='utf-8')
        return [command, '--releases', str(releases), '--version', str(pointer_path),
                '--artifacts', str(self.artifacts), '--sums', str(self.sums), '--tag', self.tag]

    def test_cli_generates_new_file_validates_and_does_not_rewrite_inputs(self):
        input_path = self.root / 'draft.json'
        original_text = json.dumps(self.releases)
        input_path.write_text(original_text, encoding='utf-8')
        output_path = self.root / 'verified.json'
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(manifest.main(self.cli_args('generate', input_path) + ['--output', str(output_path)]), 0)
            self.assertEqual(manifest.main(self.cli_args('validate', output_path)), 0)
        self.assertEqual(input_path.read_text(), original_text)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(manifest.main(self.cli_args('generate', input_path) + ['--output', str(input_path)]), 1)
        self.assertEqual(input_path.read_text(), original_text)

    def test_cli_requires_explicit_new_output_only_for_generation(self):
        path = self.root / 'draft.json'
        path.write_text(json.dumps(self.releases), encoding='utf-8')
        for args in (self.cli_args('generate', path), self.cli_args('validate', path) + ['--output', str(path)]):
            with self.subTest(command=args[0]), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    manifest.main(args)

    def test_cli_failure_does_not_create_output(self):
        path = self.root / 'draft.json'
        path.write_text(json.dumps(self.releases), encoding='utf-8')
        (self.artifacts / self.names[-1]).write_bytes(b'changed after signing')
        output_path = self.root / 'verified.json'
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(manifest.main(self.cli_args('generate', path) + ['--output', str(output_path)]), 1)
        self.assertFalse(output_path.exists())


if __name__ == '__main__':
    unittest.main()
