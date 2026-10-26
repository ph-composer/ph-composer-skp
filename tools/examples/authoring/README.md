# Zone and face authoring walkthrough

This development-only walkthrough exercises the Zone and Face features through
`PhComposer::API` while the panel is closed. It creates two synthetic box Groups, makes each a
Zone, edits Zone details, classifies one Face in each Zone, and reads the persisted values back.
It uses only public discovery, query, preview and invoke contracts after creating the geometry.

The Zone and Face walkthroughs share `client.rb`: a public-API client bound to the active Model,
the box Group most of them draw, and native Undo and Redo. Each walkthrough requires it, so loading
any one walkthrough file is enough.

Run it in a fresh scratch Model through the development bridge:

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/walkthrough.rb"; AuthoringWalkthrough.setup'
uv run tools/hostkit/host_bridge.py eval 'AuthoringWalkthrough.run'
uv run tools/hostkit/host_bridge.py eval 'AuthoringWalkthrough.undo'
uv run tools/hostkit/host_bridge.py eval 'AuthoringWalkthrough.verify'
uv run tools/hostkit/host_bridge.py eval 'AuthoringWalkthrough.redo'
uv run tools/hostkit/host_bridge.py eval 'AuthoringWalkthrough.verify'
uv run tools/hostkit/host_bridge.py save
```

After reopening the saved Model, load the script and run `AuthoringWalkthrough.verify`. The result
reports the Zone and classified-Face counts, the canonical Zone values, occurrence paths and the
agreement between each Face record and its Zone membership stamp. The fixture contains no
licensed or project data and is never included in the RBZ.

## Repairs: identity repair and limited Restore Zone

`repair_walkthrough.rb` covers the two explicit Zone repairs. Run it in a fresh scratch Model:

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/repair_walkthrough.rb"; RepairWalkthrough.setup'
uv run tools/hostkit/host_bridge.py eval 'RepairWalkthrough.copy_shared'
uv run tools/hostkit/host_bridge.py eval 'RepairWalkthrough.repair_copy'
```

`copy_shared` adds a component instance over the source Zone's definition. Repair must refuse it
with `target.shared_definition`, because shared storage cannot be given an identity of its own.

The independent copy is the case repair exists for, and how SketchUp makes one is what this
walkthrough is measuring rather than assuming. Select the source Zone in the viewport, Ctrl-drag a
copy clear of the original, then:

```sh
uv run tools/hostkit/host_bridge.py eval 'RepairWalkthrough.adopt_copy'
uv run tools/hostkit/host_bridge.py eval 'RepairWalkthrough.repair_copy'
```

`adopt_copy` reports `copy_has_own_zone_record` and `copy_shares_definition`. Record both: they are
the host evidence copy references need, and they decide which branch repair takes.
After repair, `duplicate_zone_ids` is empty, both `zone_states` read `found`, and no Face id appears
twice.

Then explode and restore:

```sh
uv run tools/hostkit/host_bridge.py eval 'RepairWalkthrough.explode_source'
uv run tools/hostkit/host_bridge.py eval 'RepairWalkthrough.restore_source'
uv run tools/hostkit/host_bridge.py eval 'RepairWalkthrough.undo'
uv run tools/hostkit/host_bridge.py eval 'RepairWalkthrough.redo_last'
uv run tools/hostkit/host_bridge.py save
```

`explode_source` should leave the stamped Faces in the parent context with their payloads, which is
what makes a limited Restore possible; `restorable` then names the exploded Zone id and its member
count. `restore_source` reports `unrecoverable`: the Zone name, ground depth and Group metadata are
not recovered, and the restored Zone takes a fresh default name. Reopen the saved Model and run
`RepairWalkthrough.verify` to confirm nothing became current across save and reopen.

## Colour-by: the overlay, its cache and the HUD

`colour_by_walkthrough.rb` is the Colour-by host gate. An earlier host spike measured that a filled
overlay is affordable and correct; this measures the feature built on it, which the spike did not
have. Run it in a fresh scratch Model:

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/colour_by_walkthrough.rb"; ColourByWalkthrough.setup'
uv run tools/hostkit/host_bridge.py eval 'ColourByWalkthrough.meshes'
uv run tools/hostkit/host_bridge.py eval 'ColourByWalkthrough.on'
```

`meshes` answers the first question, which the offline suite cannot: the stub fans a Face's outer
loop, so what SketchUp does with the holed wall and with a concave Face is unmeasured. A hole that
survives as a second loop, and a triangle count above the fan's, is the answer the fill needs.

With a mode on, look at the viewport: the HUD legend in the upper left, the fill hidden behind
geometry in front of it, edges showing through, and clicking a filled Face still selecting it.
`fingerprint_before` and `fingerprint_now` must be equal in every field, and the Undo menu must
name no Colour-by entry.

Then the invalidation questions:

```sh
uv run tools/hostkit/host_bridge.py eval 'ColourByWalkthrough.hide_tag'
uv run tools/hostkit/host_bridge.py eval 'ColourByWalkthrough.undo'
uv run tools/hostkit/host_bridge.py eval 'ColourByWalkthrough.redo_last'
uv run tools/hostkit/host_bridge.py eval 'ColourByWalkthrough.cost'
uv run tools/hostkit/host_bridge.py eval 'ColourByWalkthrough.off'
```

`hide_tag` is the one to watch: the tag path assumes `Sketchup::LayersObserver#onLayerChanged`
fires when a tag's visibility is toggled, and nothing has measured that. If `rebuilds` does not
advance, the assumption is wrong and the tag rule needs another route. Toggle a tag by hand in the
Tags panel as well, since a scripted `layer.visible =` and a user's click need not behave alike.
It also reports the revision either side of the toggle: if hiding a tag turns out to be undoable,
the host commits a transaction for it and the revision advances too, which costs a second rebuild
and is worth knowing rather than assuming.

`meshes` reports `triangles_only` alongside the triangle count. The fill flattens every polygon
into one `GL_TRIANGLES` stream, so a polygon of any other arity would draw the wrong shape.

SketchUp's own Overlays panel is a second on/off switch, kept per overlay id. Untick
"PH-Composer Colour by" there while a mode is on and record what happens: the drawing should stop
while the Colour by menu still shows the mode checked, and whether the menu ought to follow that
switch is a question for this gate.

Scene activation is expected to leave the drawing stale, because this session subscribes to no
observer that reports it. Make two scenes with different tag visibility, run `activate_scene` for
each, and record what actually happens; that answer decides whether the scene rule needs a frame
change observer or belongs in a later slice.

Finally switch to another open Model and back, and close the walkthrough Model, confirming the
overlay leaves with it and comes back with it.

## What a Classify gesture costs

`gesture_cost_walkthrough.rb` is the harness behind
[the gesture cost evidence](../../../planning/archive/phase-01-faces-and-zones/evidence/p1-d-gesture-cost.md). It answers
two questions that decide how the Classify tool is built: whether the 250-Face ceiling is
defensible on the host, and what occurrence resolution costs.

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/gesture_cost_walkthrough.rb"; GestureCostWalkthrough.build(334)'
uv run tools/hostkit/host_bridge.py eval 'GestureCostWalkthrough.gesture_curve([1, 10, 50])'
uv run tools/hostkit/host_bridge.py eval 'GestureCostWalkthrough.ceiling'
uv run tools/hostkit/host_bridge.py eval 'GestureCostWalkthrough.model_curve'
```

`build` takes a box count, six Faces each, and reports how many Faces the solve paired.
`gesture_curve` grows the gesture at one Model size, which says what a drag costs.
`model_curve` repeats one gesture against a growing Model, which says whether the cost is in the
gesture or in the walk; it rebuilds the Model at every size, so expect it to take minutes.
`ceiling` runs the shipped limit and one above it.

Run the two curves in that order and read them together. A gesture cost that grows with the Model
at a fixed gesture size is the Model walk, not the gesture, and no ceiling fixes it. `inventory`
reports `list_ms` alongside, which is how the quadratic Face read was found.

## The Classify tool

`classify_tool_walkthrough.rb` is the tool's own gate. The gesture is the part no script can
perform: SketchUp delivers pointer events to the active tool and the Ruby API synthesizes none, so
this arms the tool and then asks you to click and drag. A scripted gesture would only re-measure the
classify operation the offline suite already tests and would say nothing about the pick, the
modifier mask or the edit context, which are what this gate exists to answer.

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/classify_tool_walkthrough.rb"; ClassifyToolWalkthrough.setup(40)'
uv run tools/hostkit/host_bridge.py eval 'ClassifyToolWalkthrough.arm("Wall", "Outdoors")'
```

Then, in the viewport: drag across all forty Faces in one gesture, read `report`, send
`ClassifyToolWalkthrough.undo` and read `report` again. One drag must revert in one Undo.

Run `pick(x, y)` over one Face twice, once at the Model root and once with the Zone open for
editing, and compare `picked_reference` with `walked_reference`. Every occurrence reference the
tool builds comes from the picked path, so the two must agree in both contexts. If they differ
inside the edit context, `PickHelper#path_at` is context-relative and `Pick.face_path` has to
rebase it.

Shift-click one Face and read `report`'s `classified` count. More than one means
`CONSTRAIN_MODIFIER_MASK` really is Shift on this host and really is set in the flags a button
event carries; exactly one means neither, and the mask needs measuring. Nothing scripted can
answer this: SketchUp reports a modifier only inside an event it delivers to the active tool.

Start a drag and press Escape mid-drag, then leave the viewport mid-drag and release outside it.
Both must leave the Model unchanged and no Undo entry behind. Then, with the tool active, activate
another Model, open and close an edit context, and pick a native tool, recording what the host does
to the active tool each time.

Run `setup(251)` and drag over the lot: the gesture must refuse in the viewport the way it refuses
through the API, with nothing painted. That is the classify operation's deferred native check, kept
here because a real gesture is what it needs.

Right-click over a Face and then over empty space, once with no tool running and once with the
Classify tool running. The submenu is offered only where a Face is under the cursor, but the two
cases reach that answer differently: with no tool, a global handler reads the selection SketchUp
makes before it builds the menu; with the tool running, SketchUp hands the right-click to the tool
and its `getMenu` picks the coordinates directly. Record whether SketchUp really does select the
right-clicked Face first, and whether the global handlers fire as well while the tool is running,
which would offer the submenu twice.

Finally, turn a Colour-by mode on by hand, run the tool and stop it, and confirm the mode the user
chose is still the remembered one (PRD Q12). Do it the other way too: start the tool, pick a
different mode from the Colour by menu while it runs, and stop the tool; that mode is the user's
choice and must survive. Then `locate_unclassified` with the Zone closed and open, recording
whether SketchUp shows a selection made outside the active edit context.

## The Overview screen, the legend and the palette

`overview_walkthrough.rb` is the panel's gate. Almost none of it can be scripted: the panel is an
HtmlDialog and nothing in the Ruby API clicks one, so this builds a Model worth looking at and reads
back what the panel's own commands did to it. You do the clicking.

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/overview_walkthrough.rb"; OverviewWalkthrough.setup'
uv run tools/hostkit/host_bridge.py eval 'OverviewWalkthrough.read_cost'
uv run tools/hostkit/host_bridge.py eval 'OverviewWalkthrough.report'
```

`setup` makes two Zones of six Faces each, four of them classified, so the tree has two tiers, every
Zone row carries an unclassified marker, and each colour mode has more than one legend row. Open the
panel and work through the screen: expand and collapse a Zone, change a type and a boundary chip,
order and filter by the controls above the table, select a Zone row and save its details.

`read_cost` times the whole snapshot, which is every section the Overview paints from. Take it on
the two-Zone Model, then run `crowd(500)` and take it again: that is the first measurement of what
this screen costs to paint, and nothing offline can stand in for it.

Locate is the one thing the Classify tool gate already asked of the native menu, and the panel is a
second caller. Use a row's Locate with the Zone closed and again with it open, and then a legend
row's, recording whether SketchUp shows the selection and where the camera lands while the panel has
focus.

For the legend: turn each mode on from the panel and confirm the viewport matches what the native
Colour by menu gives, including the remembered mode after a restart. Press "Show only this" on one
row and capture the window: the muted grey has to read as set aside rather than as another value,
which is a drawing claim no offline test makes. Press it again and confirm everything comes back.
Run `refresh_pending?` straight after one legend click; it must be false, or the panel is publishing
the same snapshot twice per command.

For the palette: choose a chip while the panel has focus and record whether the viewport's first
click reaches the Classify tool or is spent returning focus to the Model window. Choose an Attached
zone from the picker and confirm the boundary condition follows it; use "New attached zone" and
confirm the new record is chosen at once. Stop classifying and confirm the viewport goes back.

Last, the stale case: with the panel open, change a Face through the Ruby Console, then use that
row's chip in the panel. The edit must refuse and the row must go back to what the Model holds.

## Spaces: records, operations, copies and moves with the panel closed

`spaces_walkthrough.rb` needs a Model with two Zones, and refuses before writing anything without
them. Its `fixture_` methods are native setup, what a user does with SketchUp's own tools: three 1 m
floor outlines drawn loose in the first Zone, 0.5 m up, a fourth drawn in the new Space, and a Volume
copied as SketchUp copies a Group. Everything else is a client using only `PhComposer::API`. It opens
the Zone with `ph_composer.context.open`, creates the Space from the three outlines, opens the Space,
finds the fourth outline with `spaces.candidate_faces.list` and makes it a second Volume, closes to the
root with `ph_composer.context.root`, marks one Floor Segment as not counting, sets a height, two
airflows and clears one, reads back, recovers from a stale edit, reads the copy's duplicate identity
and makes it independent, and moves the Space into the second Zone. It ends with the refusals a
client meets: a stale `expected_path`, a locked step and a wrong session, each leaving the path and
the revision unchanged. The client never assigns the edit path; a test refuses one. A Space copied on
its own is not part of the script: the copy watcher makes it independent after the script returns.

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/spaces_walkthrough.rb"; SpacesWalkthrough.run'
```

## Spaces: the Mark floor tool and Create Space

`mark_tool_walkthrough.rb` is the Mark floor tool's host gate script, after the Classify one. It
builds one Zone holding a Space of one Volume with four floor Faces at factor 0 and a Face at the
Space's root, four loose floor Faces, a classified wall and a Face outside every Zone, then arms the
tool; you click, drag and right-click.

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/mark_tool_walkthrough.rb"; MarkToolWalkthrough.setup'
uv run tools/hostkit/host_bridge.py eval 'MarkToolWalkthrough.instrument'
uv run tools/hostkit/host_bridge.py eval 'MarkToolWalkthrough.arm(1.0)'
```

Then drag across the four Volume Faces, read `report` (one Undo step per gesture, the factor frozen
at button-down), and read `flags`: each held move must carry `MK_LBUTTON`, or the tool's lost-release
check cancels every drag on this host. `limit(2)` checks a drag past the limit refuses whole. Open
the Space and click its root Face for a new Volume; click a loose Face for the Create Space offer
and right-click with the tool running for "Create Space…". With the Zone open and three loose Faces
selected, the wall among them, choose Create Space from SketchUp's context menu: the panel's review
must accept two, leave the wall out with its reason, and Create must make one Space in one Undo
step.

## Spaces: Colour-by modes and readouts with the panel closed

`spaces_colour_by_walkthrough.rb` turns each Spaces mode on through `ph_composer.colour_by.activate`,
reads its legend (labels, counts and summed figures) back from `ph_composer.colour_by.state`, shows the
Space labels with every optional line and the selection totals, and turns everything off. It writes
nothing; `revision_moved` says so. `tests/spaces_colour_by_walkthrough_test.rb` runs it on the reference
model.

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/spaces_colour_by_walkthrough.rb"; SpacesColourByWalkthrough.run'
```

## Thermal Bridge Types with the panel closed

`thermal_bridge_types_walkthrough.rb` creates three Thermal Bridge Types, edits one psi-value,
duplicates one and deletes one, each a registered action and one native Undo step, and reads the
catalog back through `ph_composer.thermal_bridges.types.all`. `verify` compares that read with the
expected catalog, so it serves after Undo and Redo and after a save and reopen.
`tests/thermal_bridge_types_walkthrough_test.rb` runs it offline.

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/authoring/thermal_bridge_types_walkthrough.rb"; ThermalBridgeTypesWalkthrough.run'
uv run tools/hostkit/host_bridge.py eval 'AuthoringExample.undo'     # six times, reading state between
uv run tools/hostkit/host_bridge.py eval 'ThermalBridgeTypesWalkthrough.state'
uv run tools/hostkit/host_bridge.py eval 'AuthoringExample.redo'     # six times
uv run tools/hostkit/host_bridge.py eval 'ThermalBridgeTypesWalkthrough.verify'
```
