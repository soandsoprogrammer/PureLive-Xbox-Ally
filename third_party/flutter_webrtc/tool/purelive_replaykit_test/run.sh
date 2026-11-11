#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo 'ReplayKit lifecycle harness requires macOS'; exit 77; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_dir="$here/../../common/darwin/Classes"
build=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/purelive-replaykit.XXXXXX")
clang -fobjc-arc -fblocks -include "$here/Platform.h" \
  -I "$here/stubs" -I "$source_dir" \
  "$source_dir/FlutterRPScreenRecorder.m" "$here/lifecycle.m" \
  -framework Foundation -framework CoreMedia -framework CoreVideo \
  -o "$build/replaykit-lifecycle"
"$build/replaykit-lifecycle"
