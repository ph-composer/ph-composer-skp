# Research: Zone ventilation and Space airflows

DATE: 2026-11-15
STATUS: Research complete. Ed answered Q4a-29 to Q4a-32 on 2026-11-15. F4a-28 confirmed by a PHX round trip; the rest read from source.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Ed's desired behaviour (2026-11-15):

1. The Zone's Program carries a Ventilation load, applied to the Zone by default.
2. A user *may* enter airflows per Space in Zones → Spaces. Entered values override the Program's
   airflow for that Space on export to WUFI-Passive and METr.
3. Without Space airflows, the Program's airflow applies.
4. The Program's ventilation schedule applies in every case.

Read here as the Ventilation section of the Zone's Program (Q4a-12: a Zone picks a Program, no
per-Zone loads), not a separate Ventilation record assigned per Zone.

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
| F4a-28 | PHX builds ventilation rooms only from Spaces (`create_building.py` maps each Space; `cleanup.check_room_has_spaces` is a no-op). **Confirmed 2026-11-15** by a round trip through PHX 1.59.1 (a 6 × 5 × 3 m honeybee Room, no Spaces): the WUFI XML and METr JSON build without error and without a Space warning; one Zone with its 3 components and gross volume 90 m³, but iCFA 0, `NetVolume` 0 and `<RoomsVentilation count="0"/>`. The Grasshopper WUFI writer (`gh_compo_io/write_wuif_xml.py`) runs the same PHX conversion and surfaces only its WARNING lines |
| F4a-29 | The Grasshopper hosting step folds Space overrides into the Room's honeybee Ventilation. If PH-Composer did the same, PHX would then split that folded total among the inheriting Spaces (F4a-25) and count the overrides twice. Read, not run |

## Proposal

1. **Detailed airflows are a Zone mode (Q4a-29, Q4a-30).** A Zone is *From Program* until any of
   its Spaces has a rate. Then it uses detailed airflows: every Space in it exports its own rates,
   0 where blank, and none takes a Program share. This replaces PH-Composer's per-Space any-set rule
   and makes F4a-25 moot for PH-Composer. It follows the PH design cascade (a bedroom supplies, a
   bath extracts, a hall transfers): a user who enters the bedroom's rate expects the hall's to be
   its own, 0 until entered. Export writes `_v_sup`, `_v_eta` and `_v_tran` on every Space of a
   detailed Zone and `None` on every Space of a From Program Zone, so PHX never mixes the two.
2. **Every exported Room carries its Program's Ventilation load, unchanged (Q4a-31).** It is the
   schedule for every Space, the flow for a From Program Zone, and EnergyPlus's ventilation either
   way. Never fold Space rates into the Room (F4a-29).
3. **The Spaces view shows the effective airflow on every row.** In a From Program Zone each Space
   shows its share as a muted number, with a tooltip naming the Program and the floor share. In a
   detailed Zone each Space shows what was entered and a muted 0 where blank. The Zone row shows a
   "Detailed" tag and its Program as the schedule source; Zone sums are always shown. Entering the
   first rate in a Zone says so in a notice ("its other 3 Spaces export 0 until you enter theirs").
   **From Program** sits on the Zone row and clears every Space's rates in that Zone; clearing the
   last rate by hand does the same.
4. **One Ruby calculation**, matching PHX (four terms summed, split by unweighted Space floor area),
   feeds both the Programs view's Zone column and the Spaces view's Space shares. Its per-person
   term needs the Zone's people, which for the residential default come from its Dwelling
   (bedrooms + 1, F4a-20). So the occupancy derivation must live in Ruby, not only in the Python
   translation, and the Spaces view's shares follow Programs and Dwellings in the build order.
5. **Transfer column tooltip:** PHPP only; WUFI-Passive and METr do not read it.
6. **A Zone with no Spaces is an export warning, not an error (Q4a-32).** WUFI-Passive and METr open
   such a file; it will not calculate until Spaces are added. The Spaces view flags the Zone.

The [Programs prototype](../mockups/README.md) shows items 1, 3, 5 and 6 in Zones → Spaces
(`j1-spaces`, `j1-spaces-cascade`, `j3-spaces`).

## Open questions

| Id | Question | Recommendation |
| --- | --- | --- |
| Q4a-29 | Keep the any-set rule, or let each rate override on its own, as PHX allows? | Keep the any-set rule: supply, extract and transfer rooms are designed as a set, so an unentered rate means 0 |
| Q4a-30 | In a partly specified Zone, inheriting Spaces get their floor share of the full Program flow (PHX today). Accept that and show it, or ask PHX to split only the remainder? | Accept and show it; a remainder rule is a PHX change and less predictable per Space |
| Q4a-31 | EnergyPlus: should the Room's honeybee Ventilation reflect Space overrides, as the Grasshopper path does? It conflicts with PHX's split (F4a-29) | Not now. Room keeps the Program's load; revisit with an EnergyPlus exporter |
| Q4a-32 | A Zone with no Spaces: export finding only, or write a default Space covering the Zone? | Confirm F4a-28 first; then a finding |

## Answers (Ed, 2026-11-15)

| Id | Answer |
| --- | --- |
| Q4a-29 | **Yes:** blank rates export 0 once rates are entered, now applied per Zone (Q4a-30) |
| Q4a-30 | **No remainder split, and no floor shares in a partly specified Zone:** once any Space in a Zone has a rate, the Zone uses detailed airflows and every Space exports its own rates, 0 where blank. This supersedes F4a-25 for PH-Composer. Claude agreed, with the notice on the first entry and a Zone-level From Program as the safeguards |
| Q4a-31 | **The Program's Ventilation load for EnergyPlus**, unchanged, for now |
| Q4a-32 | **A warning, not an error.** Confirmed allowed by the round trip (F4a-28); the file opens and does not calculate until Spaces are added |

What changes in the existing Spaces feature: the any-set rule moves from the Space to the Zone in
`features/spaces/scan/metrics.rb` (`airflow_mode`, `airflows`, Zone sums),
`python/ph_composer_translation/space_sections.py` (`airflow_rates`) and the Spaces view
(`html/features/spaces/cells.js`, `view.js`: placeholders, tooltips, the Zone sums' dash).
