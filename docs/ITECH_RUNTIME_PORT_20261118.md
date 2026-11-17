# Astra 2.5 (39): iTech runtime port

This candidate ports the runtime behavior from the local iTech build-19 source
tree while retaining Astra's public API origin, server signer, product secret,
Keychain namespace, catalog identity and branding.

Ported runtime layers:

- iOS/build provider policy, including the scoped Viet99/BQCore candidate for
  iOS 27.2.1–27.3.x;
- worse_query preparation and Bundle-ID/container discovery;
- DirectPatchExecutor, PatchFilesystemGate, transaction schema 3 and restore
  read-back;
- CatalogFeatureModeRegistry and iTech's per-item recovery semantics;
- device identity/session recovery and protected artifact download flow;
- `Viet99BQCore.m/.h` with production bridge wiring and native self-check.

The BQCore adapter uses class 13 → class 7 → class 12 for its candidate range.
It validates an exact application UUID root and a real directory read, runs off
the main thread, retains XPC/query ownership through cleanup and never publishes
ready from policy alone. Unsupported builds remain blocked.

Astra-specific API and instance configuration stay in:

- `helpers/AppSecurityConfiguration.swift`;
- `helpers/ServerSignatureVerifier.swift`;
- `helpers/SecureAPIClient.swift`;
- Astra's `AuthManager`, domain, signer and product secret.

No Astra server, database, registry, key, bucket or VPS process was changed.

Validation before macOS build: 76 Python/source tests passed, 14 macOS-only
checks were skipped on Windows. The macOS workflow must compile Swift/Objective-C,
run BQCore/MCM/transaction/recovery self-checks and produce the IPA before this
candidate is installable. The candidate build is 2.5 (39).
