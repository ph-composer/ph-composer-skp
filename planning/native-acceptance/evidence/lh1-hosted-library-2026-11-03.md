# LH1 hosted Library host run

DATE: 2026-11-03
STATUS: Fail on one clause. Fourteen assertions pass; Composer does not show the pairing display (connect); the firm change is blocked by the test account
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/328

Synthetic summary of the first host run of case `LH1` in [cases.json](../cases.json), the
[P2-16 host gate](../../features/phase-05-post-mvp/phases/p2-16-connection-provider.md#host-gate-case-lh1),
with the first hosted extension (the PH-Elements connector) against a synthetic firm Library on the
PH-Elements service. Steps, read-backs and exports stay in gitignored `_private/host/phe-0608-20261103/`.

## Identity

| Item | Value |
| --- | --- |
| Source | `main` at 5c36a6fc (#331 merged); the seam from #329 and #330 |
| RBZ | `dist/ph_composer.rbz`, SHA-256 3d4dfa27…f9fd438, build 407a481f28d9 (commit 5c36a6fc31e9) |
| Hosted extension | PH-Elements connector at `44cfe3a`, installed beside the RBZ |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Fixture | `lh1.skp`, a fresh copy of a new SketchUp 2026 Model with no Composer records, SHA-256 12761552…0805b |
| Library | Synthetic Firm B: one Material, "T10 synthetic mineral wool"; empty Frames and Glazings |
| Controls | Ed at the mouse and browser for Connect, consent, Cancel, Reconnect, Disconnect and the service-side edits, archive and revokes; the development bridge for loads, copies, Undo and Redo, save, relaunch, faults and read-back; computer-use for the panel's Add to file and Cmd+Z |

## Results

| Assertion | Result | Observation |
| --- | --- | --- |
| connect | fail | Connect opened the default browser; consent reached `connected` with the firm label; SketchUp stayed responsive; no Keychain prompt. Composer never shows the pairing display the consent page asks the user to compare: the extension does not pass it on and the v2 connection row has no field for it |
| replayed-callback | pass | Reloading the used callback was refused (listener closed); the connection was unaffected |
| load | pass | Materials, Frames and Glazings `ready` as revisioned snapshots; empty kinds `ready`, not `unavailable` |
| copy-undo-redo | pass | The copy carries `source_revision` and `source_revision_schema_version` 1; Cmd+Z in the panel removed it, Cmd+Shift+Z restored it. Edit > Undo is disabled while the panel is key |
| newer-revision | pass | Local edit kept the revision; keep-local wrote nothing; use-library adopted the newer revision with the Library values; Undo and Redo exact for each |
| identical-content | pass | Two revisions with the same mapped content (same fingerprint) stay distinguishable: keep-local did not adopt the newer one, use-library recorded it, Undo and Redo switched between them |
| reopen-keychain | pass | Save and fresh-process reopen kept the revision; the connection returned from the Keychain and the next load was `ready`. The row reads the provider name until the first service call restores the firm label |
| interrupted-replace | pass | A held Keychain write and `kill -9` during the rotated-credential write left the extension's spent marker, never a partial item; the relaunch read `reauthorization_required` and Reconnect recovered |
| model-switch | pass | A load started with a second Model opened in the same call completed in its own Model only |
| cancel | pass | Cancel on the consent page, and Disconnect while signing in, both ended `disconnected` with no Keychain item |
| firm-change | blocked | The account the extension signs in with belongs to one eligible firm |
| service-revoke | pass | After revoking on the service, a load moved the connection to `reauthorization_required` and kept the last batch `stale`; copies untouched |
| archived-record | pass | Use-library from a held snapshot after the record was archived refused `library.reload_required`, nothing written |
| offline | pass | Simulated in-process (an HTTP proxy to a closed loopback port); after a Model reopen the load ended `stale` with `library.offline`, the connection stayed `connected`, the copy intact; restored, the load was `ready`. A fresh-process launch while offline was not observed |
| disconnect | pass | Disconnect removed the Keychain item and stored connection ID, unloaded the catalog, kept the copy; the service showed the connection revoked |
| no-credential | pass | No service credential, code or handle in the saved SKP, the Model export, the Library export and its result, dialog reads, the Ruby Console log, Composer's log or SketchUp's preferences |

## Findings

- **Pairing display not shown** (connect): the consent page instructs the user to check that
  PH-Composer shows the same code, and nothing in Composer shows one. Needs a display-only field in the
  v2 connection row while `authorizing`, filled by the extension.
- **No loading state for a hosted Library** in the sidebar: [#332](https://github.com/ph-composer/ph-composer-skp/issues/332).

Not observable on demand: a loopback port collision, a locked keychain, the prompt after a SketchUp
upgrade. SketchUp 2023 to 2025 and Windows stay UNKNOWN.
