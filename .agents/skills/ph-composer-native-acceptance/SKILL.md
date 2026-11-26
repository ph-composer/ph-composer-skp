---
name: ph-composer-native-acceptance
description: Run or resume PH-Composer acceptance cases in real SketchUp, preserving fixture and installed-build identity, native evidence, fault restoration, and check reuse. Use for SketchUp host gates and lifecycle validation; do not use for ordinary offline tests.
---

# PH-Composer Native Acceptance

Run bounded real-host acceptance batches against the owning packet and [case ledger](../../../planning/native-acceptance/README.md). This skill does not authorize features, releases, or restarting unrelated documents. Read the machine-level host-automation guidance (`~/.codex/references/machine-workflows.md`) before controlling SketchUp.

## 1. Case Execution Procedure

1. **Select cases:** Pick a bounded batch of named cases from the owning packet and case ledger. Use ledger dependency paths to screen impacted cases, not to bypass required final gates.
2. **Choose control route:** Follow [native-control capabilities](../../../context/NATIVE_CONTROL_CAPABILITIES.md) to pick bridge calls, native controls, or a human action. Use public operations for product writes; label development-eval fixture/fault setup separately.
3. **Preflight & baseline:** Follow [ACCEPTANCE_RUN.md](../../../tools/hostkit/ACCEPTANCE_RUN.md). Run `tools/hostkit/acceptance_case.py begin` ([one-case-in-two-commands](../../../tools/hostkit/ACCEPTANCE_RUN.md#one-case-in-two-commands)) to verify session, tool, edit path, unmodified synthetic fixture, and installed `dist/ph_composer.rbz` match, capture an immutable run baseline, snapshot the ledger, and initialize `steps.md`. Confirm window activation, target, probe callbacks, and evidence writer before any human handoff.
4. **Drive & observe:**
   - Separate action and readback calls so SketchUp UI timers run.
   - Capture native window pixels for drawing/UI claims and actual references/records for persistence claims. Run required refusal, rollback, Undo/Redo, and reopen checks directly; never infer them from object counts.
   - Wait for deferred work with `host_bridge.py wait-for` and read logs with `host_bridge.py diagnostics` (`--run-id` for exports); save `--json` outputs as evidence.
   - Distinguish queued, translating, and completed states before lifecycle actions (tools-only delays may make pending states reachable but must never ship).
   - Write each case's driver as a `.sh` script in its run folder from the first run, and record exact coordinates, window, camera, panel size, probe setup, and readbacks in `steps.md` so reruns do not rediscover them. Keep helpers in `tools/hostkit/` or the run folder, never only in ephemeral scratch space.
5. **Record results:** Finish via `acceptance_case.py finish <case>` (reads `<case>/observations.json`). Keep raw models, screenshots, traces, and real data in gitignored `_private/`; commit synthetic summary evidence only. Never retrofit provenance or mark a bridge-simulated callback as a native gesture. Unknown/interrupted outcomes stay unknown.
6. **PR timing:** For a PR still under review, record ledger results only on the merge head (later dependency fixes stale the row). Continue the authorized batch after checkpoints; stop for consequential decisions, inaccessible native actions, or scope frontiers.

## 2. Full-Screen Control & Screen Etiquette

- **Top-level holds only:** Call `request_full_control` only from the top-level session, never from a subagent. Subagents prepare everything needing no card (install, `begin`, setup, driver, recipe) and stop with `"ready for hold"`; the top-level session takes one card, runs all native steps, and hands evidence back.
- **Multi-stage loops:** Ask Ed once at loop start whether he is at the Mac. If not, show no full-screen cards; run bridge/System-Events checks per stage, mark native-gesture rows owed, and execute all owed cases in one batched sitting on the final head under one card.
- **Hover caveat:** Synthetic pointer moves trigger a Ruby tool's `onMouseMove` intermittently. Bridge-invoking the handler at the screen point verifies drawing only; record it as a labelled simulation and keep the native hover assertion owed until a real pointer reaches it.
- **Warn before changing the screen:** Tell Ed in one line before bringing SketchUp forward (`host_bridge.py show-model` fires `onActivateModel`) or running anything that may trigger a macOS permission/System Settings prompt. Never answer OS prompts yourself. Front and restore apps via System Events (`set frontmost of process "<App>"`), not `tell application`.
- **Human handoffs:** State the exact action, expected visual cue, and release condition.

## 3. Faults & Normal-Build Restoration

- Reproduce faults with `host_bridge.py fault arm|observe|restore` on a fixture under `_private/host/`. If `restore` does not return `restored: true`, stop the case.
- Check open documents before `launch` (which can quit/kill the host); never discard unrelated work.
- After private fault or provider overrides, verify normal-build restoration as its own observed result: fresh SketchUp process, normal installed RBZ, no dev monkeypatches or live runtimes, clean saved synthetic model, and expected normal success/refusal.

## 4. Agent-Client Benchmarks

When measuring an agent client against PH-Composer, isolate it from operator config (no personal skills, memory, advisor, plugins, or notes):

- **Claude Code:** Run `claude -p --restricted --strict-mcp-config --mcp-config <file> --tools Read` from a scratch directory (avoid `--bare`, which requires an API key).
- **Codex:** Use a scratch `CODEX_HOME` containing only a symlink to `auth.json` (so neither `config.toml` nor `AGENTS.md` loads) and pass the server via `-c`.
- Verify isolation from the transcript before recording cost or tool-choice metrics; mark any run that loaded operator notes or an advisor as contaminated.

## 5. Receipts & Resume Notes

Update the [current execution receipt](../../../tools/hostkit/ACCEPTANCE_RUN.md#current-execution-receipt) in the owning packet while preserving linked historical evidence. Maintain a compact resume note (batch/case, fixture/session/build, accepted decisions, verified checks and invalidation triggers, reviewer, remaining action, restoration state); do not reload closed phases or rerun passing checks after chat compaction.
