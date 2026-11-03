# LH1 hosted Library host run 2

DATE: 2026-11-03
STATUS: Pass. All sixteen assertions observed on the build that includes the pairing display (#334)
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/328

Second host run of case `LH1` in [cases.json](../cases.json), the
[P2-16 host gate](../../features/phase-05-post-mvp/phases/p2-16-connection-provider.md#host-gate-case-lh1),
after [run 1](lh1-hosted-library-2026-11-03.md) failed only on the pairing display. Same synthetic firm
Library on the PH-Elements service. Steps, read-backs and exports stay in gitignored
`_private/host/phe-0608-20261103-r2/`.

## Identity

| Item | Value |
| --- | --- |
| Source | `main` at 4c9df4c5 (#334 and #335 merged) |
| RBZ | `dist/ph_composer.rbz`, build d511e59d1f68 (commit 4c9df4c52866) |
| Hosted extension | PH-Elements connector at `370b511` (pairing display, issuer-bound credentials) |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Fixture | `lh1.skp`, a fresh copy of the same blank SketchUp 2026 Model as run 1 |
| Library | Synthetic Firm B (one Material, "T10 synthetic mineral wool"); Synthetic Firm C for the firm change |
| Controls | Ed at the mouse and default browser for the first Connect, the web edits, archive and revokes, one Disconnect and two authenticator codes; the development bridge for loads, copies, Undo and Redo, save, relaunch, faults and read-back; a built-in browser signed in as a second synthetic member for the later consents, Cancel and the firm change |

## Results

| Assertion | Result | Observation |
| --- | --- | --- |
| connect | pass | The Libraries row showed the same pairing display as the consent page (four consents, all matching); connected with the firm label; responsive; no Keychain prompt; the stored item names its issuer |
| replayed-callback | pass | A reloaded callback was refused; the connection was unaffected |
| load | pass | Materials, Frames and Glazings `ready` as revisioned snapshots; empty kinds `ready` |
| copy-undo-redo | pass | The copy carries `source_revision` and schema version 1; native Undo and Redo exact |
| newer-revision | pass | Local edit kept the revision; keep-local wrote nothing; use-library adopted the newer revision; Undo and Redo exact |
| identical-content | pass | Two revisions with the same fingerprint stay distinguishable; keep-local did not adopt the newer one |
| reopen-keychain | pass | Save and fresh-process reopen kept the revision and restored the connection from the Keychain |
| interrupted-replace | pass | `kill -9` during a held credential write left a complete item and the next launch recovered (run 1 left the spent marker and asked for a sign-in; both are complete outcomes) |
| model-switch | pass | A load with a second Model opened completed in its own Model only |
| cancel | pass | Disconnect while signing in and Cancel on the consent page both ended `disconnected` with nothing stored |
| firm-change | pass | A second Connect choosing another firm relabelled the row under a new connection, served the new firm's Library, kept copies and revoked the replaced connection at the service |
| service-revoke | pass | Revoke on the service moved the connection to `reauthorization_required`, the last batch `stale` |
| archived-record | pass | Use-library from a held snapshot after an archive refused `library.reload_required`, nothing written |
| offline | pass | Simulated in-process; `stale` with `library.offline`, the connection kept, then `ready`. A fresh-process launch while offline was not observed |
| disconnect | pass | Keychain item removed, catalog cleared, copies kept, the service revoke landed |
| no-credential | pass | No service credential, code or handle in the SKP, either export, dialog reads, the Ruby Console log, Composer's log or preferences |

## Notes

- The PH-Elements consent asks an Owner for a fresh authenticator code on every consent.
- Before the run, an item stored before the extension bound credentials to their issuer read as needing
  a sign-in and was never sent.
- Open, outside LH1: the consent page's organization choices expose IDs, not names, to assistive
  technology; no hosted loading state or Cancel ([#332](https://github.com/ph-composer/ph-composer-skp/issues/332)).

Not observable on demand: a loopback port collision, a locked keychain, the prompt after a SketchUp
upgrade. SketchUp 2023 to 2025 and Windows stay UNKNOWN.
