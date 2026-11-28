# UI and UX refinements

DATE: 2026-10-07
STATUS: Complete; implementation merged through PR #79/#80 and current-host acceptance passed
ISSUE: [#77](https://github.com/bldgtyp/ph-composer/issues/77)

Ed requested incremental refinements on one branch, `codex/ui-ux-refinements`.

All accepted refinement behaviors are implemented and merged. The remaining current-host checks
closed on 2026-10-07; see the [current acceptance receipt](#current-native-acceptance).
Earlier pending statements below retain their historical checkpoint context. SketchUp 2023,
Windows support and release remain separate gates.

## Zones / Faces column headers

Ed accepted mockup A on 2026-10-05: labels on one aligned row, with Colour-by and column-menu
controls in a shallow row beneath. The shared table keeps one semantic column header for each
column, so both visual bands share its existing sticky position and resize handle. A table that
supplies `headerActions` reserves both bands in every column. Other tables keep their compact
header. Icons retain the accepted hover/focus reveal and persistent active states.

The label band is 34 px and the action band is 28 px. Labels align left and elide when the user
narrows a column, with the complete name in a tooltip. Building-Segment, Ground depth and Gross
area get slightly wider defaults. Changes affect panel presentation only.

Verification: 70 focused table/Overview tests pass; JavaScript line coverage is 96.3%
(94% minimum). Header browser checks pass at 1559, 1280, 900, 420 and 280 px, including complete
default labels at normal widths, internal scrolling at narrow widths, keyboard focus, persistent
Colour-by/filter states, sorting, unit changes, narrow-column resizing and sticky vertical scroll.
`make ui-checks` passes all nine browser scripts. The new browser check initially used a Colour-by mode
absent from the synthetic fixture; it now exercises the fixture's Face type mode and passes.
`make ci` passes, including lint, offline suites, fixture/manifest checks and RBZ validation.
One bounded independent review found no actionable issues. No new complexity branch was added
to the feature behavior; the shared table's existing header-action hook selects its presentation.

Current-host visual check passes on SketchUp 26.1.188 / Ruby 3.2.2: the installed panel shows
aligned, complete labels and separate action bands at approximately 1377 px wide. Native clicks
open and close the Level column menu; the Level palette toggles on and off with the header stable.
The two-Zone `test.skp` remains open and modified with no active edit path. Only panel assets were
reloaded; no fresh-process, fixture replacement or Model save was needed for this presentation
change. Narrow widths and keyboard/scroll behavior were checked in the browser, not in the host.
Private screenshots are under `_private/host/ui-ux-refinements/`.
The installed RBZ SHA-256 is `a0bf8cc28709d5ed760abed72d8241a963d14ca6abdaa406b01949869cc58ba6`.

## App-wide styled tooltips

Ed requested styled app tooltips to take priority over native browser hints on 2026-10-05.
The shared icon helper previously set both `title` and `data-tooltip`, reproducing the two hints
shown in his screenshot. Native-only HTML and SVG hints have also moved into the styled layer.

`ui.tooltip(node, text)` sets or clears a hint and removes the native `title` attribute. A single
panel layer handles table, toolbar, drawing and dialog hints. It moves into an open modal's
native top layer, retains existing accessible descriptions and withdraws tips whose owner is
hidden, removed or repainted with different text. Controls retain their accessible names.
No Model operations or transaction boundaries changed.

Focused browser checks pass for table and toolbar hints, resize guidance, planned tabs, modal
controls, layer reuse, keyboard focus and Escape. They also find no native `title` hints across
the primary panes. Independent simplification review found enabled Assembly segment controls
whose normal tooltips were cleared by the migration; this is fixed, with enabled and blocked
states covered by focused tests. No other actionable review findings remain.

Final verification: `make ci` passes, including 1,415 Ruby tests, 458 JavaScript tests, 172 Python
tests, lint, type checks, fixtures, panel/runtime manifests and RBZ validation. JavaScript line
coverage remains 96.3%. All ten `make ui-checks` scripts pass. The header test now waits for the
opacity transition before asserting the active filter's resting state; an earlier check caught
the animation at 0.999586 rather than its completed value of 1.

Current-host focus check passes on SketchUp 26.1.188 / Ruby 3.2.2 after installing the new panel
assets. Native Tab navigation shows a single styled toolbar hint and withdraws it on moving focus
to the filter. The model remains the modified two-Zone `test.skp`, with no active edit path and
Colour-by off. A native-control interruption left a blank panel; closing and reopening the panel
restored it without restarting SketchUp or saving/replacing the Model. Long pointer hover and
modal tooltip layering were checked in the browser, not through native controls. Native captures
are `native-tooltip-toolbar.png` and `native-tooltip-restored.png` under the same private evidence
folder. The installed RBZ SHA-256 is
`677790b3dd68e0393c43d5179cfad5448ada250787be79ebab45c4a15363266b`.

## Chip spacing and read-only alignment

Ed requested more breathing room to the right of chip chevrons and a full-width Surface chip on
2026-10-05. Table, toolbar and Assembly hint selects retain their native select behavior, with a
shared inset chevron and reserved text space. Dark Assembly assignments use a light chevron with
their existing white label. Read-only table chips now fill the available cell width and share the
editable chips' 24 px height; they retain their explanation tooltip and have no chevron.

The synthetic browser check confirms equal editable/read-only width and height, no arrow on
Surface, and a light arrow on a dark Assembly assignment. `make ci` and all ten browser scripts
pass; the focused Assembly chip colour test and lint pass after the contrast adjustment.
JavaScript coverage remains 96.3%. Focused local review confirmed that read-only styling has no
arrow background and the contrast override clears when a dark assignment is removed.

The installed SketchUp 26.1.188 panel shows inset chevrons at approximately 1377 px wide. The
current `test.skp` is unmodified and has no active edit path; its current Faces have no Surface
boundary, so equal read-only chip dimensions were verified with the synthetic browser fixture.
Reloading the open HtmlDialog left it blank; closing it and then opening a fresh panel restored
the content. No Model save, replacement or adjacency operation was performed. Evidence is under
`_private/host/ui-ux-refinements/chips/`. The installed RBZ SHA-256 is
`5a5b7b1064c59311ba64408236aef4d9f9141329dbc47fbddd046e76e998a384`.

The Design System artifact is not re-synced yet: these changes remain on the working branch;
the UI polish skill calls for its published rendering to be refreshed from `main`. Carry that
sync into the branch's merge closeout so the artifact reflects the accepted implementation.

## Read-only chip affordance

Ed observed that the full-width Surface chip still looked editable on 2026-10-05. Read-only enum
chips now retain their category fill and normal label contrast, with a subtle diagonal hatch and
decorative lock in place of an editable chip's chevron. Their explanatory tooltip starts with
"Read only."; validation issues retain priority. Chip width, row height and stored values are
unchanged. This is a shared table treatment, also used for other enum values set elsewhere.

The synthetic browser check confirms the Surface label, hatch and explicit explanation. All 52
focused Overview tests pass. All ten browser scripts pass, with JavaScript coverage at 96.3%.
The installed SketchUp 26.1.188 panel shows both Surface chips with the hatch and lock at
approximately 1377 px wide. The modified `test.skp` remains open with no active edit path; only
the panel was closed and reopened to load its new assets. No Model operation was performed.
Private visual evidence is `chips/native-locked-chips.png`. The installed RBZ SHA-256 is
`e538645eb79e8db7d6bb67a3f0d5a5aa97a4aab06d8c03ddb58cf4b7a8cfdeac`.
`make ci` passes. Focused local review found no behavior or layout changes beyond
the intended read-only presentation and tooltip wording.

## Make Zone entry point

Ed requested removal of Make Zone and its unavailable-reason icon from the Zones / Faces header
on 2026-10-05. Both controls and their header-only state are removed. The empty-table guidance
now directs users to select geometry in SketchUp and use the right-click Make Zone command.
The native command, public action and selection-target query remain unchanged. A new SketchUp
toolbar is a future option, outside this change.

All 51 focused Overview tests pass, including absence of both controls with and without a valid
Make Zone target. All ten browser scripts pass; JavaScript coverage remains 96.3%. The installed
SketchUp 26.1.188 panel shows the remaining toolbar and settings aligned at the upper right,
with neither removed control present. Native Make Zone implementation is unchanged. The modified
`test.skp` remains open, with no active edit path; no Model operation was performed. Evidence is
`remove-zone/native-header.png` in the private evidence folder. The installed RBZ SHA-256 is
`26d08fe17d70433362466f645bd1118c97660edd46c3ee4ca046f9f1097f1c12`.
`make ci` passes. Focused local review confirms that no header-only Make Zone
handler or target state remains, and that the native command/public contract is unchanged.

## Solve for checked Zones

Ed accepted moving Solve adjacencies from the permanent header into the selection bar on
2026-10-05. A Zone qualifies when every Face under its occurrence is checked; a mixed or empty
Zone does not qualify. The bar reports the qualifying Zone count and offers "Solve adjacencies
for checked Zones", disabled until two Zones qualify. Fully checked Zones hidden by a filter
remain in scope. Checking all unfiltered rows provides the whole-Model workflow without a
separate button. The later column-paint slice keeps Solve available during painting.

Solve submits those occurrence references through the existing action and revision guard, with
single-flight protection. The Ruby solver and native command are unchanged. Its existing
`scope.incomplete` refusal names a neighbour that would otherwise need a reciprocal write;
checks remain intact so the user can include it and retry. No implicit neighbour inclusion occurs.
At narrow widths, the shared selection bar puts the count and clear control above the wrapped
controls so each control remains within the bar.

All 54 focused Overview tests pass: partial/complete eligibility, explicit subset payloads,
hidden checked scope, check-all, busy protection, refusal, Classify transitions and Model switch.
Dedicated browser checks pass at 1280, 900, 420 and 280 px, including bounds of every selection
control and a filtered subset dispatch. Independent review found no actionable scope defect.
The existing header browser check caught the Zone-list input also used by column filters; its
assignment is restored before filter painting. `make ci` and all eleven browser scripts pass.
JavaScript line coverage is 96.3% of 10,598 lines across 76 files (94% minimum).

The installed SketchUp 26.1.188 panel was observed with both Zones fully checked: the bar reported
two checked Zones and enabled the new action, with its styled scope tooltip. A subsequent native
view with no checked Faces showed no selection bar and no permanent header Solve action. The
final panel screenshot is `selected-solve/native-final-panel.png` under the private evidence
folder. Partial-Zone disablement is verified by focused and browser checks; its additional native
check was not completed because the window binding changed during interaction. No Solve Model
operation was performed. Native Solve mutation and Undo/Redo have not been rerun for this UI
entry-point change. The current modified `test.skp` was not saved or replaced.
The installed RBZ SHA-256 is
`38db4e4b34e18b774be3fdce755d84ff3c6502d44325ab2a56178e24b75b6ddc`.


## Colour-by filtering in column menus

Ed accepted removal of the panel legend strip on 2026-10-05. Its Locate and eye controls are
removed from the UI; their public view commands remain compatible. The active Colour-by column's
Show choices now disclose its colour swatches. All column Show filters combine to control both
the table and the Colour-by overlay: matching occurrence geometry keeps its colours, excluded
geometry takes the existing grey wash. Clearing a column restores its values. Text search and
row collapse remain table navigation, independent of the viewport mask. Actual SketchUp visibility,
materials, selection and saved Scenes are not changed.

The shared Colour-by service accepts a generic occurrence mask through the public
`ph_composer.colour_by.filter` command, independent of any feature or colour mode. Null means all;
an empty array means mute all. The mask survives off/on and mode switches. Zone-only filters submit Zone roots so all their geometry, including Window units, stays coloured.
Face filters submit matching Face paths; detached Window units have no matching Face identity and
are muted in that scope. Group and Component
projections partition geometry at each Face so partial-Zone filters work in Zone modes too.
Legacy projections with no occurrence path are muted under an explicit mask. Filtering supersedes
legacy row isolation so a removed UI reset does not strand the viewport in an isolated state.
Panel requests coalesce rapid edits, with a separate channel from mode switching. A refused scope
reports a warning without replaying on every repaint. Clear filter updates immediately while its
menu stays open, preserving focus.

All 61 focused JavaScript checks pass. The full test run passes with 1,424 Ruby tests / 14,272
assertions, 460 JavaScript tests and 172 Python tests. Ruby 2.7 focused and adjacent checks pass
(76 tests / 683 assertions). All twelve browser scripts pass, including menu bounds at
1280, 420 and 280 px, active swatches, combined filters, explicit empty scope, reset, and stable
scope through text search/collapse. JavaScript line coverage is 96.2% of 10,597 lines in 76 files.

Independent review found and verified two corrections: Zone-only masks use Zone roots so Window
units remain coloured, and a menu omits a single swatch when a value has several state colours.
No actionable findings remain in the accepted Face-filter scope. The offline gate's syntax, lint
and test targets passed; its generated-fixture check required the regenerated API reference to
be committed. That document was recorded with DCO sign-off on the same branch (`6266ccd`).
The remaining gate targets then passed: fixtures, both manifests/pins, hostkit, Python checks,
RBZ construction and verification. No checks were weakened or skipped.

The built extension is installed. Its RBZ SHA-256 is
`9f5f4322d4b6051ea7be39407579b734df651ebc94eaf7ce4fbeca7aa6571bac`.
The last host read showed modified `test.skp`, with no active edit path; it was not saved,
replaced or restarted. The running host retains its previous Ruby code. Restart SketchUp before
using the new panel's viewport filtering. Actual native overlay wash/outline, combined filters,
mode/off retention and nested/shared-instance observations remain pending that restart. No
Model operation was performed; native no-Undo verification is also pending. SketchUp 2023 floor
proof remains open. The Design System artifact remains pending merge to main as recorded above.


## Assembly None hatch and native selection edges

Ed reported that Assembly Colour-by's None hatch covers native blue Zone selection edges on
2026-10-05. Direct source evidence identifies the cached unclassified solid-outline pass: it is
drawn at two pixels over native boundaries. Assembly entries now opt out of that pass through
`hatch_outline: false`; the unclassified hatch remains at one pixel. The option applies only to
unclassified rendering. Assigned Assembly colour fills, incomplete assignments and other modes'
default hatch/boundary treatment remain unchanged. Core rendering names no Assembly-specific mode.

All 65 focused Colour-by and Assembly refresh tests pass (566 assertions), including Ruby 2.7.2.
The regression asserts hatch-only drawing with no solid boundary, unchanged no-fill None semantics,
retained other-mode boundaries and coloured fills, and no Model write. Focused local review
confirmed that the optional entry flag defaults to the existing treatment and is read only by the
unclassified branch. `make ci` passes: 1,425 Ruby tests / 14,287 assertions, 460 JavaScript tests,
and all remaining offline gate targets. Prior browser and JavaScript coverage checks are reused
because this slice changes no panel assets. The built extension is installed, with RBZ SHA-256
`a4f866dbb146ebe62736e8b2929b8c837159cd6a99786a1c95fe1c4cff3b248e`.
The running SketchUp host has a modified `test.skp`, with no active edit path. It was not saved
or restarted; native blue-edge confirmation requires a restart to load the new Ruby. The prior
column-filter native acceptance remains open.


## Building Segment and Level option management

Ed requested select chips backed by user-managed names and colours on 2026-10-05. This exceeds a
presentation edit: current strings drive Zone stamps/recovery, Colour-by grouping and Python's
Building Segment export identity. The request is scoped in the separate
[managed Zone options packet](zone-field-options/README.md). Respective
column-menu Manage actions open one reused dialog. Ed accepted D2–D10 and implementation on
2026-10-05; managed identities, explicit adoption, select chips, custom colours and stable export
identities are implemented and current-host verified, merged through PR #80. This intake
remains the request record; the archived packet holds implementation and acceptance.


## Column-scoped Face painting

Ed approved moving paint into the Type, Boundary and Assembly headers, then refined the design on
2026-10-05: use the existing value list rather than a Paint faces… item and another picker. Each
value has a visibility checkbox/name and a separate sibling paint icon. Painting closes the menu
and submits the existing choose command with `reset: true`, so retained hidden fields cannot enter
the next gesture. All declared enum choices and local Assemblies appear even when unused. Current
values outside that declared set remain filterable but do not gain an invalid paint action.

Surface is solver-owned; Assembly None is filterable and has no paint icon because null means Keep,
not erase. Attached zone is a reference choice, so the Boundary menu contains an inline select and
New attached zone route. Creation keeps the existing guarded modal; Cancel reopens the menu and
focuses New, while create-and-choose returns to the active Boundary glyph after acknowledgement.

Only active paint intents have a persistent pressed header paint icon, with the value in its tooltip.
Clicking it stops the entire tool. External multifield palettes show each active field. Native cursor,
status guidance, gesture intent/revision freezing, Undo and the public/native entry points remain
unchanged. The selection bar retains normal checked-Face assignment and checked-Zone Solve.
Escape unwinds menu/dialog, then the native tool, checked selection and Locate. Model switching
disposes old requests and controls; Attached zone Save/Cancel guards survive.

Shared column menus now accept value-action descriptors and optional additional controls, without
naming a feature or field. The duplicate paint picker and its styles were removed. Labels can wrap
while visibility and paint remain independent accessible targets.

This refinement uses focused frontend tests, one bounded independent review, browser checks at
1280/900/420/280 px, runtime refresh and the full offline gate. Verification complete for this UI refinement: 104 focused JavaScript checks pass, and JavaScript
line coverage is 96.3% against the 94% minimum. `make ci` passes with 1,425 Ruby tests / 14,287
assertions, 459 JavaScript tests, 172 Python tests, hostkit, manifests, pins, type checks and packaging.
All 13 browser scripts pass at representative widths including 1280/900/420/280 px. The longer menu
revealed a confirmed overlap with the selection bar: fixed by elevating the owning sticky header
while its bubble is open. Pointer checks reproduce and verify the fix; a shared test covers parent,
child and final-close stacking state. The bounded review and targeted follow-up found no remaining
issues. Scoped lint and final diff checks pass.

Installed RBZ SHA-256: `70673c70ba56d529ea32e34753b43b550e21ad1178eebc13950fdd904dfbaee4`.
Native UI check uses SketchUp 26.1.188 / Ruby 3.2.2 and existing modified `test.skp` at edit depth 0.
Native controls opened Type, Boundary and Assembly menus; screenshots confirm direct value icons,
Surface/None exceptions and inline Attached zone controls. Clicking Wall's icon activated the native
tool with only face_type=Wall; the menu closed, the header glyph appeared, and Escape stopped it.
No Faces were painted, no model saved/replaced and no restart performed. Final readback shows the
same modified Model at depth 0 and the tool idle. Evidence is ignored under
`_private/host/ui-ux-refinements/column-paint-inline/native/` and `.../browser/`.
Fresh-host paint gesture/Undo and native narrow-layout acceptance remain separate. The Design
System artifact sync remains pending merge to main as recorded above.


### Matching Colour-by when painting

Ed approved automatically selecting the matching Colour-by view when entering paint mode.
The native Classify choose path owns this behavior, so direct table icons, inline Attached zone,
Assemblies-screen paint and native/public paint choices agree. Face type selects Face type,
Boundary and Attached zone select Boundary condition, and Assembly selects Assembly. This choice
is remembered and survives Stop/Escape; a later manual Colour-by override is preserved. Bare native
tool activation without a concrete choice retains the existing temporary fallback behavior.

Note, 2026-11-27: "survives Stop/Escape" no longer holds. Since #286 (2026-10-21) a paint tool leases its
Colour-by mode and gives back the mode from before painting when it stops, unless the user picked another
meanwhile (`context/EXTENSIBILITY.md`, "Give the Colour-by mode back"). The `UXR-COLOUR` case text follows the
lease, by Phase 7 decision D4-38.
No new command/schema or record mutation is introduced. The feature-owned ColourModes helper
keeps the shared Colour-by service free of field knowledge and keeps ClassifyTool within its existing
300-line complexity limit. Focused Ruby tests pass 50 cases / 302 assertions on Ruby 3.2.2 and 2.7.2;
one bounded lifecycle review found no blocker. `make ci` passes: 1,428 Ruby cases / 14,320
assertions, 459 JavaScript cases, 172 Python cases and the remaining lint/hostkit/type/package gates.
The affected paint browser check passes at 1280/900/420/280 px, with matching modes for Type,
Boundary, Attached zone and Assembly and persistence after Stop. No HtmlDialog shipping asset changed.

Installed RBZ SHA-256: `69e838df9fbb6670e7c853100eca62aa9f2a9f1c382d8dae9facacd7d3e0eb36`.
Current SketchUp 26.1.188 / Ruby 3.2.2 already had Assembly painting active, with no pointer gesture
in progress and Face type Colour-by still active. Loaded the two updated feature files in place,
then reselected the exact same Assembly through the public choose view command. Outcome completed
with effect none; the active tool and its single Assembly intent stayed unchanged, Colour-by
switched to Assembly, and the Model revision stayed 9 with its modified flag true. Native panel
indicators show Assembly paint and Assembly Colour-by pressed. This exercises same-tool native
reselection without modifying Faces or restarting/saving the Model. Evidence lives under ignored
`_private/host/ui-ux-refinements/paint-colour/native/`; affected browser evidence is in its parent.
User's active paint workflow was preserved, so native Type-to-Boundary-to-Stop and gesture/Undo
checks were not performed here. Focused Ruby/browser checks prove those state expectations offline;
this live reload does not claim fresh-process acceptance.


## PR handoff

All accepted implementation slices remain together on `codex/ui-ux-refinements`, with DCO-signed
commits. Final offline gate passes 1,428 Ruby cases / 14,320 assertions, 459 JavaScript cases and
172 Python cases plus the remaining CI targets. All 13 browser scripts pass against the final
preview host, including automatic matching Colour-by; ignored evidence is under
`_private/host/ui-ux-refinements/pr-final/`.

Issue #77 tracks these refinements. The PR was opened as a draft with the remaining native viewport-mask,
Assembly hatch-edge and gesture/Undo gates recorded above. The owner later approved merging while
those checks remain deferred; that approval is not native acceptance or release approval.
At this draft handoff, the managed Segment/Level packet in issue #78 was still planning-only,
and Design System sync was a merge-closeout follow-up. Both subsequently completed, as recorded
in the merge handoff and sync receipt below.


### Remote CI follow-up

The first PR #79 matrix run failed on Ruby 3.2.2 and 2.7.2: a comment added after the local lint
pass was 121 characters against the 120-character limit. Wrapped that comment without changing
runtime behavior. Full Ruby lint then passed on both local runtimes (440 files each), and the final
diff check passed. The corrective push reruns the full remote matrix; its result is tracked on PR #79.


## Merge handoff

Ed authorized merge after both GitHub CI matrix jobs passed on `f0db4ea`. PR #79 merged into main
on 2026-10-05 as `3417e918b3bd7773e4ab44d68c6ddf6905f54b1c`, with DCO sign-off preserved.
At merge, the native viewport-mask, hatch-edge and gesture/Undo follow-ups remained unverified;
merge approval did not close them. They subsequently passed in the current receipt below.
Managed Building-Segment/Level options subsequently merged in
[PR #80](https://github.com/bldgtyp/ph-composer/pull/80); their accepted packet is
[archived](zone-field-options/STATUS.md). Local main is synchronized. On 2026-10-05,
the merged UI-refinement feature branch was removed locally after verifying its tip was an ancestor
of origin/main; the remote branch was already deleted. At that checkpoint, both branch inventories
contained only main.
Design System artifact sync is closed by the receipt below.

## Design System sync receipt

On 2026-10-05 the existing private
[PH-Composer Design System](https://claude.ai/artifact/77GLrkZxtkxo9TksTbvodL) was updated in place
as version 8 from `main@4f516212ac7eef973f61cb8efe819c874a89867f`. Its identity and private access
were retained. The repository stylesheets remain authoritative.

- Rebuilt `components/bundle.css` from `base.css`, `overlay.css`, `shell.css`, `table.css`,
  `library/library.css` and `features/zones/zones.css`. Independent comparison of the published
  file against all six repository sources passed, ignoring only whitespace at section edges.
- Reconciled colour, type, spacing, radius and shadow references, distinguishing actual CSS
  variables from descriptive aliases. Workspace type is 13px; standalone body type is 14px.
- Refreshed the ten existing static parts and added SelectionBar, ColumnMenu, ChoiceChip,
  Tooltip and ManagedOptionsDialog. The table now depicts synthetic Zone/Face rows with managed
  Segment/Level chips, two header bands and checked-row states; the inspector example is generic.
- Corrected the source-specific chevron guidance: Segment/Level colours change label contrast
  but retain the default chevron; dark Assembly chips use a light label and light chevron.
  Tooltip markup follows the shared kit's `row-tooltip`, role and description association.
- Repaired the gallery's missing `components/bundle.js` contract with a six-line static adapter.
  It imports no kit scripts and dispatches no host actions. The artifact authoring check rendered
  all fifteen cards through the gallery runtime; independent published-page inspection confirmed
  the missing-bundle warning is gone and the choice-chip, column-menu, table, selection-bar,
  managed-option dialog and tooltip previews render.

The source extract, manifest, published CSS comparison and browser capture are ignored under
`_private/design-system-sync-20261005/`. The extract's SHA-256 is
`24207ffb84e42480f87263990072dbf187b7a00e0a8295e9d7b5de8af3dcacb9`.
These are static reading aids; live kit behavior, host actions and Undo do not execute in them.
Builder drawing styles remain excluded. No shipping source changed, so the closeout uses a
focused documentation consistency check rather than repeating the unchanged offline or host gates.
At this sync checkpoint, PR #79's native follow-ups remained open. They subsequently passed below.

## Current native acceptance

On 2026-10-07 all six bounded native refinement cases passed on SketchUp 26.1.188 / Ruby 3.2.2:
checked-Zone Solve eligibility and exact Undo/Redo; column-mask wash, combined empty scope,
mode/off retention, clearing and no Undo entry; Assembly None hatch with visible native blue
selection edges; actual Type/Boundary/Assembly paint gestures and exact Undo/Redo; matching
Colour-by and retained manual override; and distinct nested/shared occurrence masks without
Model writes. Native 420 px and minimum 360 px panels kept selection controls and column menus
within the window. The [assertion evidence](../native-acceptance/evidence/ui-ux-refinements-2026-10-07.md)
records provenance, native versus setup controls, and the wheel-scroll limitation.

The installed RBZ matched all 387 packaged files, with no extras or mismatches, before and after:
`97d30a432c31ac7132d853e52fe94bade8f8cbddb130ccbc86aac49c5be95f2c`.
Two immutable pre-action baselines and hashed observation receipts remain under ignored
`_private/host/ui-ux-acceptance-20261007/`. Normal panel restoration passed with fixture helpers
removed, exact record readback, paint idle, Colour-by off, mask null and the clean synthetic Model
at edit depth 0. The panel is left open.

No shipping code changed. `make rbz-check`, installed-package comparison and deterministic evidence
comparisons passed; earlier passing offline/browser/review gates remain applicable. The refinement's
implementation, merge, Design System sync and current-host acceptance are complete. This does not
establish SketchUp 2023 native proof, Windows support, public distribution or release acceptance.
