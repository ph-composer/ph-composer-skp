# Sun-path view

DATE: 2026-09-18
STATUS: Requested. Post-MVP draft, not interviewed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (no remote)

## Problem

Consultants explain orientation and overhang decisions to clients in the model. A Ladybug-style
sun path in the viewport, tied to the shadow time SketchUp already shows, makes that explanation
without leaving SketchUp or opening Rhino.

## Port disposition

The predecessor's V1 brief had no designPH dependency. Nearly all of it carries.

| Part | Disposition | Note |
| --- | --- | --- |
| V1 outcome, stories, scope boundary, research list, acceptance shape | Port | |
| Overlay lifecycle rules from the predecessor's `context/TECH_STACK.md` | Port | With the foundation transplant |
| The predecessor's W2 R4 overlay proof | Port as evidence | It proved world-transform drawing in a `Sketchup::Overlay`. Fill, depth and cost are the deferred overlay spike |
| V1's link to PH-Navigator web's site-sun lens | Drop | Private repository. Named as prior art only |
| Colour-by component and HUD legend | Adapt | The sun path is a view toggle beside the Colour-by modes, not a mode, since it colours nothing |

## Behaviors

- A `Sun path` toggle in the panel and in SketchUp's Overlays list. It draws a compass and
  horizon ring, seven monthly day arcs (the solstices and the months between, which pair up),
  hourly analemmas and one sun marker.
- Nothing drawn is selectable or becomes model geometry.
- SketchUp's shadow time is the authority for the marker. Change the native Shadows date or time
  and the marker moves. The view does not replace those controls.
- Latitude, longitude and time zone come from the Climate section's site location when the
  climate-data packet exists, else from SketchUp geolocation. North follows SketchUp's north
  angle.
- The diagram centres on the model bounds and sizes to them, with a user radius override.
- With no location, the toggle shows an unavailable state that names what is missing. It never
  draws a path for latitude zero by default.
- Turning it on does not turn on SketchUp shadows. The two are independent.

## Decisions for the interview

| # | Question | Recommendation |
| --- | --- | --- |
| Q1 | Can this ship before climate-data, using SketchUp geolocation alone? | Yes. It removes the only hard dependency |
| Q2 | Anchor: model bounds, origin or a user point? | Model bounds, with a radius control. A user anchor later if asked for |
| Q3 | Civil time or solar time on the hour labels? | Civil time with SketchUp's time zone, and the label says so. A hidden one-hour daylight-saving shift is the known trap |
| Q4 | Can the user drag the sun to set SketchUp's time? | Later. It writes to native shadow settings, which needs its own Undo decision |
| Q5 | Solar position method? | A published algorithm implemented in Ruby, checked against a trusted reference at solstices, equinoxes and daylight-saving boundaries. Ladybug is the visual reference, not the code source |
| Q6 | Which controls in the first scope? | On and off, radius, labels on and off. No opacity or colour settings |

## Non-goals

No radiation, no shading factors, no hosted viewer, no numerical claim against Ladybug until a
comparison is defined and passed, no writes to SketchUp's location, north or time.

## Dependencies

The foundation's overlay lifecycle and a current-host line-drawing proof. The filled-face overlay
spike does not gate this line-only view. [climate-data](../../phase-04-climate/README.md) supplies the site
location when present and is optional under Q1.

## Acceptance shape

In real SketchUp, on a geolocated and a non-geolocated synthetic model: toggle the view, change
the native shadow date, time, time zone and north, orbit, enter nested groups, switch models,
save and reopen. Registration stays correct, the missing state is clear, and no geometry
changes. Several known sun positions match the reference at a stated tolerance.

## Prior art and evidence

- Predecessor `planning/phases/V1_sun-path-view.md`.
- Predecessor `planning/archive/W2_window-representation-research.md`, R4.
- Ladybug Tools sun path, as the visual reference.
