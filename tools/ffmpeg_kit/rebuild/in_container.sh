#!/usr/bin/env bash
# Runs as root inside the builders' image (build.sh starts it), in the
# patched builders checkout mounted at /workspace:
#
#   in_container.sh android|linux|windows ...
#
# Same commands as ffmpeg-kit-builders' own release builds of the base LGPL
# bundle (scripts/build_all.sh, scripts/android/build_aar.sh), with every
# dependency built here (--build-deps) instead of downloaded from their
# releases. FFmpeg's tag comes from builders.patch (scripts/variable.sh).
set -euo pipefail
cd /workspace

for target in "$@"; do
  echo "=== $target $(date -u +%T)"
  case "$target" in
    android)
      export ANDROID_HOME=/usr/local/android-sdk ANDROID_API_LEVEL=26
      export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/$NDK_VERSION"
      export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
      for arch in aarch64 armv7a x86_64; do
        ./runner.sh --host=android --arch="$arch" -y --build-deps --base-bundle \
          --ffmpeg -ff --ff-disable-programs --kit -fk --no-bundle --release=local --skip --hide-banner
      done
      # build_aar.sh reads the publishing account even for a local build and
      # puts its "not found" message into the Gradle command line; the AAR's
      # namespace is the owner's, as in their release.
      # Gradle resolves its plugins from the network; a failed try resumes
      # at the failed step (the script keeps its own state).
      reset=--reset
      for try in 1 2 3; do
        GITHUB_USERNAME=akashskypatel GITHUB_REPO=ffmpeg-kit-builders \
          OSSRH_USERNAME=unused OSSRH_PASSWORD=unused OSSRH_BASE64=unused \
          bash scripts/android/build_aar.sh --platform=android-aarch64,android-armv7a,android-x86_64 \
          --bundle=base --license=lgpl --not-small $reset --local && break
        [[ $try -lt 3 ]] || exit 1
        reset=
        sleep 30
      done
      ;;
    linux | windows)
      bash scripts/build_all.sh --platform="$target-x86_64" --build=ffmpeg,kit,bundle \
        --bundle=base --license=lgpl --not-small --local --reset --deps
      ;;
    *)
      echo "unknown target: $target" >&2
      exit 2
      ;;
  esac
  echo "=== $target done $(date -u +%T)"
done
