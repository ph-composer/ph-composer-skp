# Native acceptance ledger

DATE: 2026-10-07
STATUS: Development tooling implemented. Historical Phase 1 acceptance remains with its packet.
ISSUE: none (local tooling work)

[`cases.json`](cases.json) holds case identities, owning authorities, deferred scope and source
dependency patterns. [`results.jsonl`](results.jsonl) is an append-only result index with
15 historical evidence pointers and 59 observed results. Historical pointers are not reconstructed host runs. Detailed case requirements
and closure remain in [the owning acceptance register](../archive/phase-01-faces-and-zones/ACCEPTANCE.md). Add finer case IDs
when a gate needs independent reruns; a partial subcase does not close its parent.

[`evidence-locations.json`](evidence-locations.json) maps original evidence paths to their current
archive locations. Ledger reads and status output resolve these exact paths without changing
recorded observations, timestamps, build provenance or the result index. New observations must
cite existing files directly. Missing or unsafe archive locations fail validation.

On 2026-10-07, the leftover Phase 2 redirect folder and evidence symlink were removed. Four path
mappings preserve the seven original result rows that referenced that folder. Phase 2 remains
[accepted and archived](../archive/phase-02-envelope/STATUS.md); this cleanup grants no new acceptance.

Cleanup verification: all 70 result rows validate, the result index is byte-for-byte unchanged,
and all local targets in 351 tracked Markdown files exist. Eight focused ledger tests and the
bounded tooling/documentation review passed. Every `make ci` target passed, with Python checks
and packaging resumed after correcting a test type annotation. No shipping behavior changed.

The Phase 1 packet is archived and stays unchanged. Later reruns record synthetic summaries under
[`evidence/`](evidence). Completed run handoffs are disposable instructions; their outcomes and
limitations belong in the evidence summary and result index. The three completed 2026-09-30
handoffs have been deleted. Keep future temporary handoffs under gitignored `_private/host/`;
keep reusable procedures in the owning packet, hostkit tooling and native acceptance skill.

## Retained evidence

Every summary below is referenced by the append-only result index. Older results identify the
build actually tested and retain observations beyond a later rerun's scope; a newer result does
not make them disposable.

| Summary | Purpose |
| --- | --- |
| [AW01 target safety](evidence/aw01-target-safety-2026-11-10.md) | Agent-workflows AW-01: claimed-contents Make Zone refusal, legacy overlap finding and removal guard, strict null Face identity, locked Zone edits, Space create receipt, native Undo/Redo and fresh-process reopen (`AW01`) |
| [AW03 inventory and candidates](evidence/aw03-inventory-candidates-2026-11-10.md) | Agent-workflows AW-03: side-effect-free candidate reads, Make Zone at the root and in a rotated wrapper, first Space, Edge assignment by path with world end points, stale refusals, native Undo/Redo (`AW03`) |
| [AW04 definition detail](evidence/aw04-definition-detail-2026-11-10.md) | Agent-workflows AW-04: 30 KB metadata fragments, 10 x 10 Type, 30 x 12 Assembly and uses pages, oversized preview by part (`AW04`) |
| [AW05 occurrence detail](evidence/aw05-occurrence-detail-2026-11-10.md) | Agent-workflows AW-05: Unit metadata, 450-hole host, run members against InstancePath, areas, guarded metadata update (`AW05`; blocked on restore offers and Floor Segment loops the fixture lacks) |
| [AW06 library paging](evidence/aw06-library-paging-2026-11-10.md) | Agent-workflows AW-06: catalog warnings and note paging, stale generation, copy-and-assign in one Undo step, compact export round trip (`AW06`) |
| [AW07 export QA and repair](evidence/aw07-export-qa-repair-2026-11-10.md) | Agent-workflows AW-07: compact and paged preflight, kept diagnostics of a refused run, Edge record repair with native Undo/Redo of exact bytes, written run hashes, save and reopen (`AW07`) |
| [AW08 client profiles](evidence/aw08-client-profiles-2026-11-10.md) | Agent-workflows AW-08: two Model-only profiles per client in fresh Claude Code and Codex sessions, replacement shown, stale and read-only refusals, port repair, revoking one profile leaves the other working, dialog at 560 and 360 widths (`AW08`) |
| [LH1 hosted Library, run 2](evidence/lh1-hosted-library-2026-11-03-run2.md) | P2-16's host gate on the build with the pairing display: all sixteen assertions pass, including the firm change (`LH1`) |
| [LH1 hosted Library](evidence/lh1-hosted-library-2026-11-03.md) | P2-16's host gate with the PH-Elements connector: connect, load, copy and revisions, Keychain reopen and interrupted replace, cancel, revoke, archive, offline, disconnect, credential sweep (`LH1`; fails on the missing pairing display) |
| [Production support PS-05](evidence/production-support-ps05-2026-10-19.md) | Incident references, page faults, runtime deadlines, lost replies, preference writes, Help & Diagnostics, the support report and help links on the installed build (`PS1` to `PS9`) |
| [Assembly Layer drag](evidence/assembly-layer-drag-2026-10-15.md) | Native grip drag, one native Undo and Redo per drop, draft/Escape/blur refusals, reversed orientation and fresh-process reopen (`E18`) |
| [Libraries picker actions](evidence/library-picker-actions-2026-10-07.md) | Equal file/folder actions, unreadable setup and fresh normal restoration with preserved preferences |
| [UI refinement closeout](evidence/ui-ux-refinements-2026-10-07.md) | Checked-Zone Solve, viewport masks including nested/shared occurrences, Assembly hatch/selection edges, native paint/Undo, matching Colour-by and narrow layout |
| [Managed Zone options](evidence/zone-field-options-2026-10-05.md) | Managed choices/dialogs, exact Undo/Redo, ID filters/custom hues, native copy/split/Restore, explicit destination adoption and normal reopen |
| [R06 after PR #7](evidence/r06-rerun-2026-09-30.md) | Panel-closed API evidence and the control fallback cited by the native-control reference |
| [UX follow-ups K1](evidence/ux-followups-k1-2026-09-30.md) | Colour-by evidence cited by the archived UX packet |
| [UXK1 rerun](evidence/uxk1-rerun-2026-09-30.md) | Later build baseline for the bounded Colour-by case |
| [Phase 1 after PR #10](evidence/phase-1-recheck-2026-09-30.md) | Ten-case recheck, walkthrough probe corrections and draft-settings observation |
| [Phase 1 for PR #11](evidence/phase-1-recheck-pr11-2026-09-30.md) | Later ten-case recheck including the settings gear draft guard; R05 pending visibility remains `unknown` with Ed's acceptance of offline coverage |
| [R11 host gate](evidence/r11-host-gate-2026-10-02.md) | Library dialogs, export replace, paging, Window Type grid gestures, panel navigation and unreadable setup on the installed build |
| [Library product tabs](evidence/library-product-tab-headers-2026-10-03.md) | Library heading New, Psi-Install defaults in the action bar, depth bubble, one Undo step each, setting-choice marking fix |

Raw Models, screenshots and traces live outside this folder in gitignored `_private/`. They are
not part of this cleanup.

## Resume and screen affected checks

```sh
uv run tools/hostkit/acceptance_ledger.py validate
uv run tools/hostkit/acceptance_ledger.py status --changed src/ph_composer/colour_by/service.rb
uv run tools/hostkit/acceptance_ledger.py snapshot A12 --output _private/host/a12-baseline.json
```

`--changed` is repeatable and takes repository-relative paths, including deleted/renamed paths.
Supply both sides of a rename. This is a dependency screen, not automatic acceptance. Check newly
added feature dependencies and change the catalog when its coverage is incomplete. Source
fingerprints include tracked and nonignored new files matching the case, with names and contents.
Only affected cases need targeted repeats; the packet's required final gates still apply.

A case's paths name the code its assertions exercise, not the documents that describe it: no case
depends on `context/`, so a documentation edit screens nothing (R06 keeps `docs/API_QUICKSTART.md` and
`docs/API_REFERENCE.md`, because it runs the documented quickstart). Changing a case's paths does not by
itself make its result stale: a result recorded under an earlier list stays current while the files the
current list names are unchanged since the result's commit, read from git's objects, and that commit
reproduces the result's recorded fingerprint (a result captured on uncommitted changes does not qualify). Narrowing drops
files the result never needed; widening adds files that have not changed since it was observed. When the
commit is not available locally, the result reads `needs_recheck`.

A case names the foundation files its feature reaches, not the foundation folders. Its `core/`,
`session/` and `shell/` files are the ones its feature, walkthrough and test files name by constant,
followed through those folders. Feature code reaches `session/model_session.rb`, `shell/dispatch.rb`
and `shell/panel.rb` through objects it is handed, and a foundation query or action by its id
(`ph_composer.records.`, `.context.`, `.view.`, `.locations.`), so a case that reaches them names their
files; a case that lists `core/records/engine.rb` lists `core/records/catalog.rb`, since an engine is
handed its catalog. Its `html/` files are its features' panel modules and their declared dependencies,
the modules its tests start, the panel's boot files (`index.html`, `module.js`, `panel.js`,
`sections/shell.js`) and the UI kit stylesheets. Its `tests/support/` files are the ones its tests
load. A subfolder whose every file a case reaches is one pattern (`core/operations/*`,
`tests/support/sketchup/*`, a feature's panel folder) and also covers files added to it later. Only the
whole-product cases A16 and E17 keep the top-level folder patterns, so a new file anywhere else in
those folders screens only those two until the catalog names it in the cases that reach it. A case
whose authority checks a screen its own paths do not name lists that screen as well: E01 keeps the
Zones and Export panels it checks load unchanged, and A12 the runtime page its runtime host loads. The
extension loads every foundation file and the panel loads every module, so a file that fails to load
breaks every case; the offline gate loads both, and that failure is its to catch rather than a case's.
Every pattern matches at least one source file; the ledger tests check these rules.

The catalog has no retired state, an indexed result keeps its case, and `deferred` refuses a case that
has results. A case whose feature is gone therefore stays in the catalog with its history, its label
naming what superseded it, and is not rerun: R05, the Zone details draft, since 2026-10-04.

| Change or condition | Checks to reconsider |
| --- | --- |
| Geometry, identity, records, operations or observer/session contracts | Dependent authoring/reference/export cases; relevant rollback, native Undo/Redo and reopen |
| Colour-by drawing/cache or visibility | A08 native pixels/occlusion/invalidation and affected timing; authoring if picking changes |
| Panel/tool keyboard, navigation or focus | A04/A07/A09 and export panel/lifecycle cases affected by the control |
| Translation, exporter, report, privacy or artifact commit | A10 to A14 and A16 as matched by dependency paths; canonical reload/reference/accounting/recovery |
| Runtime wheels, manifest, packaging or environment | Runtime/payload/parity and installed-build cases; platform proof is specific to that environment |
| Bridge/control helper or fixture/assertion recipe | Native cases depending on it; a helper change can change what the test actually establishes |
| Host/Ruby/OS/graphics/controller, fixture hash, installed RBZ or composition changes | Review corresponding native conditions even if source fingerprint is unchanged. A new session alone is not evidence of new product behavior |
| Documentation-only narrative/status edits | Focused consistency/link review; no automatic code/host rerun. Changed contracts or acceptance criteria require dependency review |

Historical evidence is preserved unless relevant changes or a changed claim make it insufficient.
The tool cannot prove the current environment from source hashes; a source-unchanged result is not
an automatic current-host pass. Unmapped changes require review of the catalog rather than silence.

## Record a new observed run

Capture a baseline before the action. Fill a copy with `evidence_kind: "observed"`, the observed
`outcome` (`pass`, `fail`, `blocked`, `unknown`), and `assertions`, each containing `status` and a
concrete `observation`. Add existing repository-relative `evidence` paths and a `control` route
(`bridge`, `native`, `human`, `combined`). A native/mixed result also needs `host` fields:
`sketchup`, `ruby`, `session_id`, `fixture_id`, `fixture_sha256`, `rbz_sha256`, `composition`
(`normal` or `synthetic`). Include optional `os` and `graphics` when they govern the claim.

The host tuple and hashes must be obtained from the actual tested host, fixture and installed RBZ;
`git HEAD`, a built RBZ and a fixture name alone cannot prove the installed build. Snapshotting
source is read-only and performs no host interaction or acceptance case. Record observed timestamps
and assertions, not inferred outcomes. The result is an attestation, not a test runner.

```sh
uv run tools/hostkit/acceptance_ledger.py record --input _private/host/a12-observed-summary.json
```

Only synthetic, publication-safe summaries belong in tracked results. Store raw Models, captures,
traces and artifacts in gitignored `_private/`. Review the summary before recording; arbitrary
free text still needs human/agent judgment. Passing new records require a matching source baseline,
existing evidence and all assertions passing. Native-interaction cases refuse a bridge-only result.
Deferred cases require a separate scope decision and catalog update before new observed acceptance.

## Restoration and check reuse

Keep one independent reviewer for the coherent task. Record deterministic checks at exact build
checkpoints and the reason for rerun; do not turn every case into a new review/full-suite cycle.
The ledger reports observations, not merge/release readiness. Normal-build restoration after
private providers, faults or runtime delays is an additional observed case, with its own readback.
Use the [project skill](../../.agents/skills/ph-composer-native-acceptance/SKILL.md) and
[control reference](../../context/NATIVE_CONTROL_CAPABILITIES.md) for the native procedure.

## Immutable run and verification receipts

Use the [run harness and current execution receipt](../../tools/hostkit/ACCEPTANCE_RUN.md) for
preflight, assertion-specific dependencies, private observed evidence and repeatable package/link
checks. Baselines refuse overwrite, including the ledger snapshot command. The harness supplements
the case ledger without rewriting history, narrowing catalog dependencies automatically or granting
acceptance. Keep current state compact and link historical observations.

### Current tooling checkpoint, 2026-10-01

Implemented the immutable run harness and execution receipt procedure after the Phase 2
retrospective. Preflight requires actual observations; assertion screens never award acceptance.
Independent review identified unmatched dependency patterns as a reuse risk; capture now refuses
them, with regression coverage. Historical results and product acceptance are unchanged.

Verification: `make ci` passed, plus final hostkit ruff/format/mypy checks and 31 Python hostkit
tests. Ruby hostkit: 9 tests, 30 assertions. Local links and ledger validation passed. No shipping
behavior changed and no new native gate is claimed. Next use: capture the owning case's observed
preflight and immutable baseline before its next required native acceptance run.
