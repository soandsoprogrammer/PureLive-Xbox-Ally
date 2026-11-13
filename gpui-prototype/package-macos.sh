#!/usr/bin/env bash
set -euo pipefail

arch=$1
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
cargo build --manifest-path gpui-prototype/Cargo.toml --release --locked

app='dist/PureLive.app'
bin="$app/Contents/MacOS"
resources="$app/Contents/Resources"
mkdir -p "$bin" "$resources"
install -m 755 gpui-prototype/target/release/purelive-gpui "$bin/purelive-gpui"
dart compile exe tools/live_cli/bin/handheld_platforms.dart -o "$bin/purelive-platforms"
cp LICENSE "$resources/"
cp gpui-prototype/Cargo.lock pubspec.lock "$resources/"
install -m 644 gpui-prototype/assets/app.icns "$resources/PureLive.icns"
grep -v -E 'libmpv|Microsoft' THIRD_PARTY.md > "$resources/THIRD_PARTY.md"
printf '\nmacOS playback uses AVFoundation and OxideAV.\n' >> "$resources/THIRD_PARTY.md"
triple=$(rustc -vV | sed -n 's/^host: //p')
cargo metadata --manifest-path gpui-prototype/Cargo.toml --locked --filter-platform "$triple" --format-version 1 > dist/cargo-metadata.json
python3 - "$resources" <<'PY'
import json, pathlib, shutil, sys
root = pathlib.Path(sys.argv[1]) / 'licenses'
metadata = json.loads(pathlib.Path('dist/cargo-metadata.json').read_text())
active = {node['id'] for node in metadata['resolve']['nodes']}
for pkg in metadata['packages']:
    if pkg['id'] not in active or pkg['source'] is None:
        continue
    target = root / 'rust' / (pkg['name'] + '-' + pkg['version'])
    for path in pathlib.Path(pkg['manifest_path']).parent.iterdir():
        if path.is_file() and path.name.lower().startswith(('license', 'copying', 'notice')):
            target.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target / path.name)
for path in pathlib.Path.home().glob('.pub-cache/hosted/pub.dev/*/LICENSE*'):
    target = root / 'dart' / path.parent.name
    target.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, target / path.name)
PY

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PureLive</string>
  <key>CFBundleDisplayName</key><string>纯粹直播</string>
  <key>CFBundleExecutable</key><string>purelive-gpui</string>
  <key>CFBundleIdentifier</key><string>io.github.soandsoprogrammer.purelive</string>
  <key>CFBundleIconFile</key><string>PureLive.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict>
    <key>NSAllowsArbitraryLoadsForMedia</key><true/>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
</dict></plist>
PLIST

plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$bin/purelive-platforms"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
file "$bin/purelive-gpui" "$bin/purelive-platforms"
catalog=$(printf '%s\n' '{"action":"catalog","platform":"bilibili","query":""}' | "$bin/purelive-platforms")
grep -q 'bilibili' <<< "$catalog"
if find "$app" -type f \( -iname '*.mp4' -o -iname '*.flv' -o -iname '*.m4s' -o -iname '*.ts' -o -iname '*.m3u8' -o -iname '*libmpv*' \) | grep .; then
  exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/PureLive-macOS-$arch.zip"

if launchctl print "gui/$(id -u)" >/dev/null 2>&1; then
  export PURELIVE_PROFILE_ROOT="$RUNNER_TEMP/purelive-smoke"
  "$bin/purelive-gpui" --probe smoke > "$RUNNER_TEMP/purelive-smoke.log" 2>&1 &
  pid=$!
  trap 'kill "$pid" 2>/dev/null || true' EXIT
  for attempt in {1..25}; do
    if grep -q '^first_frame_ms=' "$PURELIVE_PROFILE_ROOT/PureLiveRust/probe.log" 2>/dev/null; then
      echo 'The app rendered its first window frame.'
      exit 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 1
  done
  cat "$RUNNER_TEMP/purelive-smoke.log"
  exit 1
fi
echo 'GUI smoke skipped because the runner has no logged-in GUI session.'
