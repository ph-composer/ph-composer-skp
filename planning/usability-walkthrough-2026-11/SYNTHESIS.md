# Usability walkthrough: synthesis

DATE: 2026-11-07
STATUS: Draft for Ed's review. No issues posted yet.
AUTHOR: Ed May, BLDGTYP (walkthrough); Claude (synthesis)
ISSUE: none (local planning draft; issues below are drafts)

Source: [LOG.md](LOG.md), 123 raw entries (W-001 to W-123) from the 2026-11-07 run on `main`
`a39e1e19`. This file groups them, settles overlaps and conflicts, and drafts one GitHub issue
per group. Nothing here is implementation authorization. Items marked "(Claude)" are Claude's
observations or proposals, not requests from Ed.

## Outcome

Ed modelled the tutorial house in SketchUp through Zones, Faces, Spaces, Assemblies, Window Types
and Thermal Bridges. The agent read every stage back, created two placeholder Assemblies and ran
the HBJSON export. The export's windows match the Honeybee-PH tutorial almost exactly
(24 apertures, 32.43 vs 32.46 m2). It only exported after placeholder interior Assemblies were
added, honeybee rejects it, and PHX cannot convert it. Three problems stop a real modeller today:

1. **Creating Spaces fights SketchUp** (S-10, S-11). There is nowhere visible to draw inside an
   open Zone, the workarounds break good practice, and a drawn solid silently doubles iCFA.
2. **The export is not valid downstream** (S-16, S-17, S-29). honeybee rejects the interior
   Surface pair, PHX cannot convert the file, and placeholder material values go out as data.
3. **Agents cannot connect or export without a person finding hidden steps** (S-02, S-04). The
   recommended Claude Code setup cannot reach the desktop app, and export approval is filed under
   Libraries.

## Decisions for Ed

Each is needed before its issue can be planned. Recommendation first; all recommendations are
Claude's unless the row says otherwise.

| # | Decision | Recommendation | Issue |
| --- | --- | --- | --- |
| D1 | Where Spaces are drawn | Ed's preference: build Spaces outside a Zone, then host them (option A). Alternative: a "Build Spaces" mode that hides Zone Faces and drops new Spaces into that Zone (option B). Keep Create Space inside an open Zone working either way. Design packet first. | S-10 |
| D2 | Interior Surface Faces without an Assembly | Require an Assembly on a Surface Face only when its counterpart is in another Building-Segment; otherwise export with no construction. Assigning to one side of a pair assigns the reversed construction to the other. | S-17 |
| D3 | Default install psi-value | Ed asked for a built-in 0.04 W/mK default. Make it a model setting that starts at 0.04 W/mK, not a shipped library record, so the "no privileged provider" rule holds. Confirm whether PHI and Phius projects want different values. | S-30 |
| D4 | Thermal bridges on Edges shared by two Zones | Ed proposed de-duplicating. Count once per Building-Segment, Type and Edge geometry; flag only conflicting Types or different Building-Segments. | S-27 |
| D5 | Agent client connection | PH-Composer writes the live token to an owner-only file; a one-time client config reads it, so rotation touches no client settings. A "Connect Claude Code / Codex" button writes that config (Ed asked whether the app can run the setup). Verify per client first. | S-02 |
| D6 | Unhosted Window Units | Ed asked for a control. Detect, and snap a pasted Unit back to the nearest Face of its Zone; never undo from an observer. | S-22 |
| D7 | App-level settings | Ed proposed a gear at the top right opening a Setup view (Agent Access, approved locations, library setup). Placement to decide, distinct from the per-page gear (Claude, W-028). | S-01 |

## Settled while synthesising

- **Ventilated cladding as a boundary choice (W-060).** Ed's ask. Offer it in the Assembly's
  exterior dropdown, stored as Outdoors plus the ventilated flag, so the data stays honeybee's
  vocabulary (Claude).
- **Spaces airflow balance (W-054).** Ed: the check is per ERV, not per Zone. Remove the per-Zone
  check now; the per-ERV check goes to the planned Zones / Ventilation view in Phase 4.
- **Mulled paste (W-101).** Ed decided: paste what fits, skip what does not, no error.
- **Draw-then-convert windows (W-095)** is in addition to build-then-Place, which stays (Ed).
- **W-034 / W-123 (Claude).** The "stale adjacencies" repair is always offered and checks for
  nothing. Rename it, or offer it only when pairs are actually stale (S-14).
- **W-027 (Claude).** Ed found Solve adjacencies unaided (W-029). A proactive "coincident Outdoors
  Faces" finding is optional; folded into S-06.
- **W-111.** Export was blocked only by the interior pair; that is S-17.
- **W-120 / W-122 (Claude).** Adding a People load made PHX's WUFI XML conversion pass, so the
  failure sits in PHX's no-People path; the METr writer was not re-run and the mechanism was read,
  not stepped through. A PHX issue (S-29), not a PH-Composer one.
- **Not filed:** location, climate, north, shading and systems (W-110) are already Phase 4 and 5
  packets.
- **Keep (do not regress):** W-002, W-014, W-015, W-023, W-029, W-033, W-044, W-048, W-053, W-056,
  W-062, W-069, W-079, W-092, W-097, W-104, W-105, W-109, W-117.

## Proposed labels

Existing: `bug`, `enhancement`, `priority: P1` to `P4`, `size: S/M/L`. New: **`agent-access`**
for anything an agent cannot do that a user can (Ed asked for this class to be tracked).
Optional: `walkthrough-2026-11` to keep the set findable.

## Issue drafts

Priority: P1 blocks real use, produces wrong data, or is Ed's named top change; P2 a clear
workflow problem; P3 polish. "Packet" means a planning packet is needed before implementation.

### Agent access

**S-01 · Agent Access: move into the panel and simplify the token screens** · enhancement,
agent-access · P2 · M · W-001, W-003, W-004, W-005, W-009, W-012, W-013, W-028
- Reach Agent Access from inside the panel (D7), not only the Extensions menu.
- Token created screen: one client at a time (accordions), one default setup each, "Other ways to
  connect" behind an explicit control, a UI and readability pass.
- Window opens on New token; the token list is secondary, collapsed, grouped by time (today,
  yesterday, this week, this year); revoked tokens behind a toggle (Claude, W-009).
- Keep: the New token form (W-002).

**S-02 · Agent connection: the default Claude Code setup cannot reach GUI clients** ·
enhancement, agent-access · P1 · M · W-006, W-007, W-008, W-011
- The recommended `add-json` plus `export PH_COMPOSER_TOKEN` cannot work for the Claude desktop
  app or any client not started from a terminal.
- A running client never sees a newly added server. Ed: tell the user plainly and walk them
  through it, for example a final step "Start a new Claude Code session to connect". SketchUp
  needs no restart.
- Decide D5. One-click "Connect" needs the CLI found from a GUI process and a security review of
  the extension shelling out.
- Acceptance: a fresh Claude desktop session connects from the dialog's default path alone.

**S-03 · A token bound to "This Model only" stops working after Save As, silently** · bug,
agent-access · P1 · S · W-055 (Claude)
- Binding is by file path; Save As (a normal stage-copy habit) cuts the agent off and `discover`
  returns no sessions with no reason.
- Expected: `discover` says why ("bound to 02_Working.skp; open Model is 03_Spaces.skp"), and
  either the binding follows the document or the dialog warns at issue time.

**S-04 · Export approval for agents is hidden and can approve an invalid file** · bug,
agent-access · P1 · M · W-114, W-115, W-116
- Ed: fix for future agent work. The only entry is Extensions > PH-Composer > Libraries > Approve
  Export Destination; the Export tab's "Choose destination" approves nothing for agents.
- Offer "Allow agents to export here" in the Export tab or Agent Access. An agent's request is
  refused `access.user_required` without naming the path: name it, or open the native dialog for
  the user to answer.
- The dialog allows a name without `.hbjson`; `export_preflight` with that location passes and
  `start_export` refuses. Fix the extension in the dialog and make preflight report it.
- Hide or prune unavailable and development-era locations (Claude, W-114).

**S-05 · Agent schema and diagnostics gaps** · bug, agent-access · P3 · S · W-010, W-112 (Claude)
- `assemblies.create` schema gives layer and segment ids as plain strings; the validator wants
  `lyr_`/`seg_` plus 12 hex. State the pattern, or mint ids when absent.
- Log when the listener stops after the last revoke.
- Keep: bounded-read refusals that say how to ask for less (W-104).

### SketchUp-side behaviour

**S-06 · Show outcomes and refusals in SketchUp, not only in the panel** · enhancement · P2 · M ·
W-027, W-030, W-035, W-040 (toast part), W-094 (refusal part)
- Solve adjacencies (Ed: "a small modal notification ... that it worked"), Create Space refusals
  (Ed: "a note/warning/modal"), Place refusals: show what happened or why not in SketchUp.
- Panel failure toasts carry the reason and the incident id (Claude).
- If D1 lets Spaces be created outside a Zone, the Create Space refusal changes with it.

**S-07 · Context menu: split Classify faces, show current values, one PH-Composer home** ·
enhancement · P2 · M · W-021, W-076, W-077, W-106
- Ed: Set Face Type, Set Face Exposure, Set Face Assembly as three items, and a check mark on each
  current value (rule for mixed selections, Claude).
- All PH-Composer items under one submenu; one user-facing term for boundary (Claude).
- "Assign by clicking..." says what it does, with a status-bar hint while the tool runs.
- Make Zone's name prompt title (Claude, W-021). Relates to `features/unscheduled/zones-entry-points/`.

### Viewport overlay

**S-08 · Colour-by overlay ignores SketchUp's view state** · bug · P2 · L · W-031, W-032, W-078
- Section planes do not cut the overlay, so interior Faces cannot be seen (W-031, high).
- Hide Rest of Model does not hide the overlay for hidden geometry (W-078).
- Filtered-out Faces draw opaque white; offer see-through or hide while filtered (W-032).
- Keep: hidden Faces hide their overlay (W-033).

**S-09 · Thermal Bridges have no Colour-by entry; add by Group** · enhancement · P2 · S · W-107
- Ed: Colour by Name and Group, and a way to enter that view. The by-Type mode exists but is
  reachable only as a side effect of Assign by clicking. Add palette icons on the Types table and
  the Schedule; add a by-Group mode.

### Spaces

**S-10 · Space creation, editing and visibility: design packet** · enhancement · P1 · L · packet ·
W-036, W-038, W-039, W-042, W-046, W-052
- Inside an open Zone the Zone's Faces hide the plan, its tag cannot be hidden, and both
  workarounds break good practice; drawing there risks auto-splitting Zone geometry (W-036, blocker).
- Users draw rooms as solids; the app wants a floor outline plus height, and nothing on the
  SketchUp side says so (W-039).
- Height and outline can be edited only from panel routes Ed did not find; a locked Space cannot
  be reshaped in the viewport (W-038).
- Ed: Spaces visible by default (a "Show Spaces" check, on by default) and toggleable with a tag
  such as `02_SPACES`; today they vanish when the Zone closes because they nest in the Zone Group
  (W-046, W-052). Labels did not show either (Claude).
- Ed: delete a Space but keep its floor geometry (W-042).
- Decide D1. Parts exist: Spaces outside every Zone are allowed and Move to Zone re-hosts.
- Keep: flat floor outline Create Space works (W-044).

**S-11 · Create Space on a solid registers walls as floors and double-counts iCFA** · bug · P1 ·
M · W-037, W-045
- All faces of a drawn solid become Floor Segments: six vertical ones with `floor_projected`, top
  and bottom both counted (9.75 m2 for a 4.88 m2 room, Claude W-045). Height ignores the solid.
- Expected: take the bottom faces and the solid's height (as height-from-solid does), or refuse
  vertical and upward faces with a reason. Never count a floor twice.

**S-12 · Delete Space fails while its Zone is open** · bug · P1 · S · W-040, W-041, W-043
- `spaces.delete` raises `ArgumentError` in `DeleteSpaceStep#apply` (`erase_entities`) with the
  Zone open; works with it closed (Ed found this). Create needs the Zone open. Ed: delete must work
  in both states.
- Evidence: `evidence/w040-space-delete-failed.json`. Reproduce in a test first; root cause not
  yet tested.
- Dialog copy (Ed, W-041): title "Delete Space?", no Undo sentence.

**S-13 · Spaces table: wording, Height placement, order, balance check** · enhancement · P3 · S ·
W-049, W-050, W-051, W-054
- Ed: "Segment" row label becomes "Floor"; Height shows only on the Volume row where it is set.
- Sort Spaces by number, and Window Types by name (Claude, W-051, W-100).
- Remove the per-Zone supply/extract warning (Ed, settled above).

### Zones and Faces

**S-14 · Zones view polish** · enhancement · P3 · S · W-016, W-017, W-018, W-020, W-022, W-024,
W-081, W-123
- Ed: sub-tab Faces becomes Geometry; Ground depth hidden by default and explained; Building
  Segments modal polish (no full-width Add) and a custom colour picker (one exists but was not
  found, Claude).
- (Claude) Default Building Segment not named after the file; Face default names number per type;
  clipped headers on horizontal scroll; rename "Solve stale adjacencies before export" or offer
  it only when stale.

### Assemblies and Materials

**S-15 · Material entry: thermal input forms, colour, create from the Assembly page** ·
enhancement · P2 · M · W-063, W-064, W-065, W-067
- Ed: input-form dropdown beside thermal values (R per inch default in IP, conductivity, others),
  converted by the app (W-064, high); colour picker in New Material; "+ New Material" by the
  empty-state icon (every table).
- (Claude) New Material from the Assembly sidebar (W-067).

**S-16 · Material placeholders export as data** · bug · P1 · S · W-066, W-074, W-121 (Claude)
- New Material pre-fills density 1 lb/ft3, specific heat 1 Btu/(lb F), emissivity 1; every
  Material in the export carries 16.02 kg/m3 and 4186.8 J/kgK, Concrete included.
- Expected: blank or visibly-default values, and a preflight finding when unset values would be
  written. Decide what the export writes when they are unset.

**S-17 · Interior Surface pairs: Assembly rules and honeybee validity** · bug · P1 · M ·
W-084, W-113, W-118
- Ed raised it (W-084). Export blocks on interior Faces without an Assembly; with two different
  Assemblies it warns, exports, and honeybee's `check_all` rejects the model (Claude, evidence
  `w118-honeybee-check-all.txt`).
- Decide D2. PHX already drops Surface Faces within one Building-Segment
  (`PHX/from_HBJSON/cleanup.py`). Verify honeybee validity of the chosen rule with a round trip.

**S-31 · Assemblies: replace-and-delete, and two bugs** · bug · P2 · S · W-059, W-082, W-083
- Ed could not tell what the Replace action does (W-082, high). It moves Faces to a replacement
  and deletes the Assembly. Decide what it is, name it in one sentence, show Faces by Zone and
  name (not ids), disable with a reason when no replacement exists.
- U-value popover repeats one message per Layer-Segment (W-059). Paint from the Assemblies table
  jumps to Zones > Faces (W-083).

**S-18 · Assembly builder polish** · enhancement · P3 · M · W-057, W-058, W-060, W-061, W-073,
W-080
- Ed: hover delay (100 to 200 ms), Layer tools popover polish (icons, consolidate), Paint in the
  Assembly detail view, ventilated cladding in the exterior dropdown (settled above).
- (Claude) "Layer-Segment" wording; IP U-values need another significant figure.

### Library

**S-19 · Library sidebar and tables polish** · enhancement · P3 · M · W-070, W-071, W-072, W-085,
W-087, W-096
- Ed: "Materials in this file" label and drop the note; gear icon for Library setup; chevron
  matching the collapse direction; the same on every kind's sidebar; choosers alphabetical.
- (Claude) Frame chooser lists the slot's Position first; empty Actions column on Frames rows.
- Relates to #332 (sidebar loading state).

**S-20 · Frames: Brand field and an auto-name** · enhancement · P3 · S · W-086
- Ed: add Brand; Group by Brand; optional name from `{manufacturer}-{brand}-{position}-{operation}`.

### Windows

**S-21 · Draw a rectangle, convert it to a Window Type** · enhancement · P1 · L · packet · W-095
- P1 because Ed named it his biggest UX change, not because it blocks. In addition to
  build-then-Place. Selected rectangle(s) on a Zone Face become a Window Type sized from geometry
  (several become a mulled Type) and are replaced by a placed Unit. Open points in the log entry:
  host, sill rule, mulling refusal, reuse of an existing same-size Type, new-Type defaults.

**S-22 · Place tool: snapping and a visible hint; guard against unhosted Units** · enhancement ·
P2 · M · W-093, W-094, W-098
- Ed: Place must snap so CAD can guide it (W-094, high); the sill/offset hint more prominent,
  for example a callout (W-093).
- Ed: a pasted Unit must not end up outside its Zone (W-098, high); D6.

**S-23 · Window Units: names and selection sync** · enhancement · P3 · M · W-099, W-100
- Ed: Unit name editable in PH-Composer and via Entity Info's Instance field; the Schedule
  indicates the Unit selected in SketchUp. (Claude) names unique model-wide.

**S-24 · Window Type builder bugs** · bug · P2 · S · W-088, W-101, W-103
- Dimension format has no effect (Ed). Likely cause, not tested: the field declares `builder`
  where `units.profile` reads `scope`; Assemblies probably has the same. Test first, then fix.
- Mulled paste refused over Psi-Installs: paste what fits, skip the rest, no error (Ed's decision).
- Slide operation draws a swing triangle instead of an arrow (Ed).

**S-25 · Notices, popovers, chips and tooltips** · bug · P2 · S · W-019, W-025, W-026, W-047,
W-068, W-075, W-089, W-102
- Undismissable warning toast (Ed, W-102, high). Popovers and validation messages clipped by table
  overflow (Ed, W-075, W-089).
- Ed: dark text on a dark chip must never be allowed; guard against it. Cause (Claude): the
  luminance rule picks black for #268589, which sits just past its cut-off.
- Material colour swatches missing in the Assemblies sidebar and Frames table (Ed, W-068).
- Help tooltip changes width; header icon alignment and highlighted-icon padding inconsistent.
- (Claude) a g-value of 37 could prompt "did you mean 0.37?".

**S-26 · Psi-Install editor polish** · enhancement · P3 · S · W-090
- Ed: Cancel and Save near the work, tab state while in the editor, centred drawing, highlight
  style, icon actions.

**S-30 · Model default install psi-value** · enhancement · P2 · S · W-091
- Ed: always apply 0.04 W/mK unless the user sets another; today "Model default: Missing". D3.

### Thermal Bridges

**S-27 · De-duplicate thermal bridges on Edges shared by two Zones** · enhancement · P2 · M ·
W-108
- Today `thermal_bridge.counted_twice` warns and both export. Implement D4. The both-Zones case
  was not exercised in the walkthrough; reproduce it in a test.

### Export

**S-28 · Export report omits preflight warnings** · bug · P3 · S · W-119 (Claude)
- Report says "No findings" while preflight listed four warnings.

**S-29 (PH-Tools/PHX) · No-People default path leaves occupancy references dangling** · bug ·
P1 · S · W-120, W-122 (Claude)
- A load-free HBJSON fails both WUFI XML and METr JSON identity validation (15 dangling
  `occupancy.schedule` references). With a zero People load added, WUFI XML converts cleanly
  (METr not re-run). Reading `merge_occupancies`: it makes `default_occ_schedule`, which appears
  never to reach `utilization_patterns_occupancy`.
- File in PH-Tools/PHX with the three evidence logs; blocks PH-Composer's METr exporter.

## Order of work (proposal)

1. Data correctness and export: S-16, S-17, S-29 (PHX), S-12, S-11, S-28.
2. Design packets: S-10 (Spaces), S-21 (draw-then-convert). Both need D1 or the open points first.
3. Agent access: S-02, S-04, S-03, then S-01, S-05.
4. SketchUp-side behaviour and overlay: S-06, S-07, S-08, S-09, S-22.
5. Bugs and polish: S-24, S-25, S-31, S-30, S-27, then S-13, S-14, S-15, S-18, S-19, S-20, S-23,
   S-26.

## Coverage

Every W-entry is in an issue above, in "Settled", or in the "Keep" list. `STATUS.md` keeps one row
for this walkthrough until the issues are posted; each issue then links back to this file and its
W-ids.
