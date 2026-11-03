# P2-16: generic connection seam for hosted Library providers

DATE: 2026-09-30, rescoped 2026-11-02
STATUS: Merged to main 2026-11-02 ([PR #329](https://github.com/ph-composer/ph-composer-skp/pull/329), `5df489e5`). Un-deferred by D5-1. Host gate observed 2026-11-03 ([case LH1](#host-gate-case-lh1), [evidence](../../../native-acceptance/evidence/lh1-hosted-library-2026-11-03.md)): fails only on the pairing display, which Composer did not show; the firm change was blocked by the test account. #334 added the pairing display, observed passing the same day; a full LH1 rerun on that build is owed before the gate closes.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/328 (replaces the closed #14)

## Decision record

**D5-1 (2026-11-02): P2-16 un-deferred as the generic connection seam.** D2-8 deferred P2-16
until PH-Navigator's endpoint used the neutral format. PH-Elements now needs a hosted Library
connection, and its contract is ready (PH-Elements Phase 06 G1). P2-16 resumes, changed: core gains
a generic, versioned connection seam (`contract_version: 2`) and a shared OS credential store; core
encodes no sign-in mode, URL, identity provider or vendor name. Transport and sign-in belong to
each extension. Late-response guards stay. v1 providers are unchanged. Not superseded: P2-16 keeps
its number and history. The PH-Elements connector is the first extension to use the seam.

Sources (PH-Elements at `8324cfc`): the owning plan `planning/phases/06-composer-library/06-composer-core-v2.md`,
the accepted seam design in `contracts/phase00/COMPOSER_V2.md` ("Phase 06 G1 reconciliation"), the
proposal `research/phase06/composer-p2-16-proposal-20261102.md` and the credential-store experiment
`research/phase06/credential-store-20261102.md`.

## What changed from the 2026-09-30 scope

| p2-16 before | Now |
| --- | --- |
| Transport over `Sketchup::Http::Request` in core | Core does no HTTP. Each extension owns its transport |
| Sign-in modes none, static token, device code | Core has no sign-in mode. `connect`, `disconnect` and `reauthorize` are generic lifecycle actions the extension implements |
| macOS Keychain "through one short-lived process with the secret as an argument" | Core credential store keyed by provider ID and connection ID. macOS: Fiddle on `Security.framework`. A secret in `argv` is not allowed |
| Windows credentials out of scope | Windows Credential Manager through Fiddle (`CredWriteW`, `CredReadW`, `CredDeleteW`, `CredFree`), written and not yet observed on a host |
| Token and address through native dialogs, never the panel | Kept: no credential, credential-bearing URL or provider body reaches the HtmlDialog |
| Late-response guards by configuration revision and catalog generation | Kept and extended: connection generation, operation ID and destination model; cancel drops late completions |
| Offline keeps the loaded generation; revocation or removal discards it | Kept: the last complete Batch stays immutable and marked by availability; disconnect clears transient rows, never local copies |
| Refuse a body echoing the token; refuse non-loopback plain HTTP | Moves to the extension; core refuses any provider diagnostic that is not a `library.*` code |
| Connection provider through `library_provider` v1 | `library_provider(..., contract_version: 2, lifecycle: [...], connection:)` beside v1; v1 untouched |
| (absent) | Asynchronous load (`begin_load`, `poll_load`, `cancel_load`) on the export task's timer pattern; explicit states; Batch-v2 transport with snapshot identity and source revisions; `authorize_use` before every import or update; `source_revision` and `source_revision_schema_version` in the closed `source` schema; non-file setup and Remove in the Libraries setup UI; external registrations that survive `Registry.reset` |

## Scope

| Item | Design |
| --- | --- |
| Declaration | `feature.library_provider(name, contract_version: 2, kinds:, lifecycle:, connection:, refuses:, &provider_factory)`. `contract_version` accepts 1 or 2. The connection factory runs once per SketchUp process. The provider factory is still re-invoked per lookup and starts no sign-in, network or storage work |
| Registration and reset | `compose` calls `Registry.reset` and reinstalls Composer's own features, then every feature another extension installed through `Registry.install`, in order |
| Refusals | Every v2 callback declares `refuses:`. A provider error keeps its code only when it matches `library.[a-z0-9_.]+` and the callback declares it. Diagnostics carry the code, never a response body |
| Loading | v1 stays synchronous. v2 loads through `begin_load`, `poll_load` and `cancel_load` on a main-thread timer; no Ruby thread touches the model. The last complete Batch stays immutable and is marked with its availability. A failed or cancelled load never replaces it |
| States | `disconnected`, `authorizing`, `connected`, `loading`, `ready`, `stale`, `reauthorization_required`, `unavailable`, `cancelled`. An empty `ready` is distinct from `unavailable`. A completion whose connection generation, operation ID or destination model no longer matches is dropped |
| Batch-v2 transport | v1 `Batch` rows unchanged, plus `snapshot: {id, library_revision, projection_schema_version}` and `source_revisions: {"<wire kind>/<library id>/<record id>" => positive Integer}`. A missing, duplicate, zero, negative or foreign key refuses the whole snapshot with `library.source_revision_invalid` |
| Use authorization | The coordinator calls `authorize_use(operation_id:, snapshot_id:, selection:)` for v2 sources before staging any write. The authorization is valid for 5,000 ms from the start of the request on core's monotonic clock. Core rechecks the destination model, selection and connection generation on the main thread. Any mismatch, cancel or expiry refuses with no mutation. UI and scripted callers share one path; v1 sources skip the step |
| Provenance | The closed `source` schema gets two optional keys: `source_revision` (positive integer) and `source_revision_schema_version` (enum `[1]`), filled in the same Undo step as copy plus assignment. Local edit and keep-local keep them; use-library adopts a newer revision only through the guarded update. Legacy copies read as unknown and a matching fingerprint never backfills one |
| Credential store | `Library::Connection::CredentialStore`: `write(provider_id, connection_id, value)`, `read`, `delete`. macOS: one generic-password item per connection (service `ph-composer.<provider id>`, account the connection ID), replaced with one modify call. Windows: `CredWriteW`, `CredReadW`, `CredDeleteW`, `CredFree`, `CRED_TYPE_GENERIC`, `CRED_PERSIST_LOCAL_MACHINE`, target `ph-composer/<provider id>/<connection id>`. A failed write is reported to the provider |
| Setup UI | The Libraries setup dialog and setup commands show v2 connections with their state and label, and offer Connect, Reconnect, Disconnect and Remove. Remove is no longer gated on the file provider. Disconnect clears transient loaded data and never touches local copies |

## Out of scope

Each extension owns HTTPS, its sign-in flow, the callback listener, token refresh, and the mapping
from service errors to connection states. Real-host observation of the seam with a hosted
extension, and of the credential store on SketchUp 2023 to 2025, with a locked keychain, after a
SketchUp upgrade, and on Windows, is a later native gate.

## Done when

- `make ci` is green, every pre-existing library test is unchanged and passing, and the Ruby 2.7
  and Chromium 88 floors hold.
- Tests cover v2 declaration validation and refusals; external registrations surviving
  `Registry.reset`; manager states, cancel and late-completion drops; Batch-v2 admission refusals;
  `authorize_use` before mutation (expiry, changed selection, changed model, changed generation);
  `source_revision` through import, local edit, keep-local and use-library to a newer revision, with
  Undo and Redo and save and reopen, and two revisions with identical content kept distinguishable;
  non-file setup and Remove; the credential store against a fake.
- A fake v2 provider in the tests (no network) proves the seam. The example provider does not change.
- `context/EXTENSIBILITY.md`, `context/CONTRACTS.md` and `planning/STATUS.md` updated in the same PR.

## Evidence (2026-11-02, offline)

- `make ci` green: Ruby suite 2,273 runs, 0 failures; JavaScript 759 pass; pytest 258 pass; RuboCop, eslint,
  manifests and RBZ checks pass. New suites on Ruby 3.2.2 and 2.7.2: `library_connection_test` (13),
  `library_hosted_load_test` (15), `library_hosted_copy_test` (10), `library_credential_store_test` (4), plus
  connection rows in `library_setup_test.js` and hosted states in `library_sidebar_test.js`.
- One pre-existing test changed: `library_registration_test.rb` used `contract_version: 2` as its unsupported
  provider example; it now uses 3, because 2 is supported.
- The macOS Keychain backend stored, replaced, read and deleted a synthetic value from command-line Ruby 3.2.2
  and 2.7.2 on this Mac, leaving no item. Not a host gate: SketchUp 2023 to 2025, a locked keychain, the prompt
  after a SketchUp upgrade and all of Windows remain unobserved.

## Host gate (case LH1)

[`LH1`](../../../native-acceptance/cases.json) observes the merged seam on the installed RBZ with the
first hosted extension, the PH-Elements connector
([ph-composer/ph-composer-elements](https://github.com/ph-composer/ph-composer-elements)), against a
synthetic firm Library on the PH-Elements service. Ledger rows carry synthetic firm and product names,
versions and outcomes only: no handle, connection ID, service URL, account or consent-page capture.
Each assertion passes only when observed in the host:

- Connect from Libraries setup opens the browser; the pairing display matches; SketchUp stays responsive
  during the wait; the connection reaches `connected` with the firm label; a replayed callback is refused.
- Materials, Frames and Glazings load `ready` as revisioned snapshots.
- A copy carries `source_revision` and `source_revision_schema_version`, through native Undo and Redo,
  local edit, keep-local and use-library to a newer revision; two revisions with identical mapped content
  stay distinguishable.
- Save and fresh-process reopen keep the revision and restore the connection from the Keychain.
- A credential replace interrupted by a forced quit leaves either the old or the new item, never a
  partial one, and the next launch recovers or asks to reconnect.
- A model switch with a load in flight and a second open Model apply nothing to the wrong Model.
- Cancel in the browser and Cancel in Composer while authorizing end in `disconnected` with nothing stored.
- A firm change, revoke from the service, an archived record refused by use-library with reload, and an
  offline reopen each give the expected state, with local copies untouched.
- Disconnect removes the Keychain item, clears loaded data, keeps copies, and the service sees the revoke.
- No credential or credential-bearing URL in the SKP, HtmlDialog data, Ruby Console, logs or either export.

Not observable on demand and recorded as such: a loopback port collision, a locked keychain, the prompt
after a SketchUp upgrade. SketchUp 2023 to 2025 and Windows stay UNKNOWN.

## History: the 2026-09-30 scope (superseded by D5-1)

The stage first owned one generic connection the user points at an address, a one-page HTTP
protocol (`GET /library`, `GET /library/<kind>`, an auth discovery document), a port of the
predecessor's `runtime/http.rb`, `transport.rb`, `credentials.rb` and `connection.rb`, three sign-in
methods (none, static token, device-code approval), a Keychain helper process with the secret as an
argument, and a port of the predecessor's `tools/hostkit/library_server.py`. D2-8 (2026-10-01)
deferred it to Phase 5 while the PH-Navigator endpoint still served its older format. The table above
records what replaced each part.
