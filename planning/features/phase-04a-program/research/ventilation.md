# Research: Zone ventilation and Space airflows

DATE: 2026-11-15
STATUS: Research complete; proposal for review (Q4a-29 to Q4a-32). Read from source, not run.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Ed's desired behaviour (2026-11-15):

1. The Zone's Program carries a Ventilation load, applied to the Zone by default.
2. A user *may* enter airflows per Space in Zones → Spaces. Entered values override the Program's
   airflow for that Space on export to WUFI-Passive and METr.
3. Without Space airflows, the Program's airflow applies.
4. The Program's ventilation schedule applies in every case.

**PHX already does all four.** PH-Composer already writes rule 2 correctly. What Phase 4a adds is
the Program's Ventilation load on every exported Room, and a Spaces view that shows what each Space
will actually get. Baseline: honeybee-ph 1.33.65 (pinned wheel, Space fields checked against it),
honeybee-energy 1.123.23 (pinned wheel), PHX 1.59.1 (local checkout), honeybee_grasshopper_ph
(local checkout).

## The versions, layer by layer

| Layer | Where | What it holds or does |
| --- | --- | --- |
| honeybee-energy `Ventilation` | the Room's Program (`room.properties.energy.ventilation`) | Four terms: per person, per m² floor, per zone (m³/s) and ACH, plus `method` (Sum or Max) and a schedule |
| honeybee-ph `SpacePhProperties` | `honeybee_ph/properties/space.py` | `_v_sup`, `_v_eta`, `_v_tran` in m³/s, each `None` by default. `has_ventilation_flow_rates` is true when any is non-zero; `honeybee_flow_rate` is the largest of the three. Marked in the source as a temporary override |
| honeybee-energy-ph `SpaceEnergyProperties` | `honeybee_energy_ph/properties/space.py` | Only `id_num`. No ventilation data |
| Grasshopper: Create Space PH Ventilation | `gh_compo_io/space_create_vent_rates.py` | Stores an unset rate as `0.0`, not `None`, so a Space given only supply also carries extract 0 and transfer 0 |
| Grasshopper: hosting Spaces in Rooms | `make_spaces/make_space.py`, `add_spaces_to_honeybee_rooms` | For each Space with flows, rewrites the Room's honeybee Ventilation with `absolute_ventilation(existing per-zone + the Space's largest rate)`. That call zeroes per person, per area and ACH and keeps the schedule. This is for EnergyPlus, where the Space overrides would otherwise not count |
| PHX `create_rooms.create_room_from_space` | `PHX/from_HBJSON/create_rooms.py` | Per Space: schedule from the host Room's Ventilation (a constant default pattern and zero flow when the Room has none). Flow: the Room's four terms **summed** (`method` ignored), times the Space's share of the Room's **unweighted** Space floor area, in m³/h, for both supply and extract. Then each `_v_*` that is not `None` overrides its own term: supply, extract, transfer separately |
| PHX writers | `to_WUFI_XML/xml_schemas.py` `_PhxSpace`; `to_METr_JSON/metr_schemas.py` | WUFI writes `DesignVolumeFlowRateSupply`, `DesignVolumeFlowRateExhaust` and `IdentNrUtilizationPatternVent` per Space; METr writes `dVFrSup` and `dVFrEx`. **Neither writes transfer air.** Only the PHPP writer reads `flow_transfer` (`PHPP/phpp_model/vent_space.py`) |
| PH-Composer today | `features/spaces/schema.rb`, `scan/metrics.rb`, `python/.../space_sections.py` | Stores `v_sup_m3h`, `v_eta_m3h`, `v_tran_m3h`. **Any-set rule:** a Space with none set "inherits" and writes `None` for all three; a Space with any set is "user specified" and writes all three, 0 for an unset one. The Spaces view shows "Zone" as the placeholder on an inheriting Space and hides a Zone's airflow sums while any of its Spaces inherits. No Program exists yet, so no Room carries a Ventilation load |

## Findings

| Id | Finding |
| --- | --- |
| F4a-24 | PHX overrides per term; PH-Composer and the Grasshopper component decide per Space. Writing all three once any is set (PH-Composer's any-set rule) means PHX never mixes a Program supply with a user extract on one Space |
| F4a-25 | **In a Zone with some Spaces overridden, the others still get their floor share of the whole Program flow, not what is left.** The Zone's exported total is the overrides plus the inheriting shares, and can exceed or fall short of the Program total |
| F4a-26 | The schedule always comes from the Room's Ventilation load (rule 4 holds today). A Room with no Ventilation load exports zero flow on a constant default pattern, even where its Spaces carry overrides they keep |
| F4a-27 | Transfer air reaches PHPP only. WUFI-Passive and METr receive supply and extract |
| F4a-28 | PHX builds ventilation rooms only from Spaces (`create_building.py` maps each Space; `cleanup.check_room_has_spaces` is a no-op). A Zone with no Spaces would export no ventilation and no iCFA. Read, not run: test before relying on it |
| F4a-29 | The Grasshopper hosting step folds Space overrides into the Room's honeybee Ventilation. If PH-Composer did the same, PHX would then split that folded total among the inheriting Spaces (F4a-25) and count the overrides twice. Read, not run |

## Proposal

1. **Keep the any-set rule.** A Space is either *From Program* or *Specified*; once one rate is
   entered, the other two are 0. It matches the Grasshopper component and avoids F4a-24's mixing.
2. **Every exported Room carries its Program's Ventilation load, unchanged.** The residential default
   has one, so rule 4 always has a schedule. Never fold Space overrides into the Room (F4a-29).
3. **The Spaces view shows the effective airflow on every row.** An inheriting Space shows its
   Program share as a muted number, not the word "Zone", with a tooltip naming the Program and the
   floor share. A specified Space shows what was entered. Zone sums are always shown, so F4a-25 is
   visible instead of hidden behind a dash. A "From Program" action on a specified Space clears all
   three rates.
4. **One Ruby calculation**, matching PHX (four terms summed, split by unweighted Space floor area),
   feeds both the Programs view's Zone column and the Spaces view's Space shares.
5. **Transfer column tooltip:** PHPP only; WUFI-Passive and METr do not read it.
6. **A Zone with no Spaces** gets an export finding once F4a-28 is confirmed by a round trip.

## Open questions

| Id | Question | Recommendation |
| --- | --- | --- |
| Q4a-29 | Keep the any-set rule, or let each rate override on its own, as PHX allows? | Keep the any-set rule |
| Q4a-30 | In a partly specified Zone, inheriting Spaces get their floor share of the full Program flow (PHX today). Accept that and show it, or ask PHX to split only the remainder? | Accept and show it; a remainder rule is a PHX change and less predictable per Space |
| Q4a-31 | EnergyPlus: should the Room's honeybee Ventilation reflect Space overrides, as the Grasshopper path does? It conflicts with PHX's split (F4a-29) | Not now. Room keeps the Program's load; revisit with an EnergyPlus exporter |
| Q4a-32 | A Zone with no Spaces: export finding only, or write a default Space covering the Zone? | Confirm F4a-28 first; then a finding |
