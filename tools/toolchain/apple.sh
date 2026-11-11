#!/usr/bin/env bash
# Explicit final Apple toolchain, shared by all Apple build/verification jobs.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$root/toolchain.env"
xcode_path="/Applications/Xcode_${XCODE_VERSION}.app/Contents/Developer"
if [[ ! -d "$xcode_path" ]]; then
  echo "Pinned stable Xcode $XCODE_VERSION is unavailable on this runner" >&2
  exit 1
fi
sudo xcode-select --switch "$xcode_path"
xcode_version="$(xcodebuild -version)"
if [[ "$(head -n 1 <<<"$xcode_version")" != "Xcode $XCODE_VERSION" ]]; then
  echo "Selected Xcode does not match toolchain.env" >&2
  exit 1
fi
if [[ "$(pod --version)" != "$COCOAPODS_VERSION" ]]; then
  echo "CocoaPods does not match toolchain.env" >&2
  exit 1
fi
if [[ "$(python3 --version)" != "Python $PYTHON_VERSION" ]]; then
  echo "Python does not match toolchain.env" >&2
  exit 1
fi
echo "$xcode_version"
swift --version
echo "CocoaPods $(pod --version)"
python3 --version
