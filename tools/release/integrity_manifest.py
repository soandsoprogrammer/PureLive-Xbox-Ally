#!/usr/bin/env python3
"""Generate or validate additive installer integrity metadata, without networking.

Inputs must be final signed/packaged artifacts, not pre-sign intermediates. The
selected release's installers, the artifact directory, and SHA256SUMS must agree
exactly. Historical records and legacy display fields are preserved; this tool
never changes version.json, publishes assets, or rewrites a feed in place.

Example (all paths are explicit; generation refuses an existing output):
  python3 tools/release/integrity_manifest.py generate --releases draft.json \
      --version pointer.json --artifacts final --sums final/SHA256SUMS.txt \
      --tag v9.0.0 --output verified.json
  python3 tools/release/integrity_manifest.py validate --releases verified.json \
      --version pointer.json --artifacts final --sums final/SHA256SUMS.txt \
      --tag v9.0.0

Rerun validation against downloaded published bytes before changing pointers.
Hashes establish byte coherence with this manifest, not publisher authenticity;
platform signatures and OS verification remain separate requirements.
"""
import argparse
import copy
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

MAX_EXACT_INTEGER = (1 << 53) - 1
SUM_NAMES = frozenset({'SHA256SUMS', 'SHA256SUMS.txt'})
VERSION = re.compile(r'[0-9]+(?:\.[0-9]+)+')
DIGEST = re.compile(r'[0-9a-fA-F]{64}')
PACKAGE = re.compile(r'PureLive-(?P<version>[0-9]+(?:\.[0-9]+)+)-(?P<build>[0-9]+)-(?P<suffix>.+)')
SUFFIX_PLATFORMS = {
    **{f'{prefix}android-{abi}-release.apk': 'android'
       for prefix in ('', 'debug-signed-')
       for abi in ('arm64-v8a', 'armeabi-v7a', 'x86_64')},
    'windows-x64-setup.exe': 'windows',
    'windows-x64-portable.zip': 'windows',
    'linux-x64.tar.gz': 'linux',
    'macos-universal.dmg': 'macos',
    'macos-universal.zip': 'macos',
    'ios-trollstore.ipa': 'ios',
    'ios-unsigned.ipa': 'ios',
}


class ManifestError(ValueError):
    """An ambiguous, malformed or inconsistent release must not be published."""


def exact_integer(value: object, label: str) -> int:
    """Accept only positive integers exactly representable by all consumers."""
    if type(value) is not int or not 0 < value <= MAX_EXACT_INTEGER:
        raise ManifestError(f'{label} 必须是 1～{MAX_EXACT_INTEGER} 的整数')
    return value


def version_name(value: object, label: str) -> str:
    """Normalize only the established optional v/V prefix, not arbitrary text."""
    if not isinstance(value, str):
        raise ManifestError(f'{label} 必须是数字版本字符串')
    normalized = value[1:] if value.startswith(('v', 'V')) else value
    if not VERSION.fullmatch(normalized):
        raise ManifestError(f'{label} 必须是数字点分版本')
    for part in normalized.split('.'):
        if len(part) > 1 and part.startswith('0'):
            raise ManifestError(f'{label} 不能含有前导零')
        if len(part) > 16 or int(part) > MAX_EXACT_INTEGER:
            raise ManifestError(f'{label} 的数字超出范围')
    return normalized


def digest_hex(value: object, label: str) -> str:
    """Do not accept whitespace, filename suffixes or other digest algorithms."""
    if not isinstance(value, str) or not DIGEST.fullmatch(value):
        raise ManifestError(f'{label} 必须是 64 位十六进制 SHA-256')
    return value.lower()


def basename(value: object, label: str) -> str:
    """Installer identities are literal basenames, never relative paths."""
    if (not isinstance(value, str) or not value or value in {'.', '..'}
            or any(c in value for c in '/\\<>:"|?*')
            or any(ord(c) < 32 for c in value) or value != value.strip()):
        raise ManifestError(f'{label} 必须是单个有效文件名')
    return value


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ManifestError(f'JSON 字段重复：{key}')
        result[key] = value
    return result


def read_json(path: Path) -> object:
    """Reject duplicate JSON keys and non-JSON NaN/Infinity extensions."""
    def bad_constant(value: str) -> None:
        raise ManifestError(f'JSON 含有非法数值：{value}')

    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=_unique_object,
                      parse_constant=bad_constant)


def integrity_pair(record: dict, label: str, *, required: bool = False) -> tuple[int, str] | None:
    """Missing legacy pairs differ from present but incomplete or invalid pairs."""
    has_size, has_digest = 'size_bytes' in record, 'sha256' in record
    if not has_size and not has_digest and not required:
        return None
    if not has_size or not has_digest:
        raise ManifestError(f'{label} 缺少完整的 size_bytes 和 sha256')
    return (exact_integer(record['size_bytes'], f'{label}.size_bytes'),
            digest_hex(record['sha256'], f'{label}.sha256'))


def package_identity(name: str) -> tuple[str, int, str]:
    """Recognize the final installer formats currently produced for all platforms."""
    match = PACKAGE.fullmatch(name)
    if match is None or match['suffix'] not in SUFFIX_PLATFORMS:
        raise ManifestError(f'不认识的安装包名称：{name}')
    build_text = match['build']
    if build_text.startswith('0') or len(build_text) > 16:
        raise ManifestError(f'安装包构建号必须是无前导零的有界正整数：{name}')
    return (version_name(match['version'], name), exact_integer(int(build_text), name),
            SUFFIX_PLATFORMS[match['suffix']])


def parse_sums(text: str) -> dict[str, str]:
    """Read strict GNU/shasum SHA256SUMS lines; no paths or duplicate entries."""
    result = {}
    for number, line in enumerate(text.splitlines(), 1):
        if not line:
            continue
        match = re.fullmatch(r'([0-9a-fA-F]{64}) [ *](.+)', line)
        if match is None:
            raise ManifestError(f'SHA256SUMS 第 {number} 行格式错误')
        name = basename(match[2], f'SHA256SUMS 第 {number} 行')
        if name in SUM_NAMES:
            raise ManifestError('SHA256SUMS 不能包含自身的摘要')
        package_identity(name)
        if name in result:
            raise ManifestError(f'SHA256SUMS 文件名重复：{name}')
        result[name] = match[1].lower()
    if not result:
        raise ManifestError('SHA256SUMS 没有安装包记录')
    return result


def _release_base(release: dict, tag: str) -> str:
    value = release.get('github')
    if not isinstance(value, str) or any(ord(c) <= 32 or ord(c) == 127 for c in value):
        raise ManifestError('发布记录缺少有效的 github 发布页')
    try:
        uri = urlsplit(value)
    except ValueError as error:
        raise ManifestError('发布页 URL 格式错误') from error
    match = re.fullmatch(r'/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/releases/tag/([^/]+)', uri.path)
    if (uri.scheme != 'https' or uri.netloc != 'github.com' or uri.query or uri.fragment
            or match is None or match[1] in {'.', '..'} or match[2] in {'.', '..'} or match[3] != tag):
        raise ManifestError('发布页必须是与版本一致的 GitHub HTTPS 标签地址')
    return f'https://github.com/{match[1]}/{match[2]}/releases/download/{tag}/'


def _selected_release(releases: object, version: str) -> dict:
    if not isinstance(releases, list):
        raise ManifestError('releases.json 根节点必须保留为列表')
    selected = None
    versions = set()
    for release in releases:
        if not isinstance(release, dict):
            raise ManifestError('发布记录必须是对象')
        release_version = version_name(release.get('version'), '发布版本')
        if release_version in versions:
            raise ManifestError(f'发布版本重复：{release_version}')
        versions.add(release_version)
        if 'build_number' in release:
            exact_integer(release['build_number'], f'{release_version}.build_number')
        files = release.get('files')
        if not isinstance(files, list):
            raise ManifestError(f'{release_version}.files 必须是列表')
        names = set()
        for record in files:
            if not isinstance(record, dict):
                raise ManifestError(f'{release_version} 的文件记录必须是对象')
            name = basename(record.get('name'), f'{release_version}.name')
            if name in names:
                raise ManifestError(f'发布文件名重复：{name}')
            names.add(name)
            integrity_pair(record, name)
        if release_version == version:
            selected = release
    if selected is None:
        raise ManifestError(f'发布列表缺少版本 {version}')
    return selected


def _effective_settings(pointer: object, platform: str) -> dict:
    if not isinstance(pointer, dict):
        raise ManifestError('version.json 根节点必须是对象')
    platforms = pointer.get('platforms', {})
    if not isinstance(platforms, dict):
        raise ManifestError('version.json.platforms 必须是对象')
    own = platforms.get(platform, {})
    if not isinstance(own, dict):
        raise ManifestError(f'platforms.{platform} 必须是对象')
    return {**pointer, **own}


def _effective_pointer(pointer: object, platform: str) -> tuple[str, int]:
    merged = _effective_settings(pointer, platform)
    return (version_name(merged.get('version'), f'{platform}.version'),
            exact_integer(merged.get('build_number'), f'{platform}.build_number'))


def _check_pointer_coverage(pointer: dict, records: dict, platforms: set[str],
                            version: str, build: int, release_page: str) -> None:
    declared = pointer.get('platforms', {})
    if not isinstance(declared, dict):
        raise ManifestError('version.json.platforms 必须是对象')
    # The root pointer is the legacy Android contract when there is no override.
    required = set()
    for platform in {*declared, 'android'}:
        own_version, own_build = _effective_pointer(pointer, platform)
        if own_version == version:
            if own_build != build:
                raise ManifestError(f'{platform} 的构建号与同版本发布不一致')
            required.add(platform)
    if not required.issubset(platforms):
        missing = ', '.join(sorted(required - platforms))
        raise ManifestError(f'发布缺少版本指针声明的平台安装包：{missing}')
    for platform in platforms:
        if _effective_pointer(pointer, platform) != (version, build):
            raise ManifestError(f'{platform} 的有效版本/构建与安装包不一致')
        merged = _effective_settings(pointer, platform)
        if merged.get('download_url') != release_page:
            raise ManifestError(f'{platform} 的 download_url 与发布页标签不一致')
        if platform == 'windows' and merged.get('windows_msix_available', False) is not False:
            raise ManifestError('当前清单工具不支持声明 MSIX，请提供一致的 EXE/ZIP 发布设置')
        if platform == 'android':
            # Match UpdateInfo's legacy default rather than treating omission as no ABI requirement.
            abis = merged.get('android_abis', ['arm64-v8a'])
            if (not isinstance(abis, list) or not abis
                    or any(abi not in ('arm64-v8a', 'armeabi-v7a', 'x86_64') for abi in abis)
                    or len(set(abis)) != len(abis)):
                raise ManifestError('android_abis 必须是非空且不重复的已知 ABI 列表')
            for abi in abis:
                if not any(name.endswith(f'-android-{abi}-release.apk') for name in records):
                    raise ManifestError(f'发布缺少版本指针声明的 Android ABI：{abi}')


def _file_identity(path: Path) -> tuple[int, str]:
    if path.is_symlink() or not path.is_file():
        raise ManifestError(f'安装包必须是普通文件而不是链接：{path.name}')
    before = path.stat()
    exact_integer(before.st_size, f'{path.name} 字节数')
    digest = hashlib.sha256()
    count = 0
    with path.open('rb') as source:
        while chunk := source.read(1024 * 1024):
            count += len(chunk)
            digest.update(chunk)
    after = path.stat()
    attributes = ('st_size', 'st_mtime_ns', 'st_ctime_ns', 'st_ino', 'st_dev')
    if count != before.st_size or any(getattr(before, key) != getattr(after, key) for key in attributes):
        raise ManifestError(f'读取期间安装包发生变化：{path.name}')
    return count, digest.hexdigest()


def prepare_manifest(releases: object, pointer: object, artifacts: Path, sums: Path,
                     tag: str, *, generate: bool) -> list:
    """Return an independent, verified list; never mutate inputs or publish it.

    All files in the isolated artifact directory must be selected installers or
    the supplied sums file. Combine final artifacts and sums from all platforms
    before validating a release-wide list; undeclared remote assets are unknown.
    Old releases may lack integrity fields, but malformed explicit fields fail.
    """
    version = version_name(tag, '标签')
    if tag != f'v{version}':
        raise ManifestError('发布标签必须使用 v<数字版本>')
    if not isinstance(pointer, dict):
        raise ManifestError('version.json 根节点必须是对象')
    version_name(pointer.get('version'), 'version.json.version')
    exact_integer(pointer.get('build_number'), 'version.json.build_number')
    result = copy.deepcopy(releases)
    release = _selected_release(result, version)
    base = _release_base(release, tag)
    records = {}
    platforms = set()
    builds = set()
    sum_records = []
    for record in release['files']:
        name = record['name']
        if record.get('url') != base + name:
            raise ManifestError(f'文件 URL 的标签、来源或文件名不匹配：{name}')
        if not isinstance(record.get('size'), str):
            raise ManifestError(f'{name}.size 必须保留为显示字符串')
        if type(record.get('downloads')) is not int or record['downloads'] < 0:
            raise ManifestError(f'{name}.downloads 必须保留为非负整数')
        if name in SUM_NAMES:
            if integrity_pair(record, name) is not None:
                raise ManifestError('SHA256SUMS 是辅助文件，不应带安装包完整性字段')
            sum_records.append(name)
            continue
        own_version, build, platform = package_identity(name)
        if own_version != version:
            raise ManifestError(f'安装包版本与发布版本不一致：{name}')
        records[name] = record
        platforms.add(platform)
        builds.add(build)
    if not records or len(builds) != 1:
        raise ManifestError('发布必须包含安装包，且所有安装包构建号一致')
    build = next(iter(builds))
    if 'build_number' in release and release['build_number'] != build:
        raise ManifestError('发布 build_number 与安装包构建号不一致')
    if not generate and 'build_number' not in release:
        raise ManifestError('发布缺少 build_number')
    _check_pointer_coverage(pointer, records, platforms, version, build, release['github'])
    if len(sum_records) > 1:
        raise ManifestError('发布不能同时包含多个 SHA256SUMS 文件')
    if sums.is_symlink() or not sums.is_file():
        raise ManifestError('SHA256SUMS 必须是普通文件而不是链接')
    expected = parse_sums(sums.read_text(encoding='utf-8'))
    if set(expected) != set(records):
        raise ManifestError('SHA256SUMS 与发布安装包集合不一致')
    allowed = set(records)
    if sums.parent.resolve() == artifacts.resolve():
        if sums.name not in SUM_NAMES:
            raise ManifestError('目录内校验文件必须命名为 SHA256SUMS 或 SHA256SUMS.txt')
        allowed.add(sums.name)
    if sum_records and (sums.name != sum_records[0]
                        or sums.resolve() != (artifacts / sum_records[0]).resolve()):
        raise ManifestError('发布的 SHA256SUMS 必须是本次验证的目录内文件')
    if not artifacts.is_dir():
        raise ManifestError('最终安装包目录不存在')
    if {path.name for path in artifacts.iterdir()} != allowed:
        raise ManifestError('最终安装包目录与发布/SHA256SUMS 的文件集合不一致')
    for name, record in records.items():
        actual = _file_identity(artifacts / name)
        if actual[1] != expected[name]:
            raise ManifestError(f'最终安装包与 SHA256SUMS 不一致：{name}')
        declared = integrity_pair(record, name, required=not generate)
        if declared is not None and declared != actual:
            raise ManifestError(f'安装包与已有完整性元数据不一致：{name}')
        record['size_bytes'], record['sha256'] = actual
    release['build_number'] = build
    return result


def _write_new(path: Path, data: list) -> None:
    """Do not overwrite a feed, input, or another previously generated output."""
    with path.open('x', encoding='utf-8') as output:
        try:
            json.dump(data, output, ensure_ascii=False, indent=2, allow_nan=False)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        except BaseException:
            output.close()
            path.unlink(missing_ok=True)
            raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='离线生成或校验最终安装包的完整性清单，不发布文件')
    parser.add_argument('command', choices=('generate', 'validate'))
    parser.add_argument('--releases', required=True, type=Path)
    parser.add_argument('--version', required=True, type=Path)
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--sums', required=True, type=Path)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    if (args.command == 'generate') != (args.output is not None):
        parser.error('generate 必须指定新 --output；validate 不写输出文件')
    try:
        result = prepare_manifest(read_json(args.releases), read_json(args.version),
                                  args.artifacts, args.sums, args.tag,
                                  generate=args.command == 'generate')
        if args.output is not None:
            _write_new(args.output, result)
        print('release: 最终安装包字节数和 SHA-256 校验通过；未发布任何文件')
        return 0
    except (OSError, ValueError) as error:
        print(f'release: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
