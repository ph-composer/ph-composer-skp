---
name: ph-composer-ui-polish
description: Design, polish, refactor, or review PH-Composer HtmlDialog screens using the shared UI kit, visual hierarchy, interaction grammar, prototype-first mockups, and browser/host verification. Use for any UI or UX work in src/ph_composer/html/ or feature mockups.
---

# PH-Composer UI Polish

Treat every screen as one view of a single application, never a standalone visual redesign. Preserve behavior and domain language while keeping the initial state quiet, legible, and predictable.

## Core Principles

- **Design for the consultant:** Make the next step obvious, keep the work surface stationary, and cut unnecessary words and controls. Push back on any direction (including the owner's) that harms end-user clarity before building it.
- **Geometry first, then action:** The user selects geometry, then chooses one attribute action. Modal action-first tools are secondary unless the feature plan justifies them (`context/TECH_STACK.md`, "Rules for later features").
- **Kit reusability:** A shared UI kit pattern that depends on one feature's data shape is a kit defect.
- **Design System sync:** Stylesheets in `src/ph_composer/html/` are the authority. The private [PH-Composer Design System](https://claude.ai/artifact/77GLrkZxtkxo9TksTbvodL) artifact is a reading aid; after changing a kit token, type style, shared part, or state, re-sync the artifact from `main` in the same piece of work and report whether it was done (or why not).

## Establish the Baseline

1. Read `AGENTS.md`, the active feature plan/UI spec, and local `.index.md` / `.instructions.md` files for paths in scope.
2. Read [references/patterns.md](references/patterns.md) for current shared primitives, accepted screen patterns, and visual tokens; verify against live source in `src/ph_composer/html/`.
3. Inventory visible regions, actions, states, warnings, and selections, plus invariants that must survive (commands, disabled states, focus return, Escape unwinding, Undo boundaries, host workflows).

## Design & Interaction Rules

Apply in order from structure down to details:

### 1. Hierarchy & Naming
- One clear page title (`ui.pageHeader`), restrained metadata, and prominent primary metrics. Use size, weight, spacing, and grouping before color.
- Metric labels use PH symbols with subscripts (`U<sub>w</sub>`, `U<sub>w,installed</sub>`) and carry units so the value line is a bare number (em dash + tooltip naming what is missing when absent). Put nuance in an info icon + hover bubble, not a longer label.
- Never put constant captions or readiness text under the title. Show why a primary action is blocked beside it with `ui.reasonButton(action, reason)` (anchored bubble, never a page notice or footer).
- Inline rename for titles and sidebar rows: field with check/cross icons (Enter or blur applies, Escape cancels); never open a modal for one text field.
- **New / Duplicate / Delete:** Visual records (Assembly, Window Type) create/duplicate immediately under a free default name with round unit-aware defaults (e.g., 1000 × 1500 mm / 40 × 60 in) and open the title for renaming. Pure-number records (Material, Frame, Glazing, Psi-Install Type, Attached zone) use `formDialog` with required fields marked and a muted status line explaining a disabled Create. Delete confirms in `formDialog` naming what goes. Per-record Rename/Duplicate/Delete live on sidebar rows (revealed on hover/focus).
- Active setting choices (`aria-pressed="true"`) use `--interaction-highlight-tint` with teal text/border, unchanged on hover. Menu rows show short state values (e.g. unit id) so they never overflow.

### 2. Layout & Navigation
- Keep headers, sidebars, toolbars, work surfaces, inspectors, and status areas spatially consistent.
- Distinct peer jobs on one page use shared sub-tabs (`subtabs.js`, with `aria-label`) showing one work surface at a time—never stack an editor below an inventory table, and never style a feature-local tab bar.
- Sub-tabs share the page heading (which holds the active tab's primary `+ New` action). Each tab body starts with its action bar, never a second title.

### 3. Actions & Page Header
- Upper-right header order: grouped icon toolbar for frequent actions → config icon opening an anchored bubble → one labeled primary action → ellipsis overflow menu for infrequent/secondary actions (destructive items last).
- Show only actions valid for the current selection. Mutually exclusive binary states (e.g. Glazed / Empty) share one button that repaints its icon and label from selection (first selected item decides on mixed selection).
- Keep active progress and cancellation visible.

### 4. Progressive Disclosure & Sidebars
- Start with the minimum needed to orient and act; reveal contextual tools on selection and put configuration in anchored bubbles/menus.
- If a disclosed surface owns an active transaction, draft, Save, or Cancel, keep it visible and guard navigation (`panel.navigationGuard`) until the transaction ends.
- Reuse the shared collapsible sidebar, preserving selection when collapsed and degrading to a compact horizontal control at narrow widths.

### 5. Feedback, Notices & Dialogs
- Render floating notices in an overlay layer so late messages never reflow the page; preserve intrinsic height and verify wrapped text.
- Notice tones: `success` (white + check, auto-fades after 3 s, held on hover/focus—never use for instructions), `info` (white, fades on next meaningful interaction), `warning` (yellow, persistent), `error` (red, persistent). Newer notices replace older ones. All have an accessible Dismiss button and close on Escape (after bubbles/dialogs).
- Record forms use `formDialog` (top-right close matches Escape/Cancel, returns focus; right-aligned footer: Cancel then consequence-labeled commit; immediate-apply dialogs use Close/Done, never Cancel).
- Single-value edits open a compact anchored bubble (title + unit field only; Enter/blur applies, Escape restores then closes, invalid stays open; accepted formats in tooltip).
- One-Undo-step visible edits (merge, split, flip, insert) apply immediately without confirmation; confirm only when discarding user assignments/elements. Every commit path (Enter, blur, click) must hit the same submit handler.

### 6. Graphics & Drawing Interaction
- Prefer unfilled geometry, crisp outlines, and architectural line hierarchy (perimeter heaviest, component boundaries medium, internal details/operation lines lightest). Give selectable unfilled SVG shapes `pointer-events: all`.
- Two distinct highlight roles: `--drawing-highlight` (red) for transient hover/focus/insert/drop; `--interaction-highlight` (teal) + `--interaction-highlight-tint` fill for selection. Render hover/selection/controls in a top overlay layer above geometry.
- Additive edge controls appear on proximity (one per edge, named by visual result like "Insert row above"), apply immediately with a round unit-aware default as one Undo step, and select the created element.
- Modal drawing tools reflect state in three places at once: pressed toolbar button, icon, and viewport/drawing cursor (stage changes update icon + cursor together). Escape unwinds one layer at a time (bubble/dialog → active tool → selection), including when focus falls to `document.body`.
- Screen furniture (labels, dimension lines, pills, controls) scales only within 0.9×–1.25× while geometry zooms freely. Edits never change zoom (fit only on open, resize, or Fit action; oversized drawings scroll).
- Missing inputs show as an amber `?` pill or amber row tint + alert icon with tooltip naming what is missing, on the row where it belongs.
- Toolbar glyphs come from the Lucide set (with ISC notice preserved). Keep accessible names on drawing affordances, but do not add tab stops for them.

### 7. Editable Tables
- The cell grid is the visual boundary; do not box inputs at rest. Row owns hover (light wash over all cells); cell owns focus, selection, invalid, and pending states.
- Focused cells accept printable typing immediately (preserving the first character); keep identity/action columns sticky and aligned during edits and column resizing.
- Secondary table controls sit in compact icon-button menus in the control row (Columns, Colour by, view-specific menus)—never an in-flow column panel or bank of width sliders. Unavailable menus stay visible with a tooltip reason.
- Invalid-edit messages anchor to the cell on focus/hover without increasing row height, linked via ARIA and cleared on fix/cancel.

### 8. Words, Lists & Edge Rules
- **Glossary words:** Display terms from `context/UBIQUITOUS_LANGUAGE.md` (and Honeybee face/boundary labels), never raw enums, finding codes, or record IDs (put IDs in tooltips/audit views). Capitalize control labels.
- **Stable lists:** Never reorder lists, cards, or choices on selection, hover, or focus.
- **No scalloped edges:** Thick (>1 px) left/right accent bars (`border-left`, `border-inline-start`, inset box-shadow) are banned on rounded elements; communicate state via fill, label color, and icon. Separate adjacent flagged rows with alternating amber zebra tints and a hairline gap.

## Prototype-First Planning

When shaping a new screen or flow, build a clickable mockup before writing prose specs:

1. Scaffold with `make mockup-new MOCKUP_DIR=planning/features/<slug>/mockups` using the mockup kit (`tools/ui-preview/.index.md`), which loads the panel's stylesheets.
2. Open it in the preview server browser pane and iterate directly on owner picks (one small edit + reload + one-line confirmation). Ask open questions one at a time or show them as mockup states.
3. Record landed decisions in the packet's `DECISIONS.md`. Add scenes to `scenes.js`, recapture with `make ui-gallery MOCKUP=...`, and push once per topic.
4. Derive the PRD and phase plans from the reviewed mockup and link its scene table. Record newly accepted screen patterns in [references/patterns.md](references/patterns.md).

**Boards instead of a clickable page.** The mockup kit is the default. Only when the owner asks for boards
(many states side by side), draw them on a Design canvas with the PH-Composer Design System and keep the
source in `planning/features/<slug>/mockups/canvas/project/`: `canvas.json` plus one `*.dc.html` per board.
Publish with `root` set to the `canvas` folder, and read the published files before overwriting them. Ask
each decision as one dialog of two or three options, recommendation first. Decisions still go in the
packet's `DECISIONS.md`, never only on the canvas.

## Verification

1. **Deterministic tests:** Assert structure, accessible names, state transitions, and preserved commands (including Enter submit), not decorative markup.
2. **Manifest & gates:** Refresh the panel/runtime manifest when packaged assets change and run applicable repo gates.
3. **Offline browser checks:** Use `make ui-preview` for interactive inspection, `make ui-checks` (`make ui-deps` once for Playwright), and `make ui-gallery` across all panel sizes. Every browser check must run through `tools/ui-preview/support/browser_evidence.cjs` (`check({ name, output }, ...)`, declaring intentional errors with `expect`; `PH_COMPOSER_BROWSER_TRACE=on-failure` keeps traces) and verify layout via `tools/ui-preview/support/pane_fit.cjs` at `PANEL_SIZES` (`1280×800`, `420×732`, `360×520`)—no horizontal panel scroll and no floating controls covering headers.
4. **Real host check:** Offline preview does not replace host verification. Check the real SketchUp host at representative sizes (do not bring SketchUp forward over active user work; retake captures when visible). Run fresh-process acceptance when required without discarding unsaved models.
5. **Review:** Combine UI and architecture findings in the existing review ladder using `ph-composer-architecture-review` for code boundaries. Report what changed, what passed, and any deliberately omitted host checks.
