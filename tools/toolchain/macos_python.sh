#!/usr/bin/env bash
# Official universal2 installer: setup-python may lag new CPython releases.
# This installs only on a disposable GitHub-hosted macOS runner.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$root/toolchain.env"
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_OS:-}" != macOS ||
      "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo 'Python bootstrap requires a disposable GitHub-hosted macOS runner' >&2
  exit 1
fi
[[ "$PYTHON_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$PYTHON_MACOS_INSTALLER_SHA256" =~ ^[0-9a-f]{64}$ ]]
package="${RUNNER_TEMP:?}/python-${PYTHON_VERSION}-macos11.pkg"
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
  "https://www.python.org/ftp/python/$PYTHON_VERSION/$(basename "$package")" \
  --output "$package"
printf '%s  %s\n' "$PYTHON_MACOS_INSTALLER_SHA256" "$package" | shasum -a 256 -c -
pkgutil --check-signature "$package"
sudo installer -pkg "$package" -target /
python_bin="/Library/Frameworks/Python.framework/Versions/${PYTHON_VERSION%.*}/bin"
export PATH="$python_bin:$PATH"
[[ "$(python3 --version)" == "Python $PYTHON_VERSION" ]]
"/Applications/Python ${PYTHON_VERSION%.*}/Install Certificates.command"
python3 -c 'import platform, ssl, sys; print(sys.version); print(platform.machine()); ssl.create_default_context()'
printf '%s\n' "$python_bin" >> "${GITHUB_PATH:?}"
