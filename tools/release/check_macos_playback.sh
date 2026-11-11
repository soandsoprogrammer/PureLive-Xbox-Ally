#!/usr/bin/env bash
# Disposable native probe: generated video, no accounts or platform URLs.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root/apps/pure_live"
fixture="$(python3 -c 'import base64,sys; print(base64.b64encode(open(sys.argv[1],"rb").read()).decode())' test/native/fixtures/playback.mp4)"
flutter build macos --debug --target test/native/desktop_playback_smoke.dart --dart-define="PURELIVE_PLAYBACK_FIXTURE=$fixture"
unset fixture
binary="$PWD/build/macos/Build/Products/Debug/PureLive.app/Contents/MacOS/PureLive"
shots="$root/shots/macos-desktop-playback"
mkdir -p "$shots"
cover_work="$(mktemp -d)"
cat > "$cover_work/cover.swift" <<'SWIFT'
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!
let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.backgroundColor = .black
window.isOpaque = true
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
let label = NSTextField(labelWithString: "原生窗口遮挡测试")
label.textColor = .white
label.frame = NSRect(x: 40, y: 80, width: 400, height: 50)
window.contentView!.addSubview(label)
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
SWIFT
swiftc "$cover_work/cover.swift" -o "$cover_work/cover"
"$binary" > "$shots/stdout.log" 2> "$shots/stderr.log" &
owned_pid=$!
cover_pid=''
proof=''
stop_owned() {
  local pid="$1" expected="$2" actual
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    actual="$(ps -ww -p "$pid" -o command= | sed 's/^[[:space:]]*//')"
    [[ "$actual" == "$expected" ]] || { echo 'Native probe process identity changed'; return 1; }
    kill -TERM "$pid" 2>/dev/null || true
    for attempt in $(seq 1 5); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      actual="$(ps -ww -p "$pid" -o command= | sed 's/^[[:space:]]*//')"
      [[ "$actual" == "$expected" ]] || { echo 'Native probe process identity changed'; return 1; }
      kill -KILL "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  fi
  return 0
}
collect_proof() {
  if [[ -n "$proof" ]]; then
    for name in stage.json result.json; do
      [[ ! -f "$(dirname "$proof")/$name" ]] || cp "$(dirname "$proof")/$name" "$shots/"
    done
  fi
  python3 - "$shots" <<'PY'
from pathlib import Path
import re,sys
for p in Path(sys.argv[1]).glob('*.log'):
    text=p.read_text(errors='replace')
    p.write_text(re.sub(r'http://127\.0\.0\.1:\d+/[A-Za-z0-9_=-]+/?','[REDACTED_SECRET]',text))
PY
}
cleanup() {
  local outcome=$?
  trap - EXIT
  stop_owned "$cover_pid" "$cover_work/cover" || outcome=1
  stop_owned "$owned_pid" "$binary" || outcome=1
  collect_proof || outcome=1
  exit "$outcome"
}
trap cleanup EXIT
phase() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["stage"])' "$proof" 2>/dev/null || true; }
for attempt in $(seq 1 90); do
  proof="$(find "$HOME/Library/Containers/com.mystyle.pureLive" "${TMPDIR:-/tmp}" -path '*/purelive-desktop-playback-smoke/stage.json' -print -quit 2>/dev/null || true)"
  if [[ -n "$proof" ]]; then
    [[ "$(phase)" == cover_now ]] && break
    [[ -f "$(dirname "$proof")/result.json" ]] && break
  fi
  kill -0 "$owned_pid"
  sleep 1
done
test -n "$proof"
if [[ "$(phase)" != cover_now ]]; then
  cat "$proof"
  [[ ! -f "$(dirname "$proof")/result.json" ]] || cat "$(dirname "$proof")/result.json"
  exit 1
fi
screencapture -x "$shots/visible.png"
"$cover_work/cover" > "$shots/cover.log" 2>&1 &
cover_pid=$!
sleep 2
screencapture -x "$shots/covered.png"
for attempt in $(seq 1 60); do
  [[ "$(phase)" == uncover_now ]] && break
  [[ -f "$(dirname "$proof")/result.json" ]] && break
  kill -0 "$owned_pid"
  sleep 1
done
[[ "$(phase)" == uncover_now ]]
stop_owned "$cover_pid" "$cover_work/cover"
cover_pid=''
result="$(dirname "$proof")/result.json"
for attempt in $(seq 1 90); do
  [[ -f "$result" ]] && break
  kill -0 "$owned_pid"
  sleep 1
done
test -f "$result"
collect_proof
screencapture -x "$shots/restored.png"
python3 -c 'import json,sys; v=json.load(open(sys.argv[1])); print(v); assert v["passed"] and v["operating_system"]=="macos" and v["occlusion"]["hidden_event_seen"] and v["occlusion"]["position_advanced"]' "$result"
