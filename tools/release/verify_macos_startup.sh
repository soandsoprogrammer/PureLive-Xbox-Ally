#!/usr/bin/env bash
# Observe the exact signed release ZIP on a fresh hosted Mac (Z02.5).
# Successful logs do not replace manual inspection of the saved frames.
set -euo pipefail
[[ $(uname -s) = Darwin ]] || { echo 'macOS is required'; exit 64; }
archive=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
mkdir -p "$2"
shots=$(cd "$2" && pwd)
root=$(mktemp -d "$RUNNER_TEMP/purelive-package-XXXXXX")
shasum -a 256 "$archive" > "$shots/archive-sha256.txt"
ditto -x -k "$archive" "$root"
app="$root/PureLive.app"
binary="$app/Contents/MacOS/PureLive"
test -x "$binary"
codesign --verify --deep --strict "$app"
codesign -d --entitlements - --xml "$app" > "$shots/entitlements.plist"
plutil -p "$app/Contents/Info.plist" > "$shots/info.txt"
expected=$(/usr/libexec/PlistBuddy -c 'Print :FLTEnableImpeller' "$app/Contents/Info.plist")
[[ "$expected" = false ]] || { echo 'Expected the documented macOS renderer mitigation'; exit 1; }
shasum -a 256 "$binary" > "$shots/binary-before.txt"
sw_vers > "$shots/os.txt"
uname -m > "$shots/architecture.txt"
owned_pid=''
stop_owned() {
  if [[ -n "$owned_pid" ]] && kill -0 "$owned_pid" 2>/dev/null; then
    actual=$(ps -ww -p "$owned_pid" -o command= | sed 's/^[[:space:]]*//')
    [[ "$actual" = "$binary" ]] || { echo 'Owned process identity changed'; return 1; }
    kill -TERM "$owned_pid" 2>/dev/null || true
    sleep 2
    if kill -0 "$owned_pid" 2>/dev/null; then
      actual=$(ps -ww -p "$owned_pid" -o command= | sed 's/^[[:space:]]*//')
      [[ "$actual" = "$binary" ]] || { echo 'Owned process identity changed'; return 1; }
      kill -KILL "$owned_pid" 2>/dev/null || true
    fi
    wait "$owned_pid" 2>/dev/null || true
  fi
  owned_pid=''
}
trap stop_owned EXIT
ui() {
  local operation=$1
  osascript - "$owned_pid" "$operation" <<'APPLESCRIPT'
on run argv
  with timeout of 15 seconds
    tell application "System Events"
      tell (first process whose unix id is (item 1 of argv as integer))
        set frontmost to true
        if item 2 of argv is "menu" then
          click menu bar item 4 of menu bar 1
        else if item 2 of argv is "escape" then
          key code 53
        else if item 2 of argv is "close" then
          click (first button of window 1 whose subrole is "AXCloseButton")
        end if
      end tell
    end tell
  end timeout
end run
APPLESCRIPT
}
failed=0
for trial in 1 2; do
  "$binary" > "$shots/launch-$trial-stdout.log" 2> "$shots/launch-$trial-stderr.log" &
  owned_pid=$!
  started=$(date +%s)
  elapsed=0
  for target in 5 30 90; do
    sleep "$((target-elapsed))"
    elapsed=$target
    if ! kill -0 "$owned_pid" 2>/dev/null; then
      printf 'process ended before %s seconds\n' "$target" >> "$shots/failures.txt"
      failed=1
      break
    fi
    ui front > "$shots/launch-$trial-$target-foreground.log" 2>&1 || true
    screencapture -x "$shots/launch-$trial-$target.png"
    printf 'nominal=%s actual=%s\n' "$target" "$(($(date +%s)-started))" >> "$shots/launch-$trial-time.txt"
    ps -ww -p "$owned_pid" -o pid=,etime=,%cpu=,command= > "$shots/launch-$trial-$target-process.txt"
  done
  if kill -0 "$owned_pid" 2>/dev/null; then
    ui menu > "$shots/launch-$trial-menu.log" 2>&1 || true
    screencapture -x "$shots/launch-$trial-menu.png"
    ui escape > "$shots/launch-$trial-escape.log" 2>&1 || true
    ui close > "$shots/launch-$trial-close.log" 2>&1 || true
    sleep 3
    screencapture -x "$shots/launch-$trial-closed.png"
    open "$app"
    sleep 5
    ui front > "$shots/launch-$trial-reopen.log" 2>&1 || true
    screencapture -x "$shots/launch-$trial-reopened.png"
  fi
  log show --last 3m --predicate "processID == $owned_pid" --style compact > "$shots/launch-$trial-unified.log" || true
  grep -F 'Using the Skia rendering backend (Metal)' "$shots/launch-$trial-stderr.log" >/dev/null || failed=1
  if grep -E 'Caused GPU Hang Error|kIOGPUCommandBufferCallbackErrorSubmissionsIgnored' "$shots/launch-$trial-unified.log" >/dev/null; then failed=1; fi
  stop_owned
done
codesign --verify --deep --strict "$app"
shasum -a 256 "$binary" > "$shots/binary-after.txt"
cmp "$shots/binary-before.txt" "$shots/binary-after.txt"
exit "$failed"
