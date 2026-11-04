# Astra Release hardening

## Release-only compiler/linker policy

The `3105` Release configuration now enables:

- `DEPLOYMENT_POSTPROCESSING = YES`
- `STRIP_INSTALLED_PRODUCT = YES`
- `STRIP_STYLE = all`
- `COPY_PHASE_STRIP = YES`
- `STRIP_SWIFT_SYMBOLS = YES`
- `STRIP_LOCAL_SWIFT_SYMBOLS = YES`
- `DEAD_CODE_STRIPPING = YES`
- `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`
- `SWIFT_OPTIMIZATION_LEVEL = -O`
- `SWIFT_COMPILATION_MODE = wholemodule`
- `SWIFT_REFLECTION_METADATA_LEVEL = without-names`
- hidden C/C++ symbols and no exported global symbol list
- `ENABLE_TESTABILITY = NO`

The dSYM is generated outside the app for crash symbolication and is not copied
into the IPA. Debug builds retain normal reflection/debug behavior.

This is compiler-level internalization and metadata reduction, not a promise
that native ARM64 cannot be disassembled. Full control-flow virtualization or a
custom Obfuscator-LLVM toolchain is intentionally not forced into this release:
it can break SwiftUI, AirLift FFI, Objective-C selectors and reflected fields.

## Binary integrity compatible with ESign/KSign

`IntegrityAnchor.c` contains a fixed 64-byte placeholder outside `__text`. The
Release hardening phase:

1. parses the thin arm64 Mach-O;
2. hashes only `__TEXT,__text`;
3. patches the placeholder with the digest;
4. strips local/debug symbols;
5. verifies the digest again before Xcode code-signing.

At runtime `BinaryIntegrity.swift` repeats that measurement. ESign/KSign may
replace `LC_CODE_SIGNATURE`/`__LINKEDIT`, but that does not change `__text`, so a
normal re-sign remains valid. Patching executable instructions changes the hash
and enters the signed two-hour device quarantine flow.

The build fails if the integrity anchor is absent/duplicated, if the executable
is not the expected arm64 Mach-O, or if the post-strip digest is different.

## Runtime defenses

- `P_TRACED` and `CS_DEBUGGED` detection before UI startup.
- `PT_DENY_ATTACH` after the clean launch assessment in non-Debug device builds.
- injected Frida/Cycript/Substrate/libhooker/ElleKit image scanning.
- Frida localhost port scan and three-second runtime recheck.
- rootful/rootless jailbreak and sandbox-escape checks.
- pinned TLS leaf verification remains mandatory in `SecurityUtils.swift`.
- production host/origin strings are decoded at runtime instead of remaining in
  the executable's plaintext string table.
- server configuration fetches use a pinned ephemeral session; authenticated
  traffic remains restricted to `SecureAPIClient`'s exact route allowlist.

Every automatic quarantine request is signed by the enrolled installation key;
the server ignores client-supplied target HWID/key/device fields.

## Required release verification

1. Run `python3 -m unittest -v Tests/test_embed_integrity_hash.py`.
2. Build Release through Xcode/GitHub Actions. Never package a raw executable
   that bypassed `Release Binary Hardening`.
3. Confirm `tools/embed_integrity_hash.py --verify <Astra executable>` succeeds.
4. Confirm security type names are absent from `nm -gj` output.
5. Re-sign the unsigned IPA with both ESign and KSign and verify clean launch.
6. Modify one byte inside `__TEXT,__text` in a lab copy: the app must block,
   report through protocol 2 when possible, and terminate.
7. Test LLDB-before-launch, Frida-after-launch, clean iOS 16 and clean iOS 27.2.
8. Rotate the pinned leaf hash before the currently pinned certificate expires;
   never ship an unverified fallback pin just to avoid a rotation outage.

All client-side checks can ultimately be patched by an attacker who can modify
the executable. Server signatures, device-bound requests, encrypted artifacts,
short grants and authorization remain the security boundary.
