# Programs prototype

DATE: 2026-11-14
STATUS: Draft for Ed's review. Clickable mockup, not a screen; no panel code.
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
| 1. Single-family home, five Zones, one dwelling | Check every Zone, Dwelling: One shared dwelling, then bedrooms on the bedroom rows. Click the House chip | `j1-start` (`journey=1`), `j1-dwelling` (`journey=1&do=shared,beds,bubble`), `j1-default-program` (`journey=1&do=shared,beds,pdefault`) |
| 2. Apartments, one Zone each | Check every Zone, Dwelling: One dwelling each | `j2-checked` (`journey=2&do=checkall`), `j2-dwellings` (`journey=2&do=each,beds`) |
| 3. Apartments plus corridors, lobby, stair, office, gym | Apartments as in 2; pick Phius Multifamily Programs for the rest from the Program choice | `j3-corridors-checked` (`journey=3&do=each,beds,checkcorr`), `j3-common-areas` and `-420` (`journey=3&do=each,beds,common`) |
| 4. Non-residential school | Unassigned Zones are flagged; assign from Phius Non-Residential, or browse the library sidebar | `j4-start` (`journey=4`), `j4-assigned` (`journey=4&do=school`), `j4-library` (`journey=4&do=school,libnr`) |
| 5. Custom lab programs | Programs tab, + on the rail, set loads, open a schedule chip | `j5-program` and `-420` (`journey=5&do=custom`), `j5-schedule` (`journey=5&do=custom,customsched`) |
| Equipment Sets | Programs tab, Equipment Sets | `equipment-sets` (`journey=1&do=sets`) |

## What the prototype proposes

- **Programs tab** with Programs, Schedules and Equipment Sets subtabs, laid out like Window Types:
  a rail of records, the editor, and for Programs a Program Library sidebar whose sources are
  Phius Multifamily, Phius Non-Residential and honeybee-energy standards (not added).
- **A Program** is eight load cards. A derived value shows its rule instead of a number (the
  residential default's Occupancy, Lighting and Hot water). Values the library lacks are amber "?".
  Infiltration says when the Segment's test result replaces it; Setpoint says it sets the Segment.
- **A Schedule** is the PH form (start, end, fraction while operating and otherwise, days per
  week, weeks per year) over a 24-hour strip and a week row. The hourly editor is a disabled
  button marked as planned.
- **Zones → Programs**, a third Zone view: one row per Zone under a Building Segment heading row
  that holds the Phius category, the airtightness test result and the set points derived from the
  Programs, with summed bedrooms, occupants, people, lighting and ventilation. Per row: Program,
  Dwelling, Bedrooms, Occupants, Equipment Set, both floor areas, and the absolute loads. An
  unassigned Zone shows the residential default in italics.
- **The selection bar** assigns Program, Dwelling (one shared, one each, not a dwelling, add to an
  existing one) and Equipment Set to the checked Zones. Choosing a library Program copies it into
  the file and assigns it in one step.

Two labels are placeholders, not proposals: apartments inherit "Phius single-family default" as
their Equipment Set (honeybee-ph also has a multifamily set), and the Equipment Sets subtitle says one
Set serves a dwelling while Q4a-21 is open.

## Questions the prototype raised

Recorded as Q4a-19 to Q4a-25 in [DECISIONS.md](../DECISIONS.md#questions-the-prototype-raised).
The new words on screen (Program, Schedule, Equipment Set, Dwelling) enter
`context/UBIQUITOUS_LANGUAGE.md` with the PRD.
