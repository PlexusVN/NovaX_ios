# Astra 2.4 (38): container lookup and identity recovery

This change follows the supplied 3105 2.2 build-15 executable, UUID
`C0B32250-F3EE-379B-B212-4A0531E2AC67`, SHA-256
`7737f4d125de9a844d52445bd5ac28dd894d686cca407ccaaf3a98558ff89ca1`.
The local 3105-main snapshot is older and does not represent that executable.

## Container preparation

The worse_query worker now tries an exact Bundle-ID path lookup before the
anonymous inode scan. It follows the reference's separation between obtaining
a path and activating access: raw MCM class-2 path query, temporary lease path
fallback without activate:, then a fresh worse_query grant and directory read.
LaunchServices supplies another Bundle-ID path candidate if MCM did not work.

Missing xattr/metadata no longer invalidates an exact Bundle-ID system lookup
after the granted directory read succeeds. Available conflicting identifiers
still reject the candidate. Anonymous inode results and remembered UUIDs still
require independently readable identity. Two Bundle IDs cannot claim one root;
two roots claiming one target remain ambiguous. Tokens are released on all
normal/error/cancellation paths. No discovery test writes into a game container.

The Objective-C bridge shields lookup exceptions, retains XPC identifiers
through query cleanup and does not perform native lookup on the main thread.
It never activates the legacy MCM extension in this worse_query path.
Existing provider ranges and the kernel guard for iOS 17/18 are unchanged.

## Identity and download errors

Stored Secure Enclave key corruption is classified at the key load/use boundary.
Only CryptoTokenKit corruptedData (-3), directly or through bounded known
Security data-error wrappers, becomes invalidIdentity. Locked/authentication,
missing-entitlement, cancellation and communication errors retain their original
meaning. Corrupt archives are preserved; replacement still requires the server's
fresh recovery authorization. An unrelated damaged global legacy archive cannot
prevent a license's own scope from using its normal enrollment/recovery flow.

Clock-not-yet-valid and expired artifact grants have distinct messages. All
signature, recipient/session/nonce, ciphertext and absolute expiry checks remain.

## Filesystem state

New direct transactions use journal schema 3. Their first atomic prepared journal
contains immutable engine/operation/target provenance. The project sidecar can
be reconstructed after an interrupted sidecar write only after its binding and
the predecessor's terminal state are validated. Legacy schema 1/2 ambiguity and
conflicting AirLift history remain blocked. Record size limits are shared by
writers/readers and checked before backup/target I/O.

Restore verifies the final target digest or actual ENOENT before committing its
restored state. Backups and rollback remain available on verification failure.
The fixed-name startup write/delete probe in the game Documents folder is removed.

## Verification and distribution

The existing macOS workflow now also executes the full production transaction
regression with real CryptoKit and temporary files. Native MCM tests compile the
production bridge and replace only dynamic OS boundary functions. Discovery
regressions execute the production preparation body with the observed WQ02
boundary: directory readable, xattr/metadata unavailable, Bundle-ID lookup works.
Tests cover denied reads/grants, conflicting identity, cache revalidation and
cancellation before grant dispatch. Identity fixtures exercise cold legacy/scoped
flows and preserve denied recovery/transient errors.

Windows cannot execute Apple Keychain, Secure Enclave, containermanagerd or Xcode.
GitHub Actions supplies the macOS build environment; a successful CI build still
does not certify the final re-signed IPA's permissions on a physical iPhone.

Install the exact build-38 artifact while preserving the signing configuration
and accessible App Group. On 26.6.1 check startup/login/catalog and apply/restore.
On build 24B119 check preparation logs for mcm_bundle_id or
launch_services_bundle_id, then catalog, apply, close/reopen and restore.
If device recovery is requested, use the existing authorized server flow; do
not erase Keychain or reset production data to hide a failure.
