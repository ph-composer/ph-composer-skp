# Window performance overlays

DATE: 2026-09-18
STATUS: Requested. Post-MVP draft, not interviewed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (no remote)

## Problem

A consultant reviewing a design wants to see at a glance which windows receive the sun. A ramp
across the window units, read from the same climate data the energy model uses, answers that in
the model and gives the client a picture.

## What the pivot changed

The predecessor's V2 brief had two modes. One does not survive.

| V2 part | Disposition | Note |
| --- | --- | --- |
| Solar Radiation mode | Adapt | Same coarse monthly method. The data source is now the climate-data snapshot, cited from honeybee-ph, not PHPP |
| Shading Factor mode | Drop | It relayed designPH's computed factors. PH-Composer authors no shading of any kind (window-types Q10), and METr computes shading after export. There is nothing to show |
| Read-only overlay, legend, missing and stale states, fixed or user ramp limits | Port | |
| Occurrence-safe identity, no material mutation | Port | Simpler now: a window unit is one generated component instance with a `window_type_id` |
| Own overlay and legend code | Drop | Use the shared Colour-by component and HUD legend from face-assignment. This packet registers a mode |
| Links to PH-Navigator web and the PHI rules repository | Drop | Private repositories |
| dph-plus-windows prior art | Port as evidence | A public PH-Tools repository. Its material mutation and name join stay rejected |

## The metric

Incident global radiation on the window plane, in kWh for a chosen period, from the five monthly
series in the climate snapshot: north, east, south, west and global horizontal, kWh/m² per
month. A window's value is interpolated from those series by its azimuth and tilt, then
multiplied by an area.

It is unshaded, by construction. It is not hourly, not transmitted energy, not solar gain and
not a METr result. The legend says "Unshaded incident radiation, monthly climate data" so nobody
reads it as more.

The interpolation rule is the open technical question. METr and WUFI-Passive do one internally.
PH-Composer must either match a published rule or label its own as approximate. See Q2.

## Behaviors

- A `Window radiation` Colour-by mode. Window units fill with a ramp colour. The HUD legend shows
  metric, period, units, range and the climate source.
- Period control: one month, a month range, or the year.
- Ramp limits: fixed by the user, or the model's range. Never silent rescaling between views.
- The Window Schedule gains a column with the exact value, and Locate works as it does today.
- Missing states are separate from zero: no climate chosen, window unit with no Zone, a
  horizontal face with no usable azimuth.
- Values recompute on panel open and Refresh, as every scan in this product does. No observer.
- Turning the mode off leaves no trace. No materials, no attributes.

## Decisions for the interview

| # | Question | Recommendation |
| --- | --- | --- |
| Q1 | Confirm the Shading Factor mode is dropped | Yes |
| Q2 | Interpolation between the five series for an off-axis or tilted window | Linear by azimuth between the two nearest vertical series, then by tilt toward horizontal. Labelled approximate until compared against METr results for a test set |
| Q3 | Receiving area: the unit's rough opening or its glazing area? | Glazing area, which the Window Type already computes, with kWh/m² as a second legend option that needs no area |
| Q4 | A second metric later? | The window U-value, U-w, by ramp. It needs no climate and no new calculation, and it could ship first. Worth asking whether it should be the MVP mode and radiation the follow-up |
| Q5 | Screenshots: SketchUp's image writer omits overlay content | Out of scope. The user takes a screen capture. Record it as a known limit |

## Non-goals

No shading, no hourly sun tracing, no solar gain, no energy balance, no glare, no certification
claim, no material mutation, no CSV join.

## Dependencies

[climate-data](../../phase-04-climate/README.md) for the monthly series.
[window-types](../../../archive/window-types/README.md) for window units, glazing area and the schedule.
[face-assignment](../../../archive/face-assignment/README.md) for the Colour-by component. The deferred
overlay spike for filled faces.

## Acceptance shape

On a synthetic model with windows facing eight compass directions and one skylight: the mode
shows a ramp that orders south above north in a northern-latitude climate, the schedule shows
exact values, a cardinal-facing window matches the hand calculation from its series exactly, a
model with no climate shows the missing state, and turning the mode off leaves the model
byte-for-byte unchanged in its attributes and materials.

## Prior art and evidence

- Predecessor `planning/phases/V2_window-performance-overlays.md`.
- honeybee-ph `honeybee_ph/site.py`, `Climate_MonthlyRadiationCollection`.
- dph-plus-windows, https://github.com/PH-Tools/dph-plus-windows.
