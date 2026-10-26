# PH-Composer: agent guidance

This is the canonical, tool-neutral guidance for the repository. Agents read it directly; there is no
per-tool instruction file.

## Scope and product boundary

PH-Composer is a free, open-source SketchUp extension for authoring Phius passive building
models. The SKP file owns working definitions, instances, assignments and values. Hand entry is a
complete workflow. Library providers are optional and interchangeable. Hosted projects, accounts,
subscriptions and database services are not required for core use. The canonical output is
HBJSON; the METr model is produced from it by the first exporter.

Read [`planning/FOUNDING_BRIEF.md`](planning/FOUNDING_BRIEF.md) for why this repository exists and what it inherits,
then [`docs/PRD.md`](docs/PRD.md) and [`docs/.index.md`](docs/.index.md) for product scope. The
predecessor, PH-Navigator for SketchUp at `../../ph-navigator-sketchup`, is prior art and evidence,
not a dependency. Its designPH integration is retired and is never reintroduced here.

## Start with the owning authority

| Work | Read first |
| --- | --- |
| Why the project exists, what transfers, open decisions | [`planning/FOUNDING_BRIEF.md`](planning/FOUNDING_BRIEF.md) |
| Product language | [`context/UBIQUITOUS_LANGUAGE.md`](context/UBIQUITOUS_LANGUAGE.md) |
| Architecture, host behavior, transactions, seams, runtime | [`context/TECH_STACK.md`](context/TECH_STACK.md) and [`context/SKETCHUP_HOST_BEHAVIOR.md`](context/SKETCHUP_HOST_BEHAVIOR.md) |
| Core mechanics cited by code: registration, API, outcomes, revisions, retries, records, references | [`context/CONTRACTS.md`](context/CONTRACTS.md) |
| Coding and compatibility rules | [`context/CODING_STANDARDS.md`](context/CODING_STANDARDS.md) |
| Contributor architecture, scripting and extension contracts | [`context/EXTENSIBILITY.md`](context/EXTENSIBILITY.md) |
| External agent access, discovery, model reads and writes | [`context/AGENT_INTERFACE.md`](context/AGENT_INTERFACE.md) |
| Security: disclosure route, listener posture, page policies, release checklist | [`SECURITY.md`](SECURITY.md), [`context/AGENT_INTERFACE.md`](context/AGENT_INTERFACE.md) "Security posture", [`context/TECH_STACK.md`](context/TECH_STACK.md) "Panel", [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) (release checklist, `lint-paths`) |
| Build, install, test and host procedures | [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), implemented commands and remaining host gates |
| Development host and browser tooling: bridge, bounded waits, diagnostic reads, fault controls, browser failure evidence | [`tools/hostkit/.index.md`](tools/hostkit/.index.md) and [`tools/ui-preview/.index.md`](tools/ui-preview/.index.md) |
| Native acceptance and resuming host gates | [`.agents/skills/ph-composer-native-acceptance/SKILL.md`](.agents/skills/ph-composer-native-acceptance/SKILL.md), then the owning packet and case ledger |
| Current delivery state or next authorized work | [`planning/STATUS.md`](planning/STATUS.md), then the owning packet |
| Planning documents or status changes | [`planning/.instructions.md`](planning/.instructions.md) |

`AGENTS.md` is not a phase ledger. Resolve current work from the branch, the planning index and
the owning packet.

## Repository-specific invariants

- Keep proposed product behavior distinct from implemented contracts. Product shape belongs in
  `docs/`; the durable rules that constrain code belong in `context/`; plans, decisions, status
  and acceptance evidence belong in `planning/`. Feature behavior is proposed until its owning
  packet records implementation and acceptance; `planning/STATUS.md` says which phases have.
- Feature interviews establish shared understanding but do not authorize code. Follow the current
  owning plan and explicit implementation scope.
- The model is the authoring authority. Library records become editable local copies. No provider
  is privileged, and no provider address is a default the software ships.
- Four layers, one dependency direction: Ruby model, JavaScript UI kit, Python translation,
  Python exporters. The UI kit carries no calculation and no honeybee dependency. Contributor
  contracts are defined in `context/EXTENSIBILITY.md`. Built-in features use those same public
  interfaces. A contribution needing a special case in core orchestration exposes a contract
  defect; explicit composition-root registration is permitted.
- Face types and boundary conditions are honeybee's. Do not coin a third vocabulary.
- Link measured host claims to the predecessor's evidence or to current host evidence instead of
  restating them. Restated technical facts drift. Predecessor evidence lives under
  `../../ph-navigator-sketchup/planning/archive/`.
- Preserve the public-repository boundary. Licensed PHPP workbooks, designPH files, METr exports
  of real projects, and PHI or Phius source material do not enter this repository. Use synthetic
  fixtures; real files live in a gitignored `_private/` corpus with a `MANIFEST.md`, and tests
  that need them skip when it is absent.
- For licensing, shipped third-party payloads or external contributions, read
  [`docs/LICENSING.md`](docs/LICENSING.md) and [`docs/DCO.md`](docs/DCO.md). There is no CLA and no
  commercial license. Every commit carries a DCO sign-off; a pull request without one is not merged.
- Everything under `docs/`, plus `context/UBIQUITOUS_LANGUAGE.md`, may be read by external
  partners. Write those in the client-facing register without em dashes or en dashes, and keep
  licensing negotiation, partnership posture, client-derived information and local scratch out of
  them. The founding brief is internal and lives in `planning/`.
- Public distribution, Windows support and certification claims require their explicit gates. A
  local implementation, a bridge action or a current-host walkthrough is not a release claim.

## Runtime and compatibility

- SketchUp 2023 is the compatibility floor. Shipping Ruby remains compatible with Ruby 2.7, and
  HtmlDialog JavaScript remains compatible with Chromium 88. The floor's own host proof is pending.
- The shipped Pyodide runtime and wheels are pinned by a vendor manifest. After changing shipped
  Python or panel assets, refresh the manifest before the full gate.
- Preserve native SketchUp transaction, Undo/Redo, observer, modal-dialog, active-edit-path and
  multi-model behavior. The durable rules are in `context/TECH_STACK.md`.
- Never update a golden merely to make a failure disappear.

## Verification

- `make ci` is the implemented full offline gate. Use focused tests while editing. The git hooks
  in `.githooks/` lint and type-check the staged files on every commit and refuse a message without
  a DCO sign-off (`docs/DEVELOPMENT.md`, "Git hooks"). Chain the gate, as in `make ci && git commit
  -s`, never `;`, and never bypass a hook with `--no-verify`.
- Real-host acceptance uses the development bridge plus native controls. A required host gate runs
  against the specified model and host state, often from a fresh process. Offline tests, an
  installed RBZ or a bridge command alone do not satisfy it. Ask Ed to operate the host only when
  the bridge and native controls cannot reach the necessary step.
- Observe the host with the development tooling rather than ad hoc evals: wait for deferred work with
  `host_bridge.py wait-for` (never a sleep inside an eval), read what happened with
  `host_bridge.py diagnostics`, and reproduce a failure with `host_bridge.py fault`, whose `restore` must
  report `restored: true` before a fresh normal process closes the case. Their JSON results are
  evidence files for a case. Browser checks run through the shared collector in
  `tools/ui-preview/support/browser_evidence.cjs`; a new check uses it and declares any error it
  provokes with `expect`.
- Keep context, planning and status documents synchronized with verified work. Distinguish
  implemented, host-verified, merged, released and publicly supported.

## Architecture and code review

Before designing contribution boundaries or making substantive code changes, load
`.agents/skills/ph-composer-architecture-review/SKILL.md`. Apply it during design and use it
as the rubric for the existing coherent-diff review. This applies when using `implement`,
`implement-loop`, `simplify` or direct implementation. Reuse loaded context within a coherent task.

For substantive Ruby work, also load `.agents/skills/ph-composer-ruby-quality/SKILL.md` and give
its Ruby criteria to that same reviewer. It covers phase review and a separately authorized,
one-module refactor. The criteria live in `context/CODING_STANDARDS.md`, "Ruby readability and
contributor review". A review invocation alone authorizes no shipping-code edits.

Keep the shared implementation skills unchanged. Use the established review ladder and give its
reviewer this project rubric; do not add a second equivalent review. Record the outcome and
remaining acceptance evidence in the owning packet. Documentation-only edits use a focused
consistency review; they do not trigger code or host gates.

## UI and UX work

Before changing or reviewing an HtmlDialog screen, load
`.agents/skills/ph-composer-ui-polish/SKILL.md` and its linked reference. The owning feature
plan and current source remain authoritative for behavior and acceptance; the skill governs the
shared review and polish process without widening scope.

## Repository map

`src/ph_composer/` is the shipping extension. `PhComposer` and the `ph_composer` prefix are the
working namespace D8 confirmed; the final public name is still open. The following owners are implemented:

| Path | Owns |
| --- | --- |
| `extension.rb` | The composition root: the feature list (`FEATURES`), the foundation capabilities (`FOUNDATION_FEATURES`) and the load order |
| `core/` | What several features need and none owns: the record engine, dictionaries, JSON and declaration-schema builders, geometry and units primitives, model operations |
| `session/` | One `ModelSession` per open Model, its generation, observers and per-feature state objects. Names no feature |
| `shell/` | Transport and the action registry: the panel dialog, actions, commands, preferences. Names no feature |
| `features/` | One folder per feature, each registering itself in one `install`. `zones/` owns Zones, Faces and adjacency; `assemblies/` owns Materials and Assemblies; `windows/` owns products, Types, Units and Aperture export; `thermal_bridges/` owns Thermal Bridge Types, Edge assignments, runs, the edge tool and the thermal-bridge export section |
| `colour_by/` | The shared Colour-by service: the mode registry's consumers, the viewport overlay and HUD, and the drawing cache. Names no feature |
| `library/` | The optional provider seam, file/folder provider, catalog/copy coordinator and model-library export |
| `agent_access/` | Local agent access: the token store and the Agent Access dialog, a foundation capability with no public operation |
| `export/` | The export run: contributors, the attribute guard, artifact hygiene, the report, and the exporter registry |
| `html/` | The panel: the UI kit at its top level (a module graph with a generated script list and owned stylesheets), the foundation's screens in `sections/` and `library/`, one folder per feature in `features/`, and other dialogs' pages in their own folder with a generated script list (`agent_access/`) |
| `python/`, `runtime/`, `vendor/` | The translation package and exporter registry (no exporter registered yet), the Pyodide loader and the pinned payload |

Outside it: `tests/` for the offline suites and fixtures, `tools/` for development-only build,
runtime, UI-preview and hostkit tooling that never ships, `docs/` for the product written for a
reader who is not building it, `context/` for the durable authorities, and `planning/` for active
plans and archived evidence.
