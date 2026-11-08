#!/bin/bash
# Same pinned engine/compiler/lockfile as the committed iOS 18 archive, rebuilt
# for iOS 16. No Mach-O metadata editing and no fallback to the old archive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/patches/airlift-source.lock.json"
[[ "$(uname -s)" == Darwin ]] || { echo 'Airlift native rebuild requires macOS/Xcode.' >&2; exit 1; }
command -v python3 >/dev/null
command -v xcrun >/dev/null
command -v rustup >/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
command -v rustup >/dev/null
read_lock() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$LOCK" "$1"; }
REVISION="$(read_lock revision)"
RUST_VERSION="$(read_lock rust_toolchain)"
MIN_IOS="$(read_lock deployment_target)"
export IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS"
export CARGO_TARGET_DIR="$ROOT/build/airlift-ios16-target"
WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/astra-airlift-ios16.XXXXXX")"
SOURCE="$WORK/source"
echo "[native] Exact source $REVISION, Rust $RUST_VERSION, deployment iOS $MIN_IOS"
git init -q "$SOURCE"
git -C "$SOURCE" remote add origin "$(read_lock repository)"
git -C "$SOURCE" fetch --depth=1 origin "$REVISION"
git -C "$SOURCE" checkout --detach FETCH_HEAD
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$REVISION"
python3 - "$ROOT" "$SOURCE" <<'PY'
from pathlib import Path
import hashlib, json, sys
root, source = map(Path, sys.argv[1:])
lock = json.loads((root / 'patches/airlift-source.lock.json').read_text())
for path, expected in [(root / lock['patch'], lock['patch_sha256']),
                       (source / 'rust-core/Cargo.lock', lock['cargo_lock_sha256']),
                       (source / 'rust-core/include/airlift.h', lock['header_sha256'])]:
    actual = hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest()
    if actual != expected: raise SystemExit('Native source/patch checksum mismatch: ' + path.name)
PY
git -C "$SOURCE" apply --check "$ROOT/$(read_lock patch)"
git -C "$SOURCE" apply "$ROOT/$(read_lock patch)"
python3 - "$LOCK" "$SOURCE" <<'PY'
from pathlib import Path
import hashlib, json, sys
lock = json.loads(Path(sys.argv[1]).read_text())
data = (Path(sys.argv[2]) / 'rust-core/src/exploit.rs').read_bytes().replace(b'\r\n', b'\n')
if hashlib.sha256(data).hexdigest() != lock['patched_exploit_sha256']:
    raise SystemExit('Patched AirLift source is not the previously reviewed engine')
PY
echo '[native] Installing the same compiler and both iOS targets'
rustup toolchain install "$RUST_VERSION" --profile minimal --target aarch64-apple-ios --target aarch64-apple-ios-sim
export RUSTFLAGS="--remap-path-prefix=$SOURCE=/build/airlift"
export CFLAGS_aarch64_apple_ios="-miphoneos-version-min=$MIN_IOS -ffile-prefix-map=$SOURCE=/build/airlift"
export CFLAGS_aarch64_apple_ios_sim="-mios-simulator-version-min=$MIN_IOS -ffile-prefix-map=$SOURCE=/build/airlift"
echo '[native] Rebuilding device archive (including C/crypto dependencies)'
SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
  cargo +"$RUST_VERSION" build --manifest-path "$SOURCE/rust-core/Cargo.toml" --locked --release --target aarch64-apple-ios
echo '[native] Rebuilding simulator archive'
SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  cargo +"$RUST_VERSION" build --manifest-path "$SOURCE/rust-core/Cargo.toml" --locked --release --target aarch64-apple-ios-sim
DEVICE="$CARGO_TARGET_DIR/aarch64-apple-ios/release/libairlift_ffi.a"
SIM="$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libairlift_ffi.a"
python3 "$ROOT/ReleaseTools/verify_native_compatibility.py" --archive "$DEVICE" --max-ios "$MIN_IOS"
python3 "$ROOT/ReleaseTools/verify_native_compatibility.py" --archive "$SIM" --platform simulator --max-ios "$MIN_IOS"
for PLATFORM in ios-arm64 ios-arm64-simulator; do
  cmp "$SOURCE/rust-core/include/airlift.h" "$ROOT/Frameworks/AirliftFFI.xcframework/$PLATFORM/Headers/airlift.h"
done
# Install only after BOTH platforms pass, keeping the existing module/ABI header.
cp "$DEVICE" "$ROOT/Frameworks/AirliftFFI.xcframework/ios-arm64/libairlift_ffi.a"
cp "$SIM" "$ROOT/Frameworks/AirliftFFI.xcframework/ios-arm64-simulator/libairlift_ffi.a"
echo '[native] iOS 16-compatible archives installed; iOS 27 engine source unchanged.'
