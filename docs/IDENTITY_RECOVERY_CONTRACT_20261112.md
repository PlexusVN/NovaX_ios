# Identity recovery: existing server contract and deployment checks

This client repair uses the existing production server contract. No server
runtime, database function, credential, policy or customer row is changed by this
work. The application must use `production-server/AUTH/server`, not the older
`workspace-source/AUTH/server` reference tree.

Backend paths and Node commands below refer to the separately deployed AUTH
server. That server is not included in this iOS repository.

## Contract used by the client

- An active installation with both original private keys can use a fresh challenge
  and canonical enrollment to recover the server's device/installation metadata.
  The Node compatibility path accepts only matching license, HWID, both complete
  public keys/fingerprints, protocol/revision 2, and an unrevoked row. It never
  rotates keys or consumes an administrator's recovery ticket.
- `POST /api/v2/device/challenge` with `recover_installation: true` returns
  `recovery_authorized` for an unused, unexpired administrator ticket scoped to
  the verified license and HWID. This response is a hint for the client; the
  enrollment RPC must recheck and atomically consume the ticket when replacing
  an installation. License/HWID possession alone does not authorize replacement.
- `POST /api/v2/device/enroll` with `canonical_enrollment: true` returns
  `device_key_id`, `install_id`, `key_id`, `license_binding`,
  `enrollment_revision`, `public_key_fingerprint`, and
  `agreement_public_key_fingerprint` from the active persisted row, after RPC
  authorization. `X-Astra-Response-Mode: tls-pinned-v1` changes the JSON response
  format only; request signatures, challenge/nonce/counter and authorization
  remain required. The client validates the metadata against its requested
  license/HWID and both local keys before persisting it.
- The client persists a replacement candidate before enrollment and retries that
  exact candidate if the response is lost. The installed RPC must return the
  same active identity for exact-key retries after a successful replacement,
  even though its recovery ticket has already been consumed. It must not grant a
  second replacement, revive a revoked row or create another slot on retry.
- The production Reset HWID / Remove Device routes call
  `installation_recovery.js` -> `novax_reset_license_devices`. The Node helper
  acknowledges only an RPC result with `success: true` and no Supabase error.
  `novax_control.js` enables protected downloads before the HTTP listener starts.
  A legacy route that just deletes `key_devices` and clears `keys.hwid` does not
  meet this contract.

Reset and metadata repair are different operations. A targeted administrator
reset is expected to revoke the old installation/session and outstanding grants,
release its HWID binding, create the scoped recovery authorization and audit the
operation atomically. Existing ban/quarantine evidence and other devices must be
retained. Bulk reset is a separate operation and processes multiple licenses;
the Node loop is not one all-or-nothing transaction for the entire product.

## Captured SQL is incomplete

The packaged `production-server/AUTH/sql/schema.sql` is the original legacy
schema, not the final protocol-2/recovery database. It does not define
`novax_reset_license_devices`, `novax_enroll_device_v2` or the recovery tables.
`server/tools/build_schema.js` references historical migration inputs which are
missing from this capture, including `installation_recovery.sql`.

The development migration `workspace-source/AUTH/sql/release_hardening.sql`
defines an older enrollment policy. It is not a replacement for the missing final
recovery migration. The local server ZIP patches and available local Git
snapshots do not contain that final migration either. Do not regenerate or apply
a guessed database schema to make the tests pass.

Consequently, the Node boundary tests can verify request validation, same-key
resume, canonical metadata and reset error handling locally. They cannot prove
the live reset/replacement transaction. Deployment remains unverified until the
actual installed functions, constraints and runtime files are checked. An old
server without canonical metadata or a missing recovery RPC must fail visibly;
the client must retain its identity/candidate and must not bypass authorization.

## Read-only database preflight

Run these **SELECT-only** statements in the existing database owner's SQL
console. Do not paste outputs containing customer rows or credentials into logs.
These queries retrieve schema and function definitions, not customer data.

```sql
SELECT n.nspname AS schema_name, p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_execute,
       pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('novax_reset_license_devices', 'novax_enroll_device_v2',
                   'novax_consume_request_proof', 'novax_consume_download_grant_guarded')
ORDER BY p.proname, arguments;

SELECT c.relname AS table_name, a.attname AS column_name,
       format_type(a.atttypid, a.atttypmod) AS column_type, a.attnotnull
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND a.attnum > 0 AND NOT a.attisdropped
  AND c.relname IN ('novax_device_keys', 'novax_app_sessions_v2',
                   'novax_enrollment_challenges', 'novax_installation_recoveries',
                   'novax_download_grants', 'novax_device_enforcement',
                   'novax_policy_violations', 'novax_temporary_hwid_quarantine')
ORDER BY c.relname, a.attnum;

SELECT con.conrelid::regclass AS table_name, con.conname,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
WHERE con.conrelid IN (
  to_regclass('public.novax_device_keys'),
  to_regclass('public.novax_app_sessions_v2'),
  to_regclass('public.novax_installation_recoveries'),
  to_regclass('public.novax_download_grants'),
  to_regclass('public.novax_device_enforcement'),
  to_regclass('public.novax_policy_violations'))
ORDER BY table_name, con.conname;

SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('novax_device_keys', 'novax_installation_recoveries')
ORDER BY tablename, indexname;
```

Review the actual functions for scoped, expiring, one-use authorization; exact-key
idempotency; license/device slot checks; ban/quarantine enforcement; consistent
lock order; and reset/replacement/audit atomicity. Verify backend-only execution
permissions for every overload. Keep the original definitions before proposing
any narrow migration. Missing functions/tables or an older function that cannot
consume an administrator ticket are deployment blockers for replacement recovery.
They are not reasons to enable legacy downloads or delete security records.

Also compare the running AuthServer entry point and the two
`security_v2.js`/`installation_resume.js` modules with the selected production
source. Historical CI/release reports do not confirm the VPS is running them.
The existing production schema's fingerprints can remain unique across revoked
rows. `device_already_enrolled` also represents unique-constraint errors in older
enrollment SQL, so the code alone does not identify which constraint failed.

## Local verification and live acceptance

From the production server directory, with its existing test dependencies:

```sh
node --test test_installation_resume.js test_installation_recovery_contract.js test_session_logout.js test_security_v2.js test_identity_resume_sql.js
```

`test_installation_recovery_contract.js` tests the Node/RPC boundary without
inventing replacement SQL. `test_installation_recovery_sql.js` and
`test_unified_schema.js` require the missing final schema; they cannot establish
live recovery correctness using the legacy captured schema.

After the installed contract has been verified, validate targeted reset,
replacement enrollment and exact-key retry after a lost response against an
isolated database with the actual migration set. Cover simultaneous requests,
expired/used tickets, wrong license/HWID, revoked identity, slot limits,
ban/quarantine, and an injected audit failure which rolls back the transaction.
Then validate the updated IPA on a real device using the same signing context for
normal updates, and a controlled authorized recovery case for genuine key loss.
This task does not perform VPS deployment, database writes or physical-device
validation.
