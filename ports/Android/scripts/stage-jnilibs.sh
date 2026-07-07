#!/usr/bin/env bash
# Stages every native library the APK needs for one ABI into
# AndroidApp/app/src/main/jniLibs/<abi>/:
#   - libLDrawVulkanAndroid.so   (this package, built by `make build`)
#   - the Swift runtime .so's it transitively DT_NEEDs (resolved iteratively against the Swift
#     Android SDK's swift-resources lib dir, so the list tracks toolchain changes instead of
#     being hardcoded)
#
# No SDL/vendored prebuilts needed here: LDrawVulkanOffscreenRenderer renders off-screen and has
# no windowing-system dependency, so this is just our own .so plus the Swift runtime.
#
# Usage: stage-jnilibs.sh <abi> <triple> <swift-arch>   e.g. arm64-v8a aarch64-unknown-linux-android28 aarch64
set -euo pipefail

ABI="$1"
TRIPLE="$2"
SWIFT_ARCH="$3"

cd "$(dirname "$0")/.."

SDK_BUNDLE=$(echo "$HOME"/Library/org.swift.swiftpm/swift-sdks/swift-*-RELEASE_android.artifactbundle/swift-android)
SWIFT_LIBS="$SDK_BUNDLE/swift-resources/usr/lib/swift-$SWIFT_ARCH/android"
NDK_PREBUILT=$(echo "$HOME"/Library/Android/sdk/ndk/*/toolchains/llvm/prebuilt/*/bin | tr ' ' '\n' | tail -1)
READELF="$NDK_PREBUILT/llvm-readelf"
# The Swift Android runtime is built against the NDK's libc++_shared.so, but that lives in the
# NDK sysroot (not swift-resources) since it isn't Swift's own library - stage it from there.
NDK_SYSROOT_LIB="$(dirname "$NDK_PREBUILT")/sysroot/usr/lib/$SWIFT_ARCH-linux-android"

APP_SO=".build/$TRIPLE/release/libLDrawVulkanAndroid.so"
[ -f "$APP_SO" ] || { echo "error: $APP_SO not built (run make build)"; exit 1; }

DEST="AndroidApp/app/src/main/jniLibs/$ABI"
rm -rf "$DEST"
mkdir -p "$DEST"

cp "$APP_SO" "$DEST/"

# Iteratively pull in Swift runtime dependencies until the NEEDED closure is satisfied.
while true; do
  added=0
  for lib in $("$READELF" -d "$DEST"/*.so | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' | sort -u); do
    if [ -f "$DEST/$lib" ]; then
      continue
    elif [ -f "$SWIFT_LIBS/$lib" ]; then
      cp "$SWIFT_LIBS/$lib" "$DEST/"
      added=1
    elif [ -f "$NDK_SYSROOT_LIB/$lib" ]; then
      cp "$NDK_SYSROOT_LIB/$lib" "$DEST/"
      added=1
    fi
  done
  [ "$added" = 0 ] && break
done

echo "✓ staged $(ls "$DEST" | wc -l | tr -d ' ') libraries in $DEST"
