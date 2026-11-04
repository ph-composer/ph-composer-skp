# UI design polish and visual audit

DATE: 2026-11-04
STATUS: Implemented and locally verified; council accepted; unmerged
ISSUE: [#338](https://github.com/ph-composer/ph-composer-skp/issues/338)
BRANCH: `codex/ui-design-polish`
BASE: `5371cca2`

## Authorized scope

Improve every shipping tab, subtab, builder and key floating container, including sparse and dense
synthetic content. Review typography, borders, radius, icons, hierarchy, consistency, colors,
backgrounds, buttons, placement and nesting. Simplify shared components and styles. Preserve
commands, drafts, focus, Escape, native operations and data contracts. The owner requests scores
strictly above 9/10 from every council member for every category and tab.

The starting branch already contains extensive visual work. This packet records the additional
work from the base above; it does not assign scores to earlier commits or replace their evidence.

## Implementation

- Shared font and ink tokens remove a separate text treatment in the workspace, bubbles and forms.
- A dialog padding token controls its body inset, close button and sticky footer together. Agent
  Access's compact form uses the same rule with a smaller inset.
- Dialog footers wrap their actions and give status text a readable width. In narrow windows the
  message occupies its own line, keeping Cancel and the commit together. A browser run reproduced
  Export library clipping Cancel and hiding its refusal at 280 px before this correction.
- Inventory Duplicate/Delete controls reveal on row hover or keyboard focus on hover-capable
  devices. Open, assignment actions and usage indicators remain visible. The controls retain their
  positions and keyboard order; devices without hover retain visible actions.
- Narrow navigation reserves the units switch only on its final row, recovering 32 px at the
  360 px minimum. All six shipping tabs remain visible.
- Clamped action menus scroll their choices rather than allowing the final actions to escape
  below the window. The minimum-size Building Segment management route has a reachability check.
- Agent Access page-width rules no longer override Revoke and Token Created modal viewport limits.
- The staged Installs editor uses a shared sticky heading so Save and Cancel remain available
  while selecting products below the drawing. The draft and commit operations are unchanged.
- Shared narrow view controls place filtering, grouping and counts together, with ordering and
  grid tools beneath them. The compact footer retains version, edit context and Help on one row.
- The Assembly toolbar reserves the height its controls actually use. Short, narrow windows
  show thickness and U-value with films first; the existing information bubble retains the
  construction-only U-value. Window Types keeps its semantic page title while the selected record
  supplies the visible title in a short builder view.
- Narrow Zones views initially show the first identity column after Actions and Hierarchy. Each
  view preserves subsequent horizontal pans and does not reorder or remove columns.
- Thermal Bridges retains its always-present selection-first bar. Its native painting tool uses
  the shared paint-bucket glyph, with a visible label at wide sizes and the same accessible name
  and tooltip at narrow sizes.
- Dense Export advisory lists use a counted disclosure after five distinct advisory causes.
  Blockers remain visible. Expansion persists within a Model and resets on a Model change.
- Assembly deletion confirmations consume Escape before the underlying drawing selection. Layer
  deletion uses the shared danger treatment. Invalid inline dimensions use a clamped validation
  bubble that retains input focus and position; thin layers no longer clip the explanation.
- Minimum-size Window Types places identity beside performance metrics, recovering drawing space
  without reducing tool hit targets. Shared subtabs show an overflow cue when additional labels
  extend beyond the panel; pointer and keyboard selection, resize and remembered selection bring the chosen label into view.
  Narrow Window drawing tools use light functional groups; Undo/Redo help remains in More.
- Export shows active progress before readiness details. A terminal task owns its historical
  message, counts, destination, report and findings. Cancelling a subsequent destination picker
  or refusing a new request retains that history and shows the new request separately.
- Library comparison choices show their declared labels, with readable disambiguation for
  duplicate labels. Record IDs remain the selection/write values. Datasheet comparisons show complete wrapped link
  destinations, including equal-count replacements.
- The mocked host-launch test now isolates the SketchUp support folder. Its earlier fixture
  removed the real bridge state file during offline checks, interrupting native verification.
- The development visual atlas reuses the shared browser collector and pane-fit helpers. It captures
  the real panel with synthetic data and separate-window synthetic responses, and writes a manifest
  of scenarios, dimensions, dialog bounds and coverage limitations. The preview's development-only
  Example parts and Areas are hidden explicitly and recorded in the manifest.

The accepted always-present Thermal Bridges assignment bar is retained. Hiding it solely to improve
an empty-state score would change the accepted interaction pattern without demonstrated benefit.

## Acceptance and current evidence

Raw screenshots, logs and synthetic host files stay under gitignored `_private/ui-design-polish/`
and `_private/host/ui-design-polish/`.

| Check | Current state |
| --- | --- |
| All six main tabs, fourteen shipping tab/subtab routes | Final 296-capture atlas passed, matching frozen source below |
| Sparse, dense and empty fixtures | Wide atlas; representative narrow and minimum-size captures |
| Builders, record forms, library surfaces and separate windows | Final atlas passed; no captured dialogs outside their viewport |
| Inventory keyboard reveal, Enter, Escape and focus return | Focused browser check passed |
| Narrow controls, initial identity visibility, preserved table pan, dense Export disclosures | Focused browser and panel unit checks passed |
| Windows and library export at 1280, 900, 420 and 280 px | Focused browser check passed after footer correction and sticky Installs actions |
| Full offline gate | Final `make ci` passed (`final-ci.log`), including lint, type checks, tests, manifests and RBZ verification |
| Full browser suite | Final full browser suite passed (`round4-browser.log`), including post-fix pointer, keyboard, resize and remembered-selection checks |
| SketchUp 2026 | Native walkthrough passed on copied synthetic Model; Fresh final installed build verified: 38 Materials, one Assembly, two Zones, twelve Faces, one Space, one Window Type with products and three Thermal Bridge Types. Native navigation, tool grouping, menus, validation and Export readiness inspected |
| SketchUp 2023 / Windows | Not exercised; no platform claim |
| Council | Owner approved three available-model reviewers: GPT-6.1 Sol, GPT-6.1 Terra and GPT-6 Astra. Four rounds complete; every reviewer scores every requested design category/tab/container above 9, no actionable findings |
| Design System reading aid | Not synchronized: branch is unmerged, and the skill requires a sync from main. Pending after acceptance/merge |

The native run used SketchUp 26.1.188 / Ruby 3.2.2, copied `blank-template.skp` to a disposable run
Model, and authored synthetic data through the existing public-API walkthrough. A save/restart
preserved that data. Native pixels were inspected through computer use; browser images do not
substitute for native viewport, file picker, Undo/Redo or platform acceptance.

## Council review

The named Claude models could not be reached in this harness. The owner explicitly approved three
independent available-model reviewers. Each reviewed screenshots and the coherent source diff
read-only. Scores are subjective visual judgments, with native and automated gates tracked separately.

| Reviewer | Round 1 design / code | Round 2 design / code | Round 3 design / code | Round 4 design / code |
| --- | --- | --- | --- | --- |
| GPT-6.1 Sol | 8.9 / 9.0 | 9.1 / 9.3 | 9.0 / 9.2 | 9.2 / 9.3 |
| GPT-6.1 Terra | 8.2 / 9.0 | 9.0 / 9.1 | 8.8 / 9.0 | 9.1 / 9.1 |
| GPT-6 Astra | 7.8 / 8.6 | 8.8 / 9.0 | 8.8 / 9.2 | 9.1 / 9.3 |

Round 1 corrected thin-layer validation clipping, opaque equal-count link replacements, destructive
Spaces actions, missing popup captures, initial Window Schedule identity, Agent Access alignment,
and Export progress/history labels. Round 2 identified the retained-success/new-cancellation sequence;
new unit and browser evidence exercises both cancellation and refusal after success. Further narrow
layout corrections address the Thermal Bridges work area, Window Types tools and Library overflow.
Round 3 found the new cue overlapped a pointer-selected final Library subtab. Shared reveal now runs
for every successful selection and resize, with the cue mounted before measuring its scroll range.
Focused checks include pointer selection at both narrow widths, active-tab resize and remembered
selection after switching Models and rebuilding the page.

## Final acceptance receipt

The final gallery is `_private/ui-design-polish/round4-final-atlas/index.html`; its manifest records
296 fresh captures across all 14 shipping routes: 42 rich, 30 dense, 14 empty, 81 detail, 69 key popup,
33 separate-window and 27 synthetic Export states. Every capture matches all 114 shipped presentation
files at SHA-256 `b69e8d79b1f2774ebbd4992a91328b1625826a59b5aff31786d746473c12ce1f`.
The fixture hash is `8481c71a84ad2f42960dd848785d64d7a13885625b09dae723bad331ce23c27e`.
The collector reports no undeclared browser errors, sideways panel panes or clipped captured dialogs.

The three independent reviewers accepted the final source and screenshots with no remaining
findings. Each applied the following category scores across all six main tabs and fourteen routes,
including narrow states, record/setup/destructive dialogs, bubbles, menus, dimension validation,
selection shelves, library rails, Installs, Agent Access, Help & Diagnostics and Export containers.
There are no category/tab exceptions in their final matrices.

| Category | GPT-6.1 Sol | GPT-6.1 Terra | GPT-6 Astra |
| --- | --- | --- | --- |
| Typography | 9.4 | 9.2 | 9.2 |
| Borders | 9.4 | 9.3 | 9.3 |
| Radius | 9.5 | 9.3 | 9.4 |
| Icons | 9.3 | 9.1 | 9.1 |
| Hierarchy | 9.3 | 9.1 | 9.2 |
| Consistency | 9.3 | 9.2 | 9.2 |
| Colors | 9.4 | 9.1 | 9.3 |
| Backgrounds | 9.5 | 9.2 | 9.3 |
| Buttons | 9.3 | 9.1 | 9.2 |
| Placement | 9.2 | 9.1 | 9.2 |
| Nesting | 9.2 | 9.1 | 9.2 |

In round four, Sol and Astra compared all 296 captures: 74 changed frames inspected, 222
pixel-identical frames carried forward from prior reviews. Terra inspected narrow routes/details,
key popups, Export and dense desktop contact sheets and reused unchanged prior coverage. They did
not rerun tests or operate SketchUp. Their scores assess synthetic browser captures and reviewed
source, not release or platform acceptance.

Final full browser suite: `round4-browser.log`, exit 0. Final focused pointer/keyboard/resize/session
regression: `round4-pointer-subtabs-accepted/`, exit 0. Final offline `make ci` passed (`final-ci.log`). The implementation is recorded in a signed-off
local commit on the named branch. No shipped source changed after the accepted screenshot fingerprint.

Final native package comparison: `round4-native-package.json`, matching with no extra or mismatched
files; RBZ SHA-256 `d756eb99a6c3e50e9e77bb52d8a729d599634a3c575343ee037fb85dfc867795`.
Fresh SketchUp process and observations are recorded in `round4-native-launch.json` and
`round4-native-observations.json`. The disposable Model remains saved and unmodified, at root edit
path. Native screenshots were inspected inline through computer use. The native dialog's outer
360 x 520 dimensions include platform chrome; the browser viewport captures measure page content.

The final native run checked pointer selection of the final Library subtab, Home/End navigation,
Window tool groups and More menu, populated Thermal Bridges and Export's grouped blocker and
collapsed advisories. Earlier native checks covered Material dialogs, Assembly removal cancellation,
initial Zones identity and complete dimension validation. The public-API synthetic authoring
walkthroughs passed for Assemblies, Zones, Spaces, Windows and Thermal Bridge Types.

## Remaining boundaries

The branch is local and unmerged. No release, SketchUp 2023/Chromium 88 or Windows claim is made.
Native destination picker, actual export execution and viewport-tool acceptance were outside this
visual batch. Browser Export states use synthetic responses. The private Design System reading aid
remains pending until an authorized merge, because its skill requires synchronization from main.
