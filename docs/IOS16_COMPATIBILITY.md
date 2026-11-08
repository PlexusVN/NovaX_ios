# Astra 2.0 (19): iOS 16 native compatibility / iOS 27 preservation

## What changed

Build 18 linked an iOS-16 app against the old iOS-18 AirliftFFI archives. The
actual GitHub build emitted deployment mismatch warnings. This is a confirmed
build inconsistency, not proof of the sole cause of every reported crash.

Build 19 rebuilds the same native source, patch, compiler and Cargo.lock before
building the app. The minimum is 16.0 for Rust, device C dependencies and
simulator C dependencies. It does NOT rewrite the minimum version in old binaries.

The pinned inputs are recorded in patches/airlift-source.lock.json. The source
revision is 40640c4d827aeab8d798285b57d24fcf6be070d0; Rust 1.98.1 is the compiler
identified in the existing archive. Cargo uses --locked. The existing RemoteXPC
fallback, canary and 180-second AirTraffic deadline patch is preserved by exact
source/header/patch hashes and ABI/marker checks. No latest-upstream engine update.

The app's manually declared IOSurfacePrefetchPages API is now weak-imported and
checked before native work begins. If an older system lacks it, the operation
returns an error instead of requiring that symbol at app load. This does not
invent a replacement exploit or claim that missing APIs support patching.

AirLift keeps its serial native queue occupied until actual native completion.
A Swift timeout cannot unlock a live operation or a newer operation via a stale
timer. The Swift waits are 135s for a native 120s query and 195s for a native 180s
canary/write, avoiding an early 15/20/60s timeout while native work continues.
The target-path/canary/write implementation and OS pairing routes are unchanged.

## Build

GitHub Actions performs the native rebuild automatically, using Xcode 16.4.
For a local macOS/Xcode build, run this ONCE before xcodebuild:

    bash ReleaseTools/build_airlift_compat.sh

The old committed archives remain the capture baseline until a macOS rebuild;
they are not silently reused when the rebuild fails. Both platforms must pass
before the rebuilt archives are installed. Xcode also has a pre-build native
compatibility check, so a direct local build with old iOS-18 archives fails with
instructions instead of producing a misleading iOS-16 IPA.

Every native object must target the correct platform and iOS <=16.0. Existing
required FFI exports and safety/fallback markers must remain. The final app's
Info.plist AND executable must support iOS <=16.0, and the optional private API
must not be strongly imported. CI fails before packaging if any check fails.

## ESign/KSign and limits

The distributed IPA remains unsigned for ESign/KSign. No App Store receipt,
fixed signing Team ID, IPA release seal, new private signing key or jailbreak
lockout is added. Proxy/TLS guards and server authorization stay unchanged.
No AUTH/server/database modification is part of this fix.

The repository tests compile the actual OS routing policy: iOS 16 remains direct
with no AirLift pairing; supported iOS 27 builds remain AirLift + pairing. Routing
tests are not proof of exploit/write support on a physical OS/build.

Windows tests validate the checker, source wiring and patch application. Real
native compilation requires macOS. A passing CI build is not a physical iOS-16
or iOS-27 test and does not validate a third-party re-signed provisioning profile.
Before broad release test startup/login/download/direct apply on iOS 16, and
startup/pairing/VPN/canary/apply on supported iOS 27. If a crash persists, the
device .ips or the final ESign/KSign-signed IPA is needed to distinguish dyld,
code-signing, memory-pressure and native-operation failures.
