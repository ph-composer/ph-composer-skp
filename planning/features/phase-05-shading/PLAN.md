# Shading: plan

DATE: 2026-11-19
STATUS: Scoped. Authorized 2026-11-19 with every Shading stage ([STATUS](STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Seven stages, each one branch and one reviewed PR through the PR loop. Behavior owner: the
[PRD](PRD.md). Names: [CONTRACTS](CONTRACTS.md). Each stage reads the
[stage brief](../../../.agents/stage-brief.md) and loads the architecture review skill before it
designs anything.

| Stage | Delivers | Needs | Host run | Review |
| --- | --- | --- | --- | --- |
| [P5s-01](phases/p5s-01-contracts-and-host-facts.md) | CONTRACTS section 7 answered; the envelope-exclusion flag named; the Zones call-site list; the mark's survival table | D5s-07, D5s-12 | Yes, SD01 | Stronger pass |
| [P5s-02](phases/p5s-02-shading-mark-and-operations.md) | The store, `assign`, `clear`, `list`, `selection`, codes | P5s-01 | Yes, SD02 | Stronger pass |
| [P5s-03](phases/p5s-03-zones-seam.md) | A Shading Face inside a Zone leaves its envelope; Clear classification if Zones lacks it | P5s-02, D5s-11 | Yes, SD03 | Stronger pass |
| [P5s-04](phases/p5s-04-native-menu.md) | Set as Shading and Clear Shading in both menus | P5s-02 | Yes, SD04 | Ordinary |
| [P5s-05](phases/p5s-05-colour-by.md) | The Shading Colour-by mode and legend | P5s-02 | Yes, SD05 | Ordinary |
| [P5s-06](phases/p5s-06-export.md) | The export section, report, conformance and the PHX round trip | P5s-02, P5s-03 | Yes, SD06 | Stronger pass |
| [P5s-07](phases/p5s-07-acceptance-and-handoff.md) | Docs, agent guide, integrated acceptance, Ed's check in WUFI-Passive and METr | All | Yes, SD07 | Docs pass |

## Order

P5s-01, then P5s-02. P5s-03, P5s-04 and P5s-05 each need only P5s-02 and touch different files
(Zones; the menu declaration; the Colour-by declaration), so they may run in any order or stacked.
P5s-06 needs P5s-03 so a tagged Zone Face is out of the Room before it becomes a Shade. P5s-07 last.

## Shared files

| File | Stages | Note |
| --- | --- | --- |
| `core/records/entity_store.rb` | P5s-01 or P5s-02 | The one foundation addition |
| `features/zones/**` | P5s-03 only | No other stage edits Zones |
| `extension.rb`, `composition.py` | P5s-02, P5s-06 | One line each |
| `context/CONTRACTS.md`, `EXTENSIBILITY.md`, `UBIQUITOUS_LANGUAGE.md`, `SKETCHUP_HOST_BEHAVIOR.md` | Each stage folds its own bindings | |
| Runtime manifest | P5s-06 | Refreshed for the new Python file |

## Risks

| Risk | Where it is settled |
| --- | --- |
| Zones enumerates its Faces in more places than CONTRACTS section 4 lists | P5s-01 lists them from code; P5s-03's tests cover each |
| The mark is lost or duplicated by a native edit in a way that surprises | P5s-01's host table; the PRD's "Copies and edits" is corrected to it |
| Thousands of Shading Faces (a detailed neighbour model) slow export or WUFI-Passive | P5s-06 measures the section at 5,000 Shading Faces; PHX's coplanar merge is the user's mitigation |
| WUFI-Passive or METr mishandles a holed polygon | SD07; if it fails, D5s-14 flips to splitting the Face in the section |
