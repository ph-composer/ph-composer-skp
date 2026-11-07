# Usability walkthrough: raw log

DATE: 2026-11-07
STATUS: In progress. Raw, append-only log. Synthesis and issue drafts go in `SYNTHESIS.md`.
AUTHOR: Ed May, BLDGTYP

Ed models the tutorial house (two-story, two-Zone single-family) end to end in real SketchUp
to judge how the current `main` feels to a human user. Each entry records one observation as it
happens. Entries are not merged, edited or deduplicated here. This deliberately departs from
issue-first intake: issues are filed after synthesis, so overlaps and conflicts are resolved first.

## Setup

- Build: `main` at `a39e1e19`, installed with `make install` into SketchUp 2026, host bridge on.
- Model: the tutorial project's CAD-imported start file, copied to a working file. A copy is
  checkpointed at the end of each stage. The project folder is local and gitignored.
- References (same house, other tools; small differences across years): the DesignPH tutorial
  SketchUp files, the PHPP 10 intro workbook, the Honeybee-PH tutorial (Rhino, Grasshopper,
  `Model_v1.hbjson`, `Model_v2.hbjson`) and the WUFI-Passive intro SketchUp file. Paths stay out
  of this public log.
- Known before starting: location, climate and north are not implemented (Phase 5 PRD only).

## Stages

1. Zone geometry and Face attributes
2. Spaces: geometry, names, numbers, ventilation flow rates, hosting
3. Assemblies and Materials, assigned to Faces
4. Window Types, placed in the model
5. Thermal Bridges, assigned to Edges
6. Location and north
7. HBJSON export, compared against the references

## Entry format

`W-NNN` · stage · kind · severity

- kind: `bug`, `friction` (works but feels wrong), `feature` (missing capability), `agent-access`
  (an agent cannot do what Ed can, or only with difficulty), `question` (needs a decision),
  `good` (worth keeping)
- severity: `blocker`, `high`, `medium`, `low`

Then: what Ed did; expected; actual; evidence (file under `evidence/`, if any); note.

## Entries

### Stage 0: Agent Access setup

**W-001** · 0 · friction · medium
Ed opened Agent Access from Extensions > PH-Composer > Agent Access.
Expected: reach it from inside the main PH-Composer panel.
Actual: it is a separate menu item and its own window, outside the panel.
Note: Ed proposes a Setup/Config view in the panel, reached by a gear icon at the top right,
holding this and similar machine/session settings.

**W-002** · 0 · good · low
The New agent token form (name, access checkboxes with one-line consent copy, This Model only)
reads well. Keep it.

**W-003** · 0 · friction · high
Token created screen shows everything at once: the token, three Claude Code setups and two Codex
setups, each with explanatory prose.
Expected: one client at a time.
Note: at minimum, Claude Code and Codex as accordions.

**W-004** · 0 · friction · high
The screen offers several setups per client without saying which is better or what the difference
means.
Expected: one default per client, shown plainly; the alternatives behind an explicit "Other ways
to connect" control, seen only when asked for.

**W-005** · 0 · friction · high
Token created screen: too much text, no clear hierarchy, no single focus.
Note: needs a UI and readability pass (`ph-composer-ui-polish`), not only re-ordering.

**W-006** · 0 · agent-access · high
The default Claude Code setup (`add-json` reading `${PH_COMPOSER_TOKEN}` plus `export` in a
terminal) cannot work for the Claude desktop app: it is not started from a terminal, so the
exported variable never reaches it. The same applies to any GUI-launched client.
Also: a client session already running does not pick up a newly added MCP server; it needs a new
session. In this walkthrough Claude fell back to calling the endpoint directly with the token in
an owner-only scratch file, which Ed rightly asked about (W-007).

**W-007** · 0 · question · medium
Ed: why does Claude use a different method (token in a file, direct calls) than the ones the
dialog recommends? If the file is better, build it into the app; if the command is better, use it.
Answer given: the file route is a stopgap for an already-running session, not a better method.
Open design question for synthesis: a token file the extension writes (owner-only) that a stable
client config reads would make rotation touch no client config. Needs checking per client
(Claude Code headers helper; Codex reads only an env var or an inline token).

**W-008** · 0 · feature · medium
Ed: can the dialog run the setup for the user instead of copy and paste?
Note: SketchUp on macOS is not sandboxed, so Ruby can run the client CLI or write its config.
Costs: locating the `claude`/`codex` binary from a GUI process (PATH differs), editing another
app's settings, and a security review of the extension shelling out. A "Connect Claude Code"
button is feasible; decide in synthesis together with W-007.

**W-009** · 0 · friction · low (Claude's observation)
The token list behind the dialog is mostly old revoked development tokens; live tokens do not
stand out. Consider hiding revoked rows behind a toggle.

**W-010** · 0 · agent-access · low (Claude's observation)
Diagnostics record `agent_access_listening` when the first token is issued but nothing when the
last revoke stops the listener, so an agent cannot tell from the log why its connection is refused.

**W-011** · 0 · friction · high
A client session already running never sees a newly added PH-Composer MCP server; the agent
client (Claude Code, Codex) must start a new session. SketchUp itself does not need a restart: it
listens as soon as a token is issued. Nothing in the dialog says this.
Expected: the setup flow states every step that is required for it to work and walks the user
through it, with a clear prompt (modal or final step) such as "Start a new Claude Code session to
connect". Critical steps are instructions, not footnotes.

**W-012** · 0 · friction · medium
The token list shows every token ever issued, revoked ones included, as the main content of the
window (see W-009).
Expected: the list as an accordion grouped by time (today, yesterday, this week, this year),
collapsed by default, clearly secondary.

**W-013** · 0 · friction · medium
The window opens on the token list.
Expected: "New token" is the primary element; the list and its detail are extra, reached on click
or expand.

**W-014** · 0 · good · low (Claude's observation)
With a new token saved to a file, a direct MCP call worked first time: `initialize`, `tools/list`
(15 tools), `discover` (one session, `02_Working.skp`, all operations grouped by owner) and
`context`. The server instructions ("call discover first ... describe an operation before calling
it") are clear.

### Stage 1: Zones and Faces

**W-015** · 1 · good · low
Ed selected the first-floor box, right-clicked, PH-Composer > Make Zone, named it Floor-01. The
action is where he expected and worked first time. The six Faces were classified automatically
(Floor/Ground, four Walls and a RoofCeiling Outdoors), confirmed through the agent read
(276.7 m2 Face area, 0 unclassified).

**W-016** · 1 · friction · low
Zones sub-tabs are Faces and Spaces. The Faces table also holds Zone-level attributes
(Building Segment, Level, ground depth).
Expected: rename the sub-tab Geometry (Zones / Geometry), which covers both.

**W-017** · 1 · friction · medium
Manage Building Segments modal needs a UI polish pass; the full-width Add button looks wrong.

**W-018** · 1 · feature · low
Ed wants a custom colour picker beside the palette swatches.
Note (Claude): the square swatch left of the hex field is already a native colour input
(`option_dialog.js`), so the picker exists but Ed did not find it. Treat as discoverability.

**W-019** · 1 · bug · medium
Dark text on the dark teal chip ("02_Working" on #268589) is hard to read. Ed: never allow this;
guard against it.
Note (Claude): a guard exists (`zone_options.js`, WCAG luminance with a 0.179 cut). #268589 has
luminance 0.190, so it picks black: black about 4.8:1, white about 4.4:1, both marginal. The rule
works as written; the palette colour sits on the knife edge. Fix by biasing to white, or by
keeping palette colours clear of the cut.

**W-020** · 1 · friction · low (Claude's observation)
The default Building Segment is named after the file ("02_Working"). Ed renamed it Main Building.
A neutral default name may serve better.

**W-021** · 1 · friction · low (Claude's observation)
Make Zone asks for the name in a native SketchUp input box titled "Selected Zones", for one new
Zone. Title and styling differ from the panel.

**W-022** · 1 · friction · low (Claude's observation)
Default Face names number across all types: Floor 1, Wall 2, Wall 3, Roof or ceiling 4, Wall 5,
Wall 6. Per-type numbering (Wall 1 to 4) would read better.

**W-023** · 1 · good · low
Second Zone (Floor-02) made the same way. Building Segment renamed Main; Levels Level-01 and
Level-02 assigned. Colour by Face type in the viewport, with its legend, reads clearly.

**W-024** · 1 · friction · medium
"Ground depth mm" is unexplained; its header tooltip only repeats the header text.
Expected: hidden by default (column chooser), and an explanation where it is shown.

**W-025** · 1 · bug · low
The table help (?) tooltip changes width as the pointer moves over the icon (two captures, two
wrap widths). It should keep one size.

**W-026** · 1 · friction · low
The active Colour-by icon under a column header (Type) sits too close to the header text.
Padding and margins need polish.

**W-027** · 1 · question · medium (Claude's observation)
After both Zones exist, Floor-02's Floor and Floor-01's RoofCeiling are both Outdoors, though they
coincide. The agent read shows no finding on either Zone, and the panel shows no prompt. Watching
whether Ed finds the adjacency step unaided; if not, the app should flag coincident Outdoors Faces
between Zones and offer to solve adjacency.

**W-028** · 1 · friction · low (Claude's observation)
The Zones page already has its own gear (top right, page settings) besides the one Ed proposes for
app setup in W-001. Two gears with different scopes need distinct placement or labels.

**W-029** · 1 · good · low
Ed selected both Zones, right-click PH-Composer > Solve adjacencies for selected Zones. Floor-01's
RoofCeiling and Floor-02's Floor became Surface (locked, with the lock icon). Found unaided. The
filter popover's note "Surface is set by Solve adjacencies" helps.

**W-030** · 1 · friction · medium
Solve adjacencies gives no confirmation on the SketchUp side; the result shows only in the panel.
Expected: a brief notice in SketchUp that it ran and what it changed (for example "2 Faces paired
as Surface").

**W-031** · 1 · feature · high
Interior Faces (the Surface pair) are hard to see. A SketchUp section plane cuts the geometry but
not the Colour-by overlay, so the Outdoors fill still covers the cut and the green Surface Face
stays hidden. Only a camera inside the Zone shows it.
Expected: the overlay is cut by the active section plane, as a user would assume.
Note (Claude): the overlay is drawn by `colour_by/overlay.rb` through the view, which section
planes do not clip. It would have to clip its own tessellation against the active section plane.

**W-032** · 1 · friction · medium
Unchecking a Boundary in the column filter stops colouring those Faces, but SketchUp then draws
them plain white and opaque, so the inside still cannot be seen.
Expected: a way to see through or past filtered-out Faces (drawn transparent or hidden while
filtered).
Note (Claude): the legend also has Isolate (`colour_by.isolate`, HUD "Showing only"); not tried
here, and it likely leaves the other Faces opaque the same way. Check in synthesis.

**W-033** · 1 · good · low
Hiding a Face in SketchUp hides its overlay too.

**W-034** · 1 · question · low (Claude's observation)
End of Stage 1, agent read: 12 Faces (8 Wall Outdoors, Floor Ground, Floor/RoofCeiling Surface
pair, RoofCeiling Outdoors), no findings. Yet `zones.export_preflight` still proposes the repair
"Solve stale adjacencies before export" for both Zones, right after Ed solved them. Either the
pairing went stale (Ed hid and unhid Faces) or the repair is always offered. Check before
Stage 7.

Stage 1 checkpoint: `_checkpoints/01_zones.skp`.

### Stage 2: Spaces

**W-035** · 2 · friction · high
Ed drew a floor outline outside any Zone, right-click PH-Composer > Create Space. Refused, with
the message only in the panel: "Create Space works inside a Zone: open the Zone's edit context,
select the floor outlines, then choose Create Space. Nothing was written."
Expected: a refusal from a SketchUp action shows in SketchUp (notice or modal), not only in the
panel. Same pattern as W-030.

**W-036** · 2 · friction · blocker
Inside an open Zone, the Zone's own Faces cover the floor plan, so there is nowhere visible to draw
the Space. The Zone's tag (01_GEOM) cannot be hidden while the Zone is open (SketchUp: "You can not
hide the tag the active group or component is on"). Workarounds both break good practice:
1. Put the Zone's raw Faces on their own tag and hide it. Raw geometry should stay Untagged; only
   Groups and Components are tagged.
2. Hide the Zone's Faces. Hidden Faces inside a Group can only be unhidden from inside that Group,
   which confuses users.
Also: drawing inside an open Zone lets SketchUp's auto-split interact with Zone geometry; a floor
outline on a Zone edge can split it by accident.
Ed used workaround 2 for this test.
Ed's proposals, for research:
- A. Build Spaces outside a Zone, then select them and set their host Zone (a hosting tool).
  Ed's preferred direction: cleaner, no geometry interaction.
- B. A "Build Spaces" mode that hides all Zone Faces (edges stay as outlines); Spaces drawn while
  it is on land in that Zone.
Note (Claude): parts of A exist. `docs/PRODUCT.md` says a Space outside every Zone is listed after
the Zones, and Move to Zone (`spaces.move_to_zone`) re-hosts a Space where it stands. Only Create
Space is limited to an open Zone. The product text already tells users to draw the outline below
the Zone floor or inset from its walls to avoid splitting (Ed did not see that guidance). SketchUp's
X-ray mode is another partial workaround, but inference still snaps to Zone Faces.

**W-037** · 2 · bug · high
With the Zone's Faces hidden, Ed drew the Entry as an extruded L-shaped solid inside Floor-01,
selected it and ran Create Space. It made Space 101 Entry, but all eight Faces of the solid became
Floor Segments; the six vertical ones carry `space.floor_projected` (plan area used). Height is the
2.5 m default, not the drawn solid's height. Agent read: 9.75 m2 floor, 24.38 m3.
Note (Claude): a mental-model mismatch. Ed, like Honeybee and DesignPH users, models a room as a
closed solid; PH-Composer models a floor outline plus a height. Create Space should either accept a
solid (floor from its bottom Faces, height from the solid, as the existing "height from solid"
does) or refuse vertical Faces with a clear reason. Silently registering walls as floors is wrong.

**W-038** · 2 · friction · high
After creation the Space is locked (protected Volume). Ed drew it too short and cannot fix the
height by editing the geometry.
Expected: change a Space's shape and height directly in the viewport.
Note (Claude): existing routes are panel-only and Ed did not find them: the height cell in Zones >
Spaces, "height from a closed solid" (`spaces.volumes.height_from_solid`), and the row's Open or
Enter to edit Floor Segments. Discoverability from the SketchUp side is the gap, and W-037's
solid-based expectation compounds it.

**W-039** · 2 · friction · high
Ed: "am I supposed to ONLY draw the floor? not the walls as well?" Nothing in the SketchUp-side
workflow (context menu, Create Space review, refusal text) tells the user that a Space is a floor
outline plus a height value. The rule lives in `docs/PRODUCT.md` only. Ties to W-036 and W-037.

**W-040** · 2 · bug · high
Ed deleted Space 101 Entry from its row (Delete, then Delete in the confirmation). It failed three
times with only "The change could not be completed. No changes were retained." There was no way to
delete the Space from the panel.
Evidence: `evidence/w040-space-delete-failed.json`, incidents PHC-7CDF84, PHC-445CCC, PHC-D2129B:
`ph_composer.spaces.delete`, `ArgumentError` raised by `erase_entities` in
`DeleteSpaceStep#apply` (`features/spaces/steps.rb:225`), rolled back. The Zone was open at the time
(active path is the Zone). Root cause not yet tested; the Space is a locked, protected Group, which
is a likely suspect. Ed then removed it some other way (the Space list is empty at revision 96).
Also: the toast gives no reason and no incident id to quote.

**W-041** · 2 · friction · low
Delete Space confirmation: title "Delete Entry" should read "Delete Space?". Drop the Undo
sentence; say only what will happen.

**W-042** · 2 · feature · medium
Ed: allow deleting a Space while keeping its floor geometry in SketchUp (unregister the Space,
leave the Faces), so the outline can be reused or reclassified.

**W-043** · 2 · bug · high
Follow-up to W-040, found by Ed: Delete Space succeeds only when the Zone is closed, and fails
(the `ArgumentError` above) while the Zone is open. Create Space works only while the Zone is open.
The two required states are opposite, with no message saying so.
Expected: Delete works in both states; no Space action should depend on the edit path unless it
says why and offers to change it.
Repro: open Zone Floor-01, Zones > Spaces, row Delete on a Space in that Zone.

**W-044** · 2 · good · low
Create Space from a single flat floor outline (drawn inside the open Zone, Zone Faces hidden)
works: Space 101 Entry, one Volume, one Floor Segment, no findings, 4.88 m2, 2.5 m, 12.19 m3.
Colour by Ventilation then shows its prism.

**W-045** · 2 · bug · high (Claude's observation)
Correction to W-037: the solid-based Entry reported 9.75 m2, exactly twice the 4.88 m2 outline.
The solid's top and bottom Faces were both counted as floor, so a solid double-counts iCFA
silently, besides the six projected wall findings.

**W-046** · 2 · feature · medium
After Create Space nothing shows in the viewport; the Space appears only when a Colour-by mode is
on.
Expected: Spaces visible by default, for example a "Show Spaces" check in Zones > Spaces, on by
default. Users who want them off can also use Tags.
Note (Claude): `docs/PRODUCT.md` says Space labels show whether or not a mode is on; none were
visible here, and all label options read false.

**W-047** · 2 · friction · low
Column header icons (Colour by, the ... menu) sit left in some columns (Name) and right in others
(Supply, Extract, Transfer, numeric columns), in both Faces and Spaces views. Make them consistent.
Padding around the highlighted icon needs cleanup (same as W-026).

**W-048** · 2 · good · low
All nine Level-01 Spaces made with the floor-outline method (Entry, two Closets, Mech Room,
Kitchen, Living Room, Den, Bathroom, Stair at weighting factor 0). Floor-01: 67.66 m2 floor,
63.69 m2 weighted, 169.16 m3.

**W-049** · 2 · friction · medium
The hierarchy row "Segment" (Floor Segment) is a confusing word for users.
Expected: label it "Floor".

**W-050** · 2 · friction · medium
Height shows on the Space row (greyed) but can only be set on the Volume row. Weighting factor,
by contrast, shows only on the Segment row where it is set.
Expected: Height shown only where it can be edited (the Volume row), as Weighting factor is.

**W-051** · 2 · friction · low (Claude's observation)
Spaces list in creation order, not by number: 108 Closet sits between 103 and 104.

**W-052** · 2 · friction · high
All six Level-02 Spaces made (200 Open to Below at factor 0, 201 Bedroom, 202 Bathroom,
203 Landing, 204 Bedroom, 205 Closet). Floor-02: 67.66 m2 floor, 48.11 m2 weighted.
Spaces cannot be seen once their Zone is closed: they sit inside the Zone Group, behind its opaque
Faces. Locate and Open from the panel work, but closing the Zone hides them again.
Expected: put Space floors on their own tag (02_SPACES) and toggle them. That cannot work now:
hiding the Zone's tag hides everything nested in it, Spaces included, and the Zone's Faces still
cover them when it is shown.
Note (Claude): a consequence of nesting Spaces inside the Zone Group. Strengthens W-036 option A
(Spaces outside the Zone, hosted by reference) and W-046 (Spaces visible by default).

**W-053** · 2 · good · low
Airflows entered per Space in the Spaces table (Ed switched to IP; cfm, ft2, ft3 convert cleanly).
Editing works well.

**W-054** · 2 · bug · medium
Each Zone carries a warning that supply and extract differ by more than 10 percent (Floor-01:
50 supply, 75 extract; Floor-02: 50, 25). Ed: the balance check belongs per ERV, not per Zone. Two
Zones served by one ERV can each be unbalanced while the ERV is balanced, as here (100 and 100).
Expected: remove the per-Zone check from this view. When Systems lands, a planned Zones /
Ventilation view groups Zones by ERV, and the check goes there.

Stage 2 checkpoint: `_checkpoints/02_spaces.skp` (15 Spaces, airflows set; agent read: every Space
`user_specified`, supply 4 x 25 cfm, extract 50 + 3 x 25 cfm).

### Stage 3: Assemblies and Materials

**W-055** · 3 · agent-access · high (Claude's observation)
Ed saved the model under a new name (Save As `03_Spaces.skp`). The agent token was bound with
"This Model only" to `02_Working.skp`, so every call now refuses `session.unknown` and `discover`
returns an empty session list with no reason. The binding is by file path, so the normal habit of
saving stage copies (Save As) silently cuts the agent off.
Expected: discover says why no session is visible ("this token is bound to 02_Working.skp; the
open Model is 03_Spaces.skp"), and the binding either follows the document through Save As or the
dialog warns at issue time that Save As ends access.

**W-056** · 3 · good · low
Ed built the Wall Assembly's geometry first (six Layers, stud and cavity Layer-Segments, 16.5 in
total) before any Materials. Building the section works well.

**W-057** · 3 · friction · low
Hover highlighting of Layer-Segments flickers ("strobes") as the pointer moves across the section.
Expected: a short hover delay or ease, about 100 to 200 ms.

**W-058** · 3 · friction · medium
The Layer tools popover (Add outside, Add inside, Move outward, Move inward, Air barrier, Delete
Layer) needs polish: a stack of full-width text buttons. Consider icons and consolidating
(for example add/move as paired icon controls).

**W-059** · 3 · bug · medium
"About this Assembly's U-value" repeats itself: "One or more segments do not have a material
assignment" twice, then "A Layer-Segment has no Material" once per Layer-Segment (about 14 lines).
Expected: one deduplicated message with a count, for example "14 Layer-Segments have no
Material", ideally with a way to jump to them.

**W-060** · 3 · question · medium
Ventilated cladding is a checkbox under Advanced. Ed: present it as a choice in the Assembly's
boundary dropdown beside Outdoors, Ground and the rest, even if it stays a separate flag in data.
Note (Claude): `AGENTS.md` says boundary conditions are honeybee's and no third vocabulary is
coined. A UI choice that maps to Outdoors plus the ventilated flag keeps the data honeybee's; the
synthesis should say so explicitly.

**W-061** · 3 · friction · low (Claude's observation)
The selection bar reads "Layer 4 · Layer-Segment 3". "Layer-Segment" is the same kind of jargon Ed
flagged as "Segment" in W-049.

**W-062** · 3 · good · low
Library > Materials empty state (inbox icon, "No Material records yet") reads well.

**W-063** · 3 · friction · medium
The empty state says "Choose + New Material", but the button is at the top right. Expected: a
"+ New Material" button in the empty state itself, under the icon. Applies to every empty table.

**W-064** · 3 · feature · high
New Material takes conductivity only. Datasheets report thermal values in many forms.
Expected: an input-form dropdown beside the value (R per inch as the default in IP, conductivity,
and other common forms), with the app converting. Same need wherever thermal properties are typed.

**W-065** · 3 · feature · low
New Material has no colour field. Expected: a colour picker in the New Material dialog (the table
already has a Color column).

**W-066** · 3 · friction · medium (Claude's observation)
New Material pre-fills density 1 lb/ft3, specific heat 1 Btu/(lb F) and emissivity 1. These are
placeholders that look like data; a user who only types conductivity saves nonsense values. Leave
them blank, or use category-based defaults the user can see are defaults.

**W-067** · 3 · friction · medium (Claude's observation)
Ed was on the Wall Assembly when he needed Materials; creating one meant leaving for the Library tab.
The Assembly page's Material Library sidebar offers copying from a library but no "New Material".

**W-068** · 3 · bug · medium
Assemblies tab, Material Library sidebar: Plywood shows a white square beside its name, though its
colour is set (agent read: `#e6c99c`, tan; the section drawing shows it tan).
Note (Claude): `features/assemblies/editor.js:52` appends a colour swatch after the name; the white
square at the left may be the row's checkbox rather than the swatch, and the swatch itself does not
show. Either way the user reads a wrong colour. Not yet tested.
Also seen: Plywood saved at 0.069 Btu/(h ft F) (0.119 W/mK) with density 1 lb/ft3, specific heat
1 Btu/(lb F) and emissivity 1, the placeholder values of W-066.

**W-069** · 3 · good · low
Five Materials made (2.5" Air Cavity, Denspack Cellulose, GWB, Plywood, Softwood Lumber) and the
Wall Assembly filled by drag from the sidebar. Agent read: export ready, no findings,
R 8.22 m2K/W construction, U 0.119 W/m2K with films (Ed: "works well").

**W-070** · 3 · friction · medium
Material Library sidebar with "In this file" selected shows "These records are in the table.
Choose a library above to copy records from it." Ed finds it confusing.
Expected: label the choice "Materials in this file" and drop the note.

**W-071** · 3 · friction · low
"Library setup..." link under the sidebar title. Expected: a gear icon inline with the "Material
Library" title.

**W-072** · 3 · bug · low
The sidebar title has a down chevron, but the sidebar collapses to the right. The icon should match
the motion.

**W-073** · 3 · friction · low (Claude's observation)
In IP both U-values show 0.021 Btu/(h ft2 F), so the films' effect is invisible (agent: 0.1192 vs
0.1217 W/m2K). IP U-values need one more significant figure.

**W-074** · 3 · question · medium (Claude's observation)
All five Materials carry density 1 lb/ft3 and specific heat 1 Btu/(lb F): the W-066 placeholders,
now in every record. Check in Stage 7 what the export writes for them and whether METr or WUFI
consumers use those values.
Also: the Assemblies sidebar rows show no colour swatches at all (all five), consistent with W-068.

**W-075** · 3 · bug · medium
Library > Materials, Actions column: clicking the use-count badge ("1") opens a "Used by
Assemblies" popover that is clipped inside the table (left edge and content cut off, overlapping
rows). The popover should escape the table's overflow and sit fully on screen.
Also: the badge has no tooltip; Ed had to guess it means "used in N Assemblies".

**W-076** · 3 · friction · medium
Inside an open Zone, right-click on Faces shows one "Classify faces" submenu mixing Face types
(Wall, Roof or ceiling, Floor), boundaries (Outdoors, Ground, To neighbour), Assembly (Assembly:
Wall, Clear assembly) and New attached zone.
Expected: three items: Set Face Type (Wall, Floor, ...), Set Face Exposure (Outdoors, Ground,
...), Set Face Assembly (lists the Assemblies available, plus Clear).
Note (Claude): "Classify faces" and "Repair" are top-level context-menu items, beside the
"PH-Composer" submenu; PH-Composer actions are split across three places in one menu. Also "Face
Exposure" (Ed's word) vs the panel's "Boundary" column: pick one user-facing term; the data stays
honeybee's boundary condition.

**W-077** · 3 · feature · medium
The Classify faces submenu does not show the selected Face's current values. Expected: a check mark
on the current Face type, boundary and Assembly.
Note (Claude): SketchUp menu items support this through a validation proc returning `MF_CHECKED`.
A mixed selection needs a rule (no check, or check only values all selected Faces share).

**W-078** · 3 · bug · medium
With View > Component Edit > Hide Rest of Model on, entering Floor-02 hides Floor-01's geometry,
but the Colour-by overlay still draws Floor-01's Faces (translucent fill below the open Zone).
Expected: the overlay follows SketchUp's view state; it draws nothing for geometry SketchUp is not
showing. Same family as W-031 (section planes) and W-033 (hidden Faces, which does work).
Note (Claude): the state is readable as `rendering_options["InactiveHidden"]` (and
`"InstanceHidden"` for Hide Similar Components); the overlay should skip Faces outside the active
path while it is set, and redraw when it changes.

**W-079** · 3 · good · low
Paint Assembly from the Assembly column menu (Zones > Faces, ... > Show > paint icon beside Wall)
works as expected. Faces with no Assembly draw hatched in the viewport, which reads well.

**W-080** · 3 · friction · medium
Paint for an Assembly is offered in the Zones > Faces Assembly column menu and in the Assemblies
table, but not in the Assembly detail view, where the user is when they finish building one.
Expected: a Paint action in the Assembly detail view too.

**W-081** · 3 · friction · low (Claude's observation)
With the panel narrowed, the Faces table scrolls horizontally and the Level header is clipped to
"evel" while the Level chips also sit cut at the left. Clipped header text should not show.

**W-082** · 3 · friction · high
Assemblies table, row action with tooltip "Replace Wall on assigned Faces" opens a dialog titled
"Replace and delete Wall", listing "4 Faces: Floor-02 · Wall [20169], ..." and a "Replacement
assembly" dropdown. Ed could not tell what it does.
What it does (Claude): moves every Face that uses this Assembly to the chosen replacement, then
deletes this Assembly. Problems:
- tooltip and title disagree (replace vs replace-and-delete); the delete is the surprise;
- the Face list shows internal ids in brackets, meaningless to a user;
- with only one Assembly in the file the dropdown has nothing to choose: a dead end that does not
  say so;
- the icon gives no hint of its purpose among five unlabelled row icons.
Expected: decide whether this is "Delete (reassign its Faces first)" or "Replace on Faces"; name
and explain it in one sentence; show Faces as Zone and Face name with a count; disable with a
reason when no replacement exists.

**W-083** · 3 · bug · medium
Clicking Paint on a row in the Assemblies table switches the panel to Zones > Faces.
Expected: stay on the Assemblies table; painting happens in the viewport, and the panel should not
navigate away from where the user started it.

**W-084** · 3 · question · high
All envelope Faces now have Assemblies (Wall, a roof Assembly, a ground-floor Assembly). The two
interior Faces (the Surface pair between Floor-01 and Floor-02) have none, and Ed does not intend
to model them in the PH model. Agent read: `zones.faces.export_preflight` blocks export with
`construction.missing` on exactly those two Faces.
Ed: honeybee-energy has generic interior constructions (Generic Interior Wall, Ceiling, Floor);
should PH-Composer offer them so the HBJSON is valid?
Note (Claude): the HBJSON itself does not need an explicit construction; honeybee-energy falls back
to its default construction set, whose interior set covers Surface Faces. The block is
PH-Composer's own rule (authored Assemblies required). Options for synthesis:
- A. Exempt Surface Faces from `construction.missing`; export them with no construction so
  honeybee's default interior set applies. No invented data.
- B. Ship generic interior Assemblies as built-in records. Conflicts with "no provider is
  privileged" unless they are plain local records the user can see and edit.
- C. A per-Face "not part of the PH envelope" flag.
Before choosing: check how PHX's METr/WUFI writers treat Surface Faces with and without a
construction (trace PHX, do not assume).
Also: `zones.export_preflight` still offers "Solve stale adjacencies" (W-034).
PHX trace (Claude, read only): `PHX/from_HBJSON/cleanup.py` (exposed-face filter, around line 160)
skips any Surface Face whose adjacent Room is in the same room group (Building Segment) before it
builds components; a Surface Face facing another Building Segment is kept with its construction.
So for this model (both Zones in Main) the pair never reaches the PH model, whatever construction
it has. This favours option A, refined: require an Assembly on a Surface Face only when its
counterpart is in a different Building Segment. Not yet confirmed by a round trip.

Stage 3 checkpoint: `_checkpoints/03_assemblies.skp` (5 Materials, Wall plus roof and ground-floor
Assemblies, all envelope Faces assigned; interior Surface pair unassigned per W-084).

### Stage 4: Window Types

**W-085** · 4 · friction · medium
Library > Frames sidebar repeats W-070, W-071 and W-072 (the "These records are in the table" note,
the "Library setup..." link, the down chevron on a right-collapsing sidebar). The same sidebar
component serves every record kind, so one fix covers all.

**W-086** · 4 · feature · medium
Ed made three Frames: Entrada Head, Entrada Jamb, Entrada Sill. Position is typed twice, once in the
name (to make it unique) and again in the Position field.
Expected: an optional auto-name built from the fields, for example
`{manufacturer}-{brand}-{position}-{operation}`, so setting the fields names the Frame.
Needs a new Brand field (Entrada, Motura, Purista), and Brand as a Group by option beside
Manufacturer.

**W-087** · 4 · friction · low (Claude's observation)
Frames table: the Color cells show empty white squares for all three (no colour set, or the same
missing-swatch issue as W-068), and the Actions column is empty on every row.

**W-088** · 4 · bug · medium
Window Types builder, ... > Dimension format: choosing a format (Decimal inches, Decimal feet,
Feet and inches, Fractional inches) changes nothing; the drawing keeps "3.28 ft x 6.92 ft".
Likely cause (Claude, read only, not tested): the dimension field declares its scope under the key
`builder` (`features/windows/editor_shared.js:6`), but `units.profile` reads `field.scope`
(`units.js:182`), so the stored per-scope format is never looked up and the system default is used.
The control writes the preference under scope `ph_composer.windows.types` correctly. The
Assemblies dimension field has the same `builder` key (`features/assemblies/editor_shared.js:6`), so
its format chooser is probably inert too; the Zones ground-depth field uses `scope` and should work.
Ed asked for a fix; held for the post-walkthrough implementation batch with a reproducing test.

**W-089** · 4 · bug · medium
Library > Glazings: typing 37 for g-value (meant 0.37) raises "g-value must be between 0 and 1"
and blocks all other work until fixed. When the row is the last in the table the message bubble is
clipped by the table's scroll area, so the user cannot read why they are blocked.
Expected: validation messages escape the table's overflow (same root as W-075's clipped popover).
Also consider accepting 37 as 37 percent, or saying "did you mean 0.37?".

**W-090** · 4 · friction · medium
Window Type > Door Installs (Psi-Install editor) needs polish:
- Cancel and Save Installs sit at the far top right, away from the work.
- The tab bar still shows Types as current; the editor is a separate mode with no breadcrumb.
- The element drawing is left-aligned; it should be centred in the canvas.
- The edge hover highlight is thick with square ends; it works but looks clunky.
- "Apply to perimeter edges" and "Copy to other Window Types" are full-width text buttons;
  consider icons.

**W-091** · 4 · question · high
Psi-Install Types shows "Model default: Missing". Ed created a "Default" record at 0.04 W/mK by hand.
Ed: a built-in model default of 0.04 W/mK (the usual Passive House default install psi) should
always apply unless the user sets another.
Note (Claude): agent read `windows.settings.get`: `default_psi_install_id: null`. The product
(`docs/PRODUCT.md`) requires an explicit model default, and `AGENTS.md` says no default ships from a
provider. A model setting that defaults to 0.04 W/mK (a value, not a library record) may satisfy
both; decide in synthesis, and say whether PHI and Phius defaults differ.

**W-092** · 4 · good · low
Window Type "Door" built (SGG Climatop One, Entrada Head/Jamb/Sill, swing left; Uw 0.736,
Uw,installed 0.861 W/m2K). Place works and lands a Window Unit on the Zone Face ("Placed Window.").

**W-093** · 4 · friction · medium
While placing, the hint "Measurements: sill=opening bottom above host base; offset=anchor inset
from nearest edge" is helpful but renders as plain text under the tabs and is easy to miss.
Expected: a more prominent treatment (a highlighted callout) while the tool is active.

**W-094** · 4 · feature · high
The Place tool does not snap or infer, so CAD linework cannot guide placement. Ed places, then uses
SketchUp Move (which snaps) to position it: two operations every time.
Expected: inference while placing (endpoints, edges, guides), as native tools do.
Note (Claude): SketchUp's Tool API supports this through `Sketchup::InputPoint` (`pick` plus
`draw`) for the cursor point; worth checking what the place tool uses now.
Also: a failed placement ("The Window outline leaves its host Face or crosses a hole. Nothing was
written.") shows only in the panel, the W-035 pattern.

**W-095** · 4 · feature · high (Ed: "the biggest UX change I want to include")
Today a Window Type must be built in the panel before it can be placed. Ed wants the reverse as a
second path: draw the opening as a rectangle with native SketchUp tools (on the Zone Face, snapping
to CAD), select it, right-click "Convert to Window Type". The new Type takes its size from the
geometry; the user then sets frames, glazing and Psi-Install in the panel. Several selected
rectangles become one mulled Window Type (grid). The original Faces are removed and replaced by a
placed Window Unit of the new Type.
Questions for synthesis (Claude):
- Host: must the rectangle lie on a Zone Face, and is the Unit placed there automatically?
- Orientation: which edge is the sill (world Z for walls; roofs and skylights need a rule)?
- Mulling: selected rectangles must be coplanar and tile a grid; how to refuse others clearly.
- Reuse: when a Type of the same size exists, offer to place it rather than create a duplicate;
  converting many same-size rectangles at once should yield one Type and many Units.
- New Type defaults: frames and glazing blank (export-blocking until set) or copied from the last
  Type used.
Note: this matches how DesignPH and Honeybee users already work (windows drawn as faces), and it
also answers W-094 (no snapping while placing) for the first placement.
Ed confirmed: this is in addition to the existing build-then-Place workflow, which stays.

**W-096** · 4 · friction · medium
"Choose top frame" lists Frames in no clear order (Entrada Jamb, Purista - Head, Purista - Sill,
Entrada Head, ...). Expected: alphabetical by default.
Note (Claude): the chooser for the Top Frame also lists Jambs and Sills. Frames carry a Position;
list those matching the slot first (or filter, with "show all" for exceptions). Ties to W-086's
Brand and auto-name.

**W-097** · 4 · good · low
Copy and paste of a placed Window Unit makes new Units (Type-A, four Units across both Zones). The
Schedule view lists Types, Units, Zone and host Face clearly.

**W-098** · 4 · bug · high
A pasted Unit can land outside its Zone and off any Face. Schedule shows it as "Unhosted" (Window 4,
Floor-02) with repair actions, but nothing stopped it.
Expected: a control so a Unit cannot end up unhosted by accident.
Note (Claude): SketchUp observers cannot cancel a paste or move cleanly; undoing from an observer
breaks native Undo (`context/TECH_STACK.md` transaction rules). Options for synthesis: snap the
Unit back to the nearest Face of its Zone, refuse with a SketchUp-side notice and one-click Undo,
or keep detection but make it loud in the viewport (the panel-only flag is easy to miss, W-035).
Agent read after Ed's cleanup: four Units, all hosted, no findings.

**W-099** · 4 · feature · medium
Window Unit names ("Window 1") are not editable in the Schedule, and SketchUp's Entity Info
Instance field is empty and unconnected.
Expected: set the Unit name in either place, kept in sync both ways (the Unit name is the
component instance name).
Note (Claude): numbering restarts per Type, so the model has two "Window 1" Units (Door and
Type-A). Names should be unique model-wide, or the Schedule should show Type plus name wherever a
Unit is referenced.

**W-100** · 4 · feature · medium
Selecting a Window Unit in SketchUp gives no sign of it in the Schedule, and once placed there is no
direct way to see a Unit's Type except Zones > Faces with Colour by Window Type.
Expected: the Schedule highlights (subtly) the row of the selected Unit(s), and scrolls to it.
Note (Claude): the Zones Faces table already follows the SketchUp selection; the Schedule should
too. The only native clue today is Entity Info's Definition name ("PhComposer_Window_Type-C#1").
Also: Schedule lists Types in creation order (Door, Type-B, Type-A, Type-C), not by name (W-051).

**W-101** · 4 · friction · high
Type-C-2: Ed added a mulled neighbour element, then eyedropped the existing element and painted
the new one. Refused: "Installation topology differs. Use the staged Installs workflow to review
the mapping. Nothing was written." Meaningless to a user.
What it means (Claude, from `features/windows/types/grid_operations.rb`, `paste`): paste copies
glazing, all four frames, operation and the per-edge Psi-Install assignments together. If either
element has Psi-Installs set, it requires both elements to have the same edges on the window's
outer perimeter. The source element's right edge is now the shared mullion, while the target's left
edge is; the per-side installs would land on the wrong sides, so the whole paste is refused.
Operation is not the cause; Psi-Install is.
Expected: paste glazing, frames and operation regardless; copy Psi-Installs only to edges that
match (perimeter to perimeter), leaving the mullion edge unassigned, and say so in plain words
("Copied glazing, frames and operation. Psi-Install set on 3 outer edges; the shared edge has
none."). Never refuse the whole paste for the install part. Rewrite the message either way.

**W-102** · 4 · bug · high
The W-101 warning toast cannot be dismissed: its close (x) does nothing, so it stays over the page.
Expected: every notice closes on its x (and on Escape). Check whether this toast differs from the
ones that do close (W-089's, W-040's).
W-101 decision (Ed): paste what can be pasted, skip what cannot, and show no error.

**W-103** · 4 · bug · medium
Window Type builder: element SD1.1 with Operation Slide, direction Right, draws the swing triangle
(dashed lines to the hinge side) instead of a slide arrow. Each operation needs its own symbol:
slide as an arrow in the slide direction.
Also seen (Claude): the Right Frame row (the shared mullion edge) shows psi-install 0 while the
other edges show a dash; check that 0 is intended for a mullion and say so in the table.

**W-104** · 4 · good · low (Claude's observation)
Agent check at end of Stage 4: 9 Window Types, 16 Units, all hosted, no findings, window export
preflight clean; Type-E (two-element slider) fully assigned. `windows.types.all` refused as 37 KB
over the 24 KB reply limit with "Ask for less: a smaller page, fewer fields"; `types.list` with
`fields` and `limit` then worked. The refusal and the bounded list made recovery easy.

Stage 4 checkpoint: `_checkpoints/04_windows.skp` (Ed's own copy: `05_Windows.skp`).

### Stage 5: Thermal Bridges

**W-105** · 5 · good · low
Thermal Bridge Types Eave (-0.041 Btu/(h ft F), Ambient) and Footing (-0.036, Perimeter) made in
the Types table. Colour by Window Type in the viewport (Stage 4) reads clearly.

**W-106** · 5 · friction · medium
Right-click an Edge > Thermal bridge lists the Types (Eave, Footing) plus "Assign by clicking...".
Ed: "what does 'assign by clicking' mean?" The same label is a button in the panel.
What it does (Claude): starts a viewport tool; you choose a Type, then click Edges one after
another to assign it, each click one Undo step (`docs/PRODUCT.md`).
Expected: a label that says what happens, for example "Pick Edges with a tool..." or
"Assign Eave by clicking Edges...", and a status-bar hint once the tool runs.
Also (Claude): Thermal bridge sits as a top-level context-menu item beside "Place Windows", while
Make Zone and Create Space live under a "PH-Composer" submenu (W-076).

**W-107** · 5 · feature · high
No way to see which Edges carry a Thermal Bridge. Ed: add Colour by to Thermal Bridges, by Name
(Type) and by Group.
Note (Claude): a "Thermal bridges" Colour-by mode by Type exists and is registered
(`features/thermal_bridges/colour_modes.rb`; agent `colour_by.state` lists
`ph_composer.thermal_bridges.by_type`), and `docs/PRODUCT.md` promises it. But the Thermal Bridges
tab has no palette icon on any column (`html/features/thermal_bridges/*.js` never reaches Colour by),
so a user cannot turn it on; only an agent can. A by-Group mode does not exist. Fix: palette icons
on the Types table's Name and Group columns (and the Schedule), plus the Group mode.
Ed found it: running Assign by clicking switches the viewport to the Thermal bridges by-Type view,
which reads well. So the view exists but is reachable only as a side effect of the tool. Expected:
enter it directly (palette icons on Name and Group, as above).

**W-108** · 5 · question · high
Eave and Footing assigned. Next case: the intermediate floor-to-exterior-wall junction (detail
1/A-903), which by definition lies where Floor-01 and Floor-02 meet. Each Zone has its own
coincident Edge there. Ed: assign in one Zone, or both? What if both are assigned? Should exact
duplicates (same Type, same Edge geometry) be de-duplicated?
Current behaviour (Claude, from `features/thermal_bridges/codes.rb` and the API reference):
coincident assigned Edges in two Zones raise the warning `thermal_bridge.counted_twice` ("so the
bridge is counted twice") and both still export; export writes each run on its Zone's
Building-Segment. Assigning in one Zone only works today with no warning.
Recommendation for synthesis: a linear thermal bridge belongs to the Building-Segment (that is
where export puts it), so de-duplicate by Building-Segment, Type and Edge geometry:
- same Type on coincident Edges, same Building-Segment: count once, list once in the Schedule
  noting both Zones, no warning;
- different Types on coincident Edges: a finding (conflict), user chooses;
- coincident Edges in Zones of different Building-Segments: a finding asking which segment owns
  the bridge (or split by rule).
Then the user can assign from either Zone, or both, without thinking about it.

**W-109** · 5 · good · low (Claude's observation)
End of Stage 5, agent read: three Thermal Bridge Types (Eave, Footing, Floor-to-Wall), three runs
of four Edges each (39.0 m apiece), total -4.52 W/K, thermal-bridge preflight clean. Ed assigned
Floor-to-Wall in Floor-02 only, so the both-Zones double-count baseline for W-108 was not
exercised.

Stage 5 checkpoint: `_checkpoints/05_thermal_bridges.skp` (Ed's own copy: `06_Thermal_Bridges.skp`).

### Stage 6: Location, north, shading, systems

**W-110** · 6 · feature · high
Not testable: location and climate, true north / orientation, shading surfaces, and systems
(ERV, heat pumps, hot water). None is implemented; location, climate and sun path are Phase 5
PRDs, systems are Phase 4. Recorded so the synthesis lists them as the gaps between this build and
a complete Phius model of the tutorial house.

### Stage 7: Export

**W-111** · 7 · question · high (Claude's observation)
Whole-model `export_preflight` (agent): export is blocked only by `construction.missing` on the two
interior Surface Faces (W-084). Also present: two `space.airflow_imbalance` warnings (W-054) and
the repair "Solve stale adjacencies before export" still offered (W-034). So the HBJSON could not
be exported as modelled; an end-to-end export and comparison against the reference models needs
W-084 settled, or a temporary Assembly on the interior pair.
