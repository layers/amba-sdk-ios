#!/usr/bin/env bash
#
# build-xcframework.sh — bootstrap or rebuild
# Frameworks/AmbaCoreFFI.xcframework locally with full iOS + macOS
# slices.
#
# Customers cloning the monorepo get a `swift/Frameworks/` that's
# gitignored (binary artifacts don't belong in git). The release CI
# builds + uploads xcframeworks; for local SPM consumption (e.g.
# `swift test` or running examples/ios), run this script once to
# populate the slices your target needs.
#
# Targets built:
#   - aarch64-apple-ios          (iPhone/iPad device, arm64)
#   - aarch64-apple-ios-sim      (iOS Simulator on Apple Silicon, arm64)
#   - x86_64-apple-ios           (iOS Simulator on Intel Mac, x86_64)
#   - aarch64-apple-darwin       (macOS arm64)
#
# The two simulator slices are lipo'd into a fat library so a single
# xcframework slice covers both Apple-Silicon and Intel-Mac simulators.
#
# Usage:
#   cd swift && ./build-xcframework.sh
#
# Required: rustup with the listed targets installed, and Xcode
# command-line tools (for `xcodebuild -create-xcframework` + `lipo`).
#
set -euo pipefail

cd "$(dirname "$0")"
SWIFT_DIR="$(pwd)"
REPO_ROOT="$(cd .. && pwd)"
CORE_DIR="$REPO_ROOT/core"
TARGET_DIR="$REPO_ROOT/target"
GENERATED_DIR="$SWIFT_DIR/Sources/Amba/Generated"

if [ ! -d "$CORE_DIR" ]; then
    echo "error: expected $CORE_DIR — run from inside the amba-sdks monorepo" >&2
    exit 1
fi

# Ensure rustup targets are present. `rustup target add` is
# idempotent — re-running is cheap.
echo "==> ensuring rustup targets installed"
rustup target add \
    aarch64-apple-ios \
    aarch64-apple-ios-sim \
    aarch64-apple-darwin \
    x86_64-apple-ios

# Step 1 — host build. Produces the .dylib that uniffi-bindgen
# introspects for the Swift binding generation. We also need the
# debug build to produce the uniffi-bindgen binary itself (it lives
# in the same crate as a `[[bin]]`). Both are cheap incremental.
# `--features uniffi-surface` matches the Kotlin build and ensures
# the UniFFI facade module is always compiled into the host binary
# used for introspection.
echo "==> building core for host (uniffi-bindgen + introspection target)"
# `bindgen-tool` enables the uniffi `cli` feature (clap), which is required
# for the `uniffi-bindgen` binary target. Kept gated so iOS/Android cargo
# builds don't pull clap into the published staticlibs.
(cd "$CORE_DIR" && cargo build --release --features uniffi-surface,bindgen-tool)
(cd "$CORE_DIR" && cargo build --features uniffi-surface,bindgen-tool)

# Step 2 — generate Swift bindings. uniffi-bindgen emits
# AmbaCoreFFI.h + AmbaCoreFFI.modulemap (the FFI surface) plus
# AmbaCore.swift (the high-level wrapper). All three files are
# intentionally committed (see sdks/.gitignore lines 62-74) so they
# exist on a fresh CI checkout — always regenerate unconditionally to
# guarantee the committed copy matches the compiled xcframework. A
# stale committed binding silently drifts from the .dylib otherwise,
# and any "skip if present" optimization is permanently false (the
# files are always present, so it would never fire).
echo "==> generating Swift FFI bindings (AmbaCoreFFI.h + modulemap + AmbaCore.swift)"
(cd "$CORE_DIR" && cargo run --bin uniffi-bindgen --features uniffi-surface,bindgen-tool -- generate \
    --library "$TARGET_DIR/release/libamba_core.dylib" \
    --language swift \
    --out-dir "$GENERATED_DIR")

# Sanity check — uniffi-bindgen should have produced all three files.
for f in AmbaCoreFFI.h AmbaCoreFFI.modulemap AmbaCore.swift; do
    if [ ! -f "$GENERATED_DIR/$f" ]; then
        echo "error: expected $GENERATED_DIR/$f after binding generation, not found" >&2
        echo "       Check that core/uniffi.toml is configured correctly." >&2
        exit 1
    fi
done

# Step 3 — cross-compile the four slices.
echo "==> building core for iOS device (arm64)"
(cd "$CORE_DIR" && cargo build --release --target aarch64-apple-ios --features uniffi-surface)

echo "==> building core for iOS Simulator (arm64)"
(cd "$CORE_DIR" && cargo build --release --target aarch64-apple-ios-sim --features uniffi-surface)

echo "==> building core for iOS Simulator (x86_64)"
(cd "$CORE_DIR" && cargo build --release --target x86_64-apple-ios --features uniffi-surface)

echo "==> building core for macOS (arm64)"
(cd "$CORE_DIR" && cargo build --release --target aarch64-apple-darwin --features uniffi-surface)

# Step 4 — stage headers in a temp dir alongside the libraries.
# xcodebuild -create-xcframework copies whatever lives in -headers
# into each slice's Headers/. uniffi emits the modulemap as
# `AmbaCoreFFI.modulemap`, but xcodebuild expects `module.modulemap`
# inside the slice — so we rename on the way in.
HEADERS_TMP="$(mktemp -d)"
SIM_FAT_DIR="$(mktemp -d)"
trap 'rm -rf "$HEADERS_TMP" "$SIM_FAT_DIR"' EXIT

cp "$GENERATED_DIR/AmbaCoreFFI.h" "$HEADERS_TMP/AmbaCoreFFI.h"
cp "$GENERATED_DIR/AmbaCoreFFI.modulemap" "$HEADERS_TMP/module.modulemap"
echo "==> staged headers from $GENERATED_DIR"

# Step 5 — create fat simulator library (arm64 + x86_64). xcframework
# can only hold one slice per SDK, so Apple-Silicon and Intel
# simulator builds must be lipo'd together before the xcframework
# assembly. The device and macOS slices are single-arch and don't need
# this step.
echo "==> creating fat iOS Simulator slice (arm64 + x86_64)"
lipo -create \
    "$TARGET_DIR/aarch64-apple-ios-sim/release/libamba_core.a" \
    "$TARGET_DIR/x86_64-apple-ios/release/libamba_core.a" \
    -output "$SIM_FAT_DIR/libamba_core.a"

# Step 6 — assemble the xcframework.
rm -rf "$SWIFT_DIR/Frameworks/AmbaCoreFFI.xcframework"

xcodebuild -create-xcframework \
    -library "$TARGET_DIR/aarch64-apple-ios/release/libamba_core.a" \
    -headers "$HEADERS_TMP" \
    -library "$SIM_FAT_DIR/libamba_core.a" \
    -headers "$HEADERS_TMP" \
    -library "$TARGET_DIR/aarch64-apple-darwin/release/libamba_core.a" \
    -headers "$HEADERS_TMP" \
    -output "$SWIFT_DIR/Frameworks/AmbaCoreFFI.xcframework"

echo
echo "done. xcframework slices:"
ls "$SWIFT_DIR/Frameworks/AmbaCoreFFI.xcframework" | grep -v Info.plist
