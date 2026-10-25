# PH-Composer: founding brief

**DATE:** 2026-09-20 | **STATUS:** Founding record. Phase 0 foundation merged through PR #1.
[Phase 1 planning](archive/phase-01-faces-and-zones/README.md) now owns the next delivery sequence; building features
remain unimplemented. The transplant tables below record the original predecessor inventory.
**OWNER:** Ed May, BLDGTYP

Current repository home: `ph-composer/ph-composer-skp`, authorized 2026-10-25.
The original decisions below retain their historical context. See the
[migration plan](features/unscheduled/github-organization-migration.md).

## The idea

PH-Composer is a free, open-source SketchUp extension for authoring Phius passive building
models. The consultant draws in SketchUp, assigns assemblies, windows, thermal bridges, spaces and
systems to the geometry inside SketchUp, and exports a complete, valid HBJSON model. A second
exporter converts that HBJSON to the WUFI-shaped JSON that METr reads.

The METr development team has no plan or capacity to build a graphical front end for METr, and on
2026-09-17 they endorsed a free, open-source SketchUp extension that exports to HBJSON and on to
METr. PH-Composer is to METr what the OpenStudio Application was to EnergyPlus: a community
front end for a calculator maintained by someone else.

The project is 100 percent free and 100 percent open source, licensed AGPL-3.0. Its purpose is not
only the tool but the community around it. BLDGTYP builds the foundation and the core patterns.
Anyone can add a piece.

## Where it comes from

PH-Navigator for SketchUp (`00_PH_Tools/ph-navigator-sketchup`, main at `f358ebf`) is the direct
predecessor. It was built as a companion to designPH for PHI projects: it adopted designPH's
assemblies and windows, pushed edits back, propagated geometry to designPH windows, and exported
HBJSON through honeybee-ph running in Pyodide. It works, and the affordances are good.

PH-Composer drops designPH and PHI, and with them the whole adopt, compare, push and propagate
machinery. It keeps the foundation that machinery sat on. The decision to start a fresh repository
rather than edit the predecessor down rests on four points:

1. The new work is larger than either the deletion or the kept code. Face assignment, assembly to
   face assignment, window geometry authoring and thermal bridge assignment do not exist in the
   predecessor. designPH owned all of them.
2. The predecessor's PRD, planning archive, acceptance contracts and vocabulary all describe a
   designPH companion. A contributor reading that history would learn the wrong product.
3. A new name means a new Ruby namespace, new attribute dictionary keys, a new extension ID and a
   new RBZ. That is a copy, not an edit.
4. If the panel is to be a UI kit that other teams reuse, the boundary has to exist from the first
   commit.

The predecessor becomes prior art, the same status it gave the earlier designPH proof of concept.

### What transfers

Measured on the predecessor at `f358ebf`, excluding the vendored payload.

| Transfers intact | Lines | Notes |
| --- | --- | --- |
| `core/` | 1,374 | Record engine, dictionaries, canonical JSON, geometry and unit primitives. designPH is one source kind of four in `core/records/sources.rb` and deletes cleanly. |
| `session/` | 347 | One session per open model, generation, observers. |
| `shell/` | 1,355 | Panel dialog, action registry, commands, preferences. |
| `runtime/` | 685 | Pyodide loader. |
| `html/` | 10,459 | The `Phn.define` module graph, split editors, eight owned stylesheets. designPH-specific modules are dropped. |
| `features/organization_library/` | 1,139 | Becomes the first library provider. |
| `tools/`, `tests/` harness, `planning/` conventions | | Host bridge, build, RBZ verification, offline suites. |

| Transfers stripped | Lines | Notes |
| --- | --- | --- |
| `features/spaces/` | 2,678 | 7 of 28 files touch designPH. |
| `python/ph_navigator_translation/` | 6,034 | Already produces HBJSON through honeybee-ph. The contract layer is shaped around designPH face types and bridges and is rewritten around PH-Composer's own records. |
| `export/` | 1,517 | Export run, attribute guard, artifact hygiene, report. |
| `features/assemblies/` builder, thermal, schema | ~1,600 | The Assembly Builder itself. |
| `features/windows/model/`, `panel/`, `export/` | ~2,000 | Window types, frames, glazings, install types. |

| Left behind | Lines | Notes |
| --- | --- | --- |
| `designph/` | 859 | The designPH dialect. |
| `features/assemblies/` adoption, push, states | ~1,200 | PushState and sync-state vocabulary. |
| `features/windows/` reviews, assign, compare, placement, designph | ~6,200 | Propagation to designPH windows. |
| `docs/PRD.md` and the planning archive | | Prior art. |

## Architecture

The contributor-facing principles are governed by
[`context/EXTENSIBILITY.md`](../context/EXTENSIBILITY.md), accepted on 2026-09-18. They extend the
initial seams below with record-kind and importer contracts, scripting and metadata affordances.
The exact APIs remain design work; no implementation is implied.

Four layers, each with one dependency direction. The initial four contribution seams are below;
the contributor architecture extends their contracts.

| Layer | Language | Owns | Depends on |
| --- | --- | --- | --- |
| Model | Ruby | Attribute dictionaries, record engine, sessions, transactions, Undo, observers | SketchUp API only |
| UI kit | JavaScript and CSS | The panel module graph, editors, grids, notices | The request channel contract, nothing else |
| Translation | Python in Pyodide | Model snapshot to HBJSON | honeybee-ph |
| Exporters | Python in Pyodide | HBJSON to METr JSON, later others | PHX |

Seams:

- **Feature.** One folder under `features/`, one `install` call in the composition root. This
  exists in the predecessor and carries over.
- **Library provider.** A contract for browsing and fetching definitions from an outside source.
  Every provider returns records that become editable local copies in the model. The first
  provider is a flat file, a folder of JSON records on disk, because it needs no account, makes
  tests trivial, and forces the contract to be honest. PH-Navigator is the second provider. METr,
  PassivSure and company APIs follow the same shape.
- **Export contributor.** HBJSON is the canonical interchange and the product's core promise. The
  METr writer is the first consumer of it. A third consumer adds a contributor without touching
  the model layer.
- **Colour-by mode.** One overlay, one legend, one viewport HUD; a feature registers a mode that
  colours faces or Zones by one of its fields. Decided in the face-assignment interview,
  2026-09-18.

The UI kit carries no honeybee dependency. That is what keeps it reusable by teams such as
PassivSure, who will continue to build a PHI-focused designPH companion, and it is what leaves
the licensing door open for a separable kit later.

## Scope

Core follows the walking-skeleton order in `ROADMAP.md`:

1. Zones and adjacency, then face assignment: what a Zone is, which faces are envelope and what
   is on the other side. Zones come first because a boundary condition may name another Zone.
2. Validation and the canonical HBJSON/report handoff. D12 defers METr export through PHX
   until further feature development; its return milestone is unscheduled. The Phase 1 construction is a development-only fixture, never a user
   fallback.
3. Assembly Builder and the file-library seam, carried over and generalized.
4. Windows: types, Frames, Glazings and Psi-Install Types carried over; window geometry authoring
   new.
5. Spaces, carried over and extended, then linear thermal bridges assigned to edges.
6. Mechanical equipment, ERV ducting and hot-water piping.

Post-MVP: climate, sun path, window performance overlays, further providers, PV and site work.
PH-Composer authors no window shading; METr handles it after export.

Out of scope: designPH in any form, PHI certification workflows, PHPP export, hosted projects,
accounts, subscriptions and database services. An organization library remains optional and is
never required to author or export a model.

## Decisions taken

| Decision | Date | Basis |
| --- | --- | --- |
| Drop designPH and PHI. Target Phius CPHCs and METr. | 2026-09-17 | Ed. METr team endorsement the same morning. |
| Fresh repository seeded by transplant, not an edit of the predecessor. | 2026-09-17 | The four points above. |
| Primary artifact is HBJSON. METr JSON is a second exporter. | 2026-09-17 | METr ingests WUFI-shaped JSON. PHX already converts HBJSON to it. |
| PHX runs inside Pyodide. | 2026-09-17 | Direct export from SketchUp, no second application. Subject to the spike below. |
| AGPL-3.0. | 2026-09-17 | Matches the vendored ladybug and honeybee wheels and the predecessor. |
| Strong separation between UI and business logic. Clear, modular boundaries as the first architectural goal. | 2026-09-17 | Ed. The project exists to be extended by other people. |
| Library provider contract, flat file first, PH-Navigator second. | 2026-09-17 | No hosted requirement. Many vendors, none privileged. |
| Development name and home: PH-Composer at `bldgtyp/ph-composer`. | 2026-09-18 | D8. Ed confirmed the bldgtyp organization for development. Neither the name nor organization is permanent; a future move requires an explicit decision. Namespace checks passed 2026-09-18; only the X handle was taken. |
| No commercial license. DCO instead of a CLA. | 2026-09-18 | Ed: a foundation library like OpenPH, not a revenue generator. Products may connect to it or build on it under AGPL. |
| UI kit remains AGPL for MVP; closed systems use file, HBJSON or HTTPS boundaries. | 2026-09-18 | D5. Reconsider a separately licensed package only for a real embedder. |
| The authored model is honeybee-shaped Ruby records in the SKP, translated to honeybee at export; honeybee is never run live. | 2026-09-18 | Ed, face-assignment interview Q1. The model must live in Ruby-written dictionaries regardless; authoring is partial where simulation is resolved; the panel needs sub-100 ms updates and native Undo; a contributor who knows honeybee recognizes every field. honeybee's names and enumerations are used wherever honeybee has them. |
| Colour-by is a shared component and the fourth contribution seam. | 2026-09-18 | Ed, face-assignment interview Q16. One overlay, one legend, one HUD; features register modes. |

## Open questions and first gates

The cross-cutting choices are consolidated in [`DECISIONS.md`](DECISIONS.md); feature-local
questions remain in their packet PRDs.

- **PHX in Pyodide.** [B1](archive/phase-00-foundation/evidence/spike-phx.md) passed with nine pinned
  wheels installed without dependency resolution. Phase 1 selects its HBJSON translation pins. The no-Spaces
  floor-area decision, PHX integration and actual METr import wait with the deferred exporter. Upstream optional-dependency cleanup remains a follow-up.
- **Public name, organization and namespaces.** Development remains PH-Composer at `bldgtyp/ph-composer`.
  Before public announcement, decide whether to keep that name and home, then claim only the
  namespaces that decision requires.
- **The contribution unit.** What a contributor's piece is called, and the worked example that
  shows how to add one through each supported contribution contract.

## Naming record

Eleven names were considered between 2026-09-17 and 2026-09-18. Kept here so the reasoning is not
repeated.

| Name | Why not |
| --- | --- |
| Trellis | Trellis Group (formerly GreenBiz) and Trellis Technologies both sell to the sustainability audience. Microsoft TRELLIS owns the 3D search results. No namespace free. |
| FreePH, OurPH, MyPH, FastPH | The xxxPH shelf is full: PHPP, designPH, easyPH, bim2PH, PHribbon, OpenPH, PHX. FreePH reads as a jab at paid tools. FastPH was the best of the four. |
| LibrePH | Clean namespace, says free as in freedom, the LibreCAD precedent. Kept as the runner-up. Cost: two unfamiliar tokens for a US CPHC, and the knockoff reading. |
| ConPHlux | Spoken, it is Conflux, a funded blockchain network. The mid-word capital PH breaks in every medium but a logo. |
| Storypole, Barnraising | Residential framing vocabulary. Wrong scale for a movement moving from houses to buildings. |
| Ridgepole | RubyGem taken by Cookpad's Rails schema tool. |
| Plenum | plenum.pro is HVAC field-service software sold to the same trades. |
| Stoa, Truss, Armature | Crowded. |
| Colonnade | Clean namespace, civic scale, many members holding one roof. Kept as the alternative if a brand matters more than findability. |
| PassiveMaker | "Maker" is coded hobbyist. Wrong register for a certification instrument. |
| PH-Composer | Chosen. Uses Phius's own term "passive building", found by search, "builder" says authoring. Cost: shares a search page with general contractors and carries no community signal. The tagline and README carry that. |

## References

Predecessor and prior art:

- PH-Navigator for SketchUp: `00_PH_Tools/ph-navigator-sketchup`, main at `f358ebf`. Read
  `AGENTS.md`, `docs/PRD.md`, `context/TECH_STACK.md`, `context/SKETCHUP_HOST_BEHAVIOR.md`,
  `context/CODING_STANDARDS.md`, `docs/LICENSING.md`, `docs/CLA.md`.
- designPH proof of concept: `00_PH_Tools/dph_reader_poc` and `00_PH_Tools/design-ph-plus`.
- PH-Navigator web: `00_PH_Tools/ph-navigator` and `ph-navigator-v2`, the second library provider
  after the library file. Its address is entered by the user; the software ships no default.

Libraries the runtime ships:

- honeybee-ph: https://github.com/PH-Tools/honeybee_ph
- PHX: https://github.com/PH-Tools/PHX
- PH_units: https://github.com/PH-Tools/PH_units
- Ladybug Tools honeybee-core, honeybee-energy, ladybug-geometry: https://github.com/ladybug-tools
- Pyodide: https://pyodide.org

Standards and calculators:

- Phius, what is passive building: https://www.phius.org/passive-building/what-passive-building
- METr, Phius's browser-based calculator, built by C3rro. WUFI-Passive model shape, JSON
  instead of XML. No public URL recorded here yet.
- WUFI-Passive: https://wufi.de/en/software/wufi-passive/
- OpenStudio Application, the analogy: https://github.com/openstudiocoalition/OpenStudioApplication

Naming and licensing:

- Can Passive House be trademarked, Green Building Advisor:
  https://www.greenbuildingadvisor.com/article/can-passive-house-be-trademarked
- AGPL-3.0: https://www.gnu.org/licenses/agpl-3.0.html
- SketchUp Extension Warehouse: https://extensions.sketchup.com

Partners:

- PassivSure: continues a PHI-focused designPH companion. Reuse of the UI kit is encouraged.
- C3rro and the METr team: endorsement recorded 2026-09-17.
