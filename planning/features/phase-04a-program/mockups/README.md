# Programs prototype

DATE: 2026-11-14
STATUS: In review. First review 2026-11-14 added the Single dwelling switch and library files; 2026-11-15 added Building Segment management. Clickable mockup, not a screen; no panel code.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

`programs.html` links the panel's real stylesheets and reuses its class names; a throwaway script
holds a synthetic model per journey. Phius program values come from honeybee-ph's
`PHIUS_programs.py`; residential schedule shapes and all derived numbers are illustrative.

Open it from the worktree in a browser (`open -a Vivaldi programs.html`) or through the UI preview
server. The dark strip at the top picks a journey and says what to try; Reset restarts it.
`?journey=N` opens one, `&do=` replays the steps each PNG shows (listed below). PNGs are 1280 × 800, and 420 × 732 where marked.

| Journey | What to try | PNGs |
| --- | --- | --- |
| 1. Single-family home, five Zones, one dwelling | Single dwelling is on: type the bedrooms on the Building Segment row. Click a locked cell, Open settings, uncheck Single dwelling, then click the House chip | `j1-start` (`journey=1`), `j1-bedrooms` (`journey=1&do=house3`), `j1-unlocked` (`journey=1&do=house3,unsingle,bubble`), `j1-default-program` (`journey=1&do=pdefault`) |
| 2. Apartments, one Zone each | Check every Zone, Dwelling: One dwelling each. Then check Single dwelling in the Building's settings to see its confirmation | `j2-checked` (`journey=2&do=checkall`), `j2-dwellings` (`journey=2&do=each,beds`), `j2-single-confirm` (`journey=2&do=each,beds,trysingle`) |
| 3. Apartments plus corridors, lobby, stair, office, gym | Apartments as in 2; pick Phius Multifamily Programs for the rest from the Program choice | `j3-corridors-checked` (`journey=3&do=each,beds,checkcorr`), `j3-common-areas` and `-420` (`journey=3&do=each,beds,common`) |
| Building Segments (journey 3, then 1) | Check the Bike shed, Building Segment: No Building Segment or New Building Segment. Hover a Segment row: Settings and Delete appear in its Actions cell; settings is where it is renamed | `j3-no-segment` (`…,common,moveshed`), `j3-move-segment` (`…,common,checkshed`), `j3-new-segment` (`…,common,newseg`), `j3-segment-settings` (`…,common,segsettings`), `j3-delete-segment` (`…,common,newseg,trydelete`), `j1-segment-settings` (`journey=1&do=house3,segsettings`), `j1-adu` (`journey=1&do=house3,adu`), `j1-lock-bubble` (`journey=1&do=house3,lockinfo`), `j1-segment-actions` (the ADU row hovered) |
| 4. Non-residential school | Unassigned Zones are flagged; assign from Phius Non-Residential, or browse the library sidebar | `j4-start` (`journey=4`), `j4-assigned` (`journey=4&do=school`), `j4-library` (`journey=4&do=school,libnr`), `j4-long-name` (`journey=4&do=school,longname`) |
| 5. Custom lab programs | Programs tab, + on the rail, set loads, open a schedule chip | `j5-program` and `-420` (`journey=5&do=custom`), `j5-schedule` (`journey=5&do=custom,customsched`) |
| Equipment Sets | Programs tab, Equipment Sets | `equipment-sets` (`journey=1&do=sets`) |
| Program cards and the ventilation Schedule | Open and close the load cards; Schedules, SFH ventilation, change the hours | `j4-program-cards` (`journey=4&do=school,libnr,cards`), `j1-vent-schedule` (`journey=1&do=ventsched`) |
| Zones → Spaces (journey 1, then 3) | Zones, Spaces subtab. Type a Supply, Extract or Transfer rate on a Space and its Zone turns detailed; hover the Zone for From Program. Then compare Zones → Programs' Ventilation | `j1-spaces` (`journey=1&do=house3,spaces`), `j1-spaces-cascade` (`…,spaces,cascade`), `j3-spaces` (`journey=3&do=each,beds,common,spaces,cascade`) |

## What the prototype proposes

- **Programs tab** with Programs, Schedules and Equipment Sets subtabs. Each is the editor and one
  right sidebar, as in the Assembly and Window Type Builders (Q4a-35): no left rail; the source
  select starts with "Programs in this file" (or Schedules, Equipment Sets) and then the added
  library files, Phius Multifamily and Phius Non-Residential from ph-composer-standards, with
  honeybee-energy standards shown as not added (Q4a-20). Choosing a record in this file opens it;
  a library row ends in a plus that copies it, or a check when it is already in this file.
  Journeys 3 and 4 assume both Phius files were added.
- **A Program** is a column of full-width accordion cards (Q4a-34, `j4-program-cards`): closed,
  each shows its values and schedule on one line; open, its values on the left and its Schedules on
  the right. Order: Occupancy, Lighting, Ventilation, Electric equipment, Setpoint, Infiltration,
  then Gas equipment and Hot water under "EnergyPlus only". A derived value shows its rule (the
  residential default's Occupancy, Lighting and Hot water); the lighting rule exposes its
  high-efficacy fraction. Library Programs arrive complete, with the slots the Phius data lacks
  filled from their 2019 base program and labelled (Q4a-25).
- **A Schedule** is the PH form (start, end, fraction while operating and otherwise, days per
  week, weeks per year) over a 24-hour strip and a week row. A **ventilation** Schedule is four
  rows, high, standard, basic and minimum, each hours per day and a fraction, totalling 24 h
  (Q4a-33, `j1-vent-schedule`). The hourly editor is a disabled button marked as planned.
- **Single dwelling**, a setting of each Building Segment, switched in its settings dialog (Q4a-26
  as revised by BS-3). The heading shows a "Single dwelling" tag only where it is on. Clicking a
  locked cell or the tag opens a bubble explaining the lock with one **Open settings**
  button (`j1-lock-bubble`). When on, that Segment's Zones are one dwelling, named for the Segment, with the
  residential default. A new Model's one Segment has it on (Q4a-27). Its rows are locked and show
  their values muted; its heading row takes the bedrooms, occupants (Phius rule when empty) and the
  Equipment Set. Switching it off keeps everything it set as ordinary assignments, with the counts on the
  dwelling. Checking it over per-Zone assignments opens a confirmation naming what gives way in
  that Segment. Moving a Zone into a Single dwelling Segment joins its dwelling. `j1-adu` shows a
  house and an ADU as two single-dwelling Segments.
- **Building Segments** ([PRD](../building-segments/PRD.md), BS-1 to BS-6 answered). The
  heading takes two lines: the name alone on the first (a long name truncates, full name in its
  tooltip, `j4-long-name`), with a findings flag; then the Default and Single dwelling tags where
  they apply (no Zone count or category subtitle). Settings and Delete sit in the row's Actions cell, revealed on hover as in
  Geometry and Spaces (`j1-segment-actions`); Delete is disabled on the last Segment, and the name is
  edited in settings.
  Airtightness, category and certification moved into the Building Segment settings dialog. The
  selection bar moves checked Zones to a Segment, a new one (named, then renamed in place) or No
  Building Segment, a muted last group left out of export. Deleting a used Segment asks where its
  Zones go. An empty Segment carries no flag: export checks it (BS-2). Geometry and Spaces get
  the same heading row (BS-1); only Programs is mocked.
- **Zones → Programs**, a third Zone view: one row per Zone under a Building Segment heading row
  with summed bedrooms, occupants, people, lighting and ventilation. Per row: Program,
  Dwelling, Bedrooms, Occupants, Equipment Set, both floor areas, and the absolute loads. An
  unassigned Zone shows the residential default in italics.
- **Zones → Spaces** ([ventilation research](../research/ventilation.md)): Building Segment, Zone
  and Space rows with floor area, iCFA, net volume and Supply, Extract and Transfer, as the shipping
  view has them. Airflow cells read **By Program** until a rate is entered. Typing any rate switches
  the Zone to detailed airflows (Q4a-29, Q4a-30): a notice says its other Spaces export 0, their
  blanks read 0, and From Program in the Zone's Actions cell clears every rate. Zone sums show a dash
  while By Program. Transfer's header says it reaches PHPP only (F4a-27). A Zone with no Spaces shows
  the export warning (Q4a-32). In Zones → Programs, the Ventilation column follows: the Program's
  flow, or the detailed sums (the larger of supply and extract), with the source in its tooltip.
- **The Dwelling cell** opens a bubble anchored to it: first the Zone's dwelling (an existing
  one, New dwelling, or Not a dwelling), then that dwelling's units, Zones, bedrooms, occupants and
  iCFA. A "None" cell opens the same chooser (`j1-unlocked` shows it on House).
- **The selection bar** assigns Program, Dwelling (one shared, one each, not a dwelling, add to an
  existing one) and Equipment Set to the checked Zones. Choosing a library Program copies it into
  the file and assigns it in one step.

Two labels are placeholders, not proposals: apartments inherit "Phius single-family default" as
their Equipment Set (honeybee-ph also has a multifamily set), and the Equipment Sets subtitle says one
Set serves a dwelling while Q4a-21 is open.

## Questions the prototype raised

Recorded as Q4a-19 to Q4a-28 in [DECISIONS.md](../DECISIONS.md#questions-the-prototype-raised);
Q4a-19, Q4a-20, Q4a-26, Q4a-27 and Q4a-28 are [answered](../DECISIONS.md#answered).
The new words on screen (Program, Schedule, Equipment Set, Dwelling) enter
`context/UBIQUITOUS_LANGUAGE.md` with the PRD.
