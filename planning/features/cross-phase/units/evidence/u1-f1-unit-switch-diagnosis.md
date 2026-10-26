# U1-F1: why a unit switch repaints slowly

DATE: 2026-10-21
STATUS: Diagnosed. Ed authorized F1 and F2 on 2026-10-21 with a target of under 200 ms with every row open;
both merged to main through PR #289 (see "Implementation" below). F3 and F4 are not
authorized.
ISSUE: [#154](https://github.com/ph-composer/ph-composer-skp/issues/154)

## Outcome

The cost is not number formatting. One unit switch renders the whole panel eight times, and seven of those
renders change nothing. A scratch prototype that renders once brought the median from 417 ms to 83 ms with
the Zones open, and from 835 ms to 172 ms with every row open. That is under the issue's example target of
200 ms with every row open.

Ed decides two things: whether to authorize the fix (F1 and F2 below, with F3 optional), and the target to
record as the units repaint budget. The proposal is under 200 ms with every row open in desktop Chrome, to be
re-measured in the HtmlDialog at the S07 host gate.

## Method

- Fixture `spaceslarge` in the UI preview (300 Spaces, 150 per Zone, one Volume and one Floor Segment each),
  `main` at `3cc97bb4`, Google Chrome 155 headless through Playwright 1.63, Apple M1 Max.
- The same switch `tools/ui-preview/spaces_checks.cjs` times: press SI or IP, wait for the Supply header to
  change, then two animation frames. Two warm-up switches, then five measured, per state.
- Chrome DevTools Protocol `Performance.getMetrics` deltas per switch (script, style, layout, and the counts
  of style recalculations and layouts), and a CPU profile at 50 µs sampling of the third switch. The
  profiler slows that run, so medians are reported.
- Prototypes were measured in a scratch worktree and discarded. The diff is at the end of this file.

The baseline matches the re-measurement in the issue's comment (408 ms and 786 ms) within run-to-run noise;
the issue body's first figures (393 ms and 748 ms) stopped the timer earlier. The fixture shows 302 rows with
the Zones open and 902 with every row open (2 Zones, 300 Spaces, 300 Volumes, 300 Floor Segments), not the
"about 1,200 rows" the issue and the units ledger give.

## Where the time goes

Medians in ms. "Recalcs" is the number of style recalculations in one switch.

| Variant | Zones open (302 rows) | Every row open (902 rows) | Recalcs |
| --- | --- | --- | --- |
| Baseline, `main` | 417 (script 204, style 143, layout 49) | 835 (script 421, style 278, layout 101) | 113 |
| B: one render while the preference applies | 126 | 269 | 35 |
| C: B, and no render on the host's confirmation | 83 | 172 | 22 |
| D: C, and the CSS minimum column width read once | 78 | 154 | 9 |

Style and layout fall with script: most of the script time is forced style and layout recalculation that a
redundant render triggers, not JavaScript work.

## The eight renders

A press calls `setPreference` (`src/ph_composer/html/panel.js:506`), which runs:

1. `preferences.set`, whose listeners each repaint the panel. Every record `Inventory` subscribes to the
   preference store with its owner's `changed` callback (`src/ph_composer/html/inventory.js:79`), and each
   owner's `changed` is a full `panel.repaint()`. Six inventories exist once the panel is built, so six full
   renders, in this order:
   - Materials (`src/ph_composer/html/features/assemblies/materials.js:64`). This first render is the one that
     changes text: 70 ms with the Zones open.
   - Attached zones (`src/ph_composer/html/features/zones/attached_zones.js:86`), 50 ms.
   - Frames, Glazings and Psi-Install Types, one Windows library surface each
     (`src/ph_composer/html/features/windows/section.js:11` passes `panel.repaint` itself), 153 ms for the three.
     They share one call stack, so the CPU profile shows them as a single node.
   - Assemblies (`src/ph_composer/html/features/assemblies/section.js:33`), 50 ms.
2. Its own `render()`, 50 ms.
3. `send("preferences.set")`. The host answers `preferences.result` with the stored preferences
   (`src/ph_composer/shell/panel.rb:401` to `:408`), and `receive` (`src/ph_composer/html/panel.js:169`) renders on
   every message it has a handler for, 50 ms. The profile is unchanged by then, so this render changes nothing
   either.

The count agrees with the style recalculations: 113 in a baseline switch is 22 for the one render that changes
text plus 13 for each of the seven that do not, and B, which leaves two renders, measures 35. With every row
open each redundant render costs about 95 ms. The count grows with every screen that builds an inventory, so the
cost is not specific to Spaces: every unit system or dimension format change pays it, on every tab. (A table
view choice does not: `set` stores it without notifying listeners, `unit_preferences.js:99`, so the preference
flow renders twice, `setPreference`'s render and the confirmation's. Its caller adds a third: the Zones table's
view switch calls `panel.repaint()` after `setPreference`, `features/zones/overview.js:260`.)

A profile change that arrives in a host snapshot takes the same path: `preferences.replace` runs inside the
reducer (`panel.js:73`), its listeners render six times on the state before the snapshot, and `receive` renders
once more.

In the preview the stand-in host answers synchronously, so render 3 falls inside the measurement. In SketchUp
the answer is a separate message, so render 3 runs as its own task just after the switch: it may not delay the
first painted frame, but it still blocks the panel for 50 to 100 ms.

## Costs inside one render

What remains after C, with every row open (172 ms):

- The Zones table repaint itself: about 50 ms of script, mostly the Spaces cells and their record-edit inputs.
- `minimumColumnWidth` (`src/ph_composer/html/table.js:47`) calls `getComputedStyle` for each column while
  `paintHeaders` writes widths, so every column forces a style recalculation. Reading the CSS minimum once per
  header (D) removed 13 of the 22 recalculations and 18 ms.
- The library sidebars (Materials and the three Windows surfaces) re-render although their tabs are hidden.
  Each reads `this.list.scrollTop` (`src/ph_composer/html/library/rows.js:29`) and then replaces the list, so
  the first read forces a layout of the whole document and each later one can force another: 44 ms of self
  time, most of it the Spaces table's layout paid early. `applyTab` calls
  `scrollIntoView` on the current tab on every render (`src/ph_composer/html/panel.js:430`), another forced layout.
  Removing one of these only moves the layout to the other, or to the frame; both would have to go to save it.

What the issue suspected is small. `units.profile` and `units.format` per cell in
`src/ph_composer/html/features/spaces/view.js` (`format`, line 186) cost about 6 ms of self time in a switch.
`preferences.current()` clones the profile once per cell; `preferences.peek()` exists for render loops and would
remove the clone, but the saving is too small to measure here. `record_edits.js` repainting clean draft cells on
the preference subscription (cells whose status is
`clean`) costs 4 to 8 ms.

## Proposed fix

In order of payoff. F1 and F2 meet the proposed target on this machine.

| Id | Change | Saving (every row open) |
| --- | --- | --- |
| F1 | One panel render per preference change | 835 to 269 ms |
| F2 | No render for a confirmed preference result that changes nothing | 269 to 172 ms |
| F3 | Read each header's CSS minimum width outside the write loop | 172 to 154 ms |
| F4 | Not prototyped: hidden-tab sections and `scrollIntoView` forcing layout | at most the 44 ms forced layout, if both go |

**F1, one render.** Two designs:

- *One owner (recommended).* The panel subscribes to the preference store once and renders on a profile change.
  The six inventories' subscriptions only repaint the panel, so they go. Components that patch their own DOM
  without a panel render keep theirs (`record_edits.js` clean cells, `unit_field.js`). Every `Inventory` is
  built inside a panel section (the Agent Access page loads no inventory), and the offline tests that build
  one directly paint it themselves after a preference change, so no consumer loses its repaint. Three details
  for the stage:
  - The panel's subscription must not render while `receive` is reducing a message, since `receive` renders
    afterwards; otherwise a snapshot that changes the profile still renders twice.
  - `setPreference` still renders itself for a key that does not change the profile (`table_view`), because
    `set` notifies no listener for it.
  - The panel's subscription is registered before any inventory's today, so it would run before the
    `record_edits.js` and `unit_field.js` patches. Their patches still land; the stage's test should show it.
- *Guard (the prototype).* `setPreference` holds `repaint` while `preferences.set` runs, then renders once. Smaller,
  and feature code is untouched, but every new preference listener that repaints is silently absorbed, and a
  profile change that arrives in a host snapshot (`preferences.replace` from `receive`, `panel.js:73`) still
  renders once per inventory plus once from `receive`. It treats the symptom at one call site.

**F2, no confirmation render.** `receive` renders on every message it handles. A completed
`preferences.result` whose stored preferences equal the applied profile, with no notice raised, changes nothing on
screen, and neither does a result for a request a later press superseded (`reducePreferenceResult`,
`panel.js:135`, returns the state unchanged). The reducer cannot yet tell the first case: profile equality is
decided inside `preferences.replace`, which returns nothing, so F2 needs `replace` to report whether the profile
moved. Nothing outside `panel.js` reads `ui.preferencePending`, so skipping the render loses nothing. A result
that is not `completed` (refused or failed) restores the previous value and raises a notice, so it still
renders.

**F3, minimum widths.** Split `paintHeaders` into passes: set every header's classes and actions, then read every
visible header's computed `min-width`, then write the widths. A header's minimum depends on classes the same loop
sets (`.has-header-actions` raises it to 72 px, `table.css:113`) and on `--row-actions-width`, set after
`paintHeaders` (`table.js:447`), so a pre-pass before the loop would read the previous render's minimum, and a
per-header cache like the prototype's goes stale when actions change or a column is resized
(`setColumnWidth`, `table.js:78`, reads the same minimum).

**F4** is left out of the proposal. Whether sections on hidden panes should render at all is a panel-wide
design question, larger than this issue.

Each fix needs a focused test: a unit switch causes one render of each section (F1), a confirmed unchanged
result causes none (F2). The browser check keeps printing the median; a stated target could become an
assertion with headroom, but timing assertions in CI flake, so the proposal is to keep it a printed figure
and check it at the host gate.

## Implementation

Ed authorized F1 and F2 on 2026-10-21, with the target set at under 200 ms per unit switch with every row
open. Both use the one-owner design:

- `src/ph_composer/html/panel.js` subscribes to the preference store once and renders when the display profile
  moves. `receive` and `setPreference` hold that render while they apply a change and render once afterwards.
  `src/ph_composer/html/inventory.js` no longer subscribes.
- Pending preference choices moved out of `state.ui` into the panel's own bookkeeping. `receive` renders
  nothing for a message that leaves the state and the display profile as they were, such as a confirmation of
  what is shown, an answer to a superseded choice, or a result for another session. A refusal still renders
  once, with the previous value restored and the notice shown.
- `context/TECH_STACK.md` ("The page") records the rule.

| Check | Result |
| --- | --- |
| `tools/ui-preview/spaces_checks.cjs` (300 Spaces) | Median 85 ms with the Zones open (80 to 89), 161 ms with every row open (157 to 168) |
| Profiling script, as in "Method" | Median 97 ms and 171 ms; 22 style recalculations per switch, down from 113 |
| `tests/panel_app_test.js`, two new cases | Fail on `main` with 4 renders where 1 is expected and 1 where 0 is expected; pass on the branch |
| `make ui-checks` | Every browser check passes |

## Not verified

- Chromium 88 in the HtmlDialog is not measured. It is older and may be slower; S07 re-measures.
- The real host answers asynchronously, so its baseline and its F2 saving may differ from the preview's.
- The prototypes ran against the timing only, not the offline suites or the browser checks.

## Prototype diff (scratch, not committed)

```diff
--- a/src/ph_composer/html/panel.js
+++ b/src/ph_composer/html/panel.js
@@ receive
     state = handler(state, payload);
     offerHelp(before, payload);
+    if (envelope.type === "preferences.result" && payload.status === "completed") return;
     render();
@@ setPreference
     state = withUI(state, { preferencePending: pending });
-    preferences.set(key, value, details);
+    holdRepaint += 1;
+    try { preferences.set(key, value, details); } finally { holdRepaint -= 1; }
     render();
@@ repaint
-  function repaint() { render(); }
+  var holdRepaint = 0;
+  function repaint() { if (!holdRepaint) render(); }
--- a/src/ph_composer/html/table.js
+++ b/src/ph_composer/html/table.js
@@ minimumColumnWidth
-    var computed = window.getComputedStyle ?
-      parseFloat(window.getComputedStyle(cache.headers[field]).minWidth) : 0;
+    var th = cache.headers[field];
+    if (th._cssMin === undefined) th._cssMin = window.getComputedStyle ? parseFloat(window.getComputedStyle(th).minWidth) : 0;
+    var computed = th._cssMin;
```

The C variant's `receive` change skips every completed result, which is only safe for timing: F2 must still
render when the result changes the profile.
