# Edge capture and contributed drawing geometry

DATE: 2026-10-13
STATUS: Complete 2026-10-26: G-02 merged, G-03 superseded, G-01 and G-04 closed through thermal bridges. Stage ledger in [STATUS.md](STATUS.md).
ISSUE: [#118](https://github.com/ph-composer/ph-composer-skp/issues/118)
BASELINE: `cfe01a6aad99a0e09d5ecf0de5659c606d7ba4f9`
FINDING: [F06](../code-review/sections/03-services.md#f06-the-geometry-seams-cannot-yet-serve-ordinary-edges-or-derived-line-overlays)
DEPENDS ON: the [thermal-bridge plan](../phase-03b-thermal-bridges/PLAN.md) P3b-06 and
P3b-08 are the adopters; [foundation purity](../foundation-purity/PLAN.md) P-02 touches the same
capture file if both run.

## Goal

The shared export snapshot captures ordinary Edges with their occurrence path, transform, registered
dictionaries, SI endpoints and the links a run rule needs. The shared Colour-by service accepts a
typed line primitive beside the Face entries it paints today. Features keep classification, run
formation, quantities and colours.

## Verified at the baseline

| Where | What it does now | Consequence |
| --- | --- | --- |
| `export/geometry_snapshot.rb`, `GeometrySnapshot.walk` | Faces become entries; Groups and ComponentInstances become entries and recurse; anything else yields nil | Ordinary Edges are dropped |
| `export/geometry_snapshot.rb`, `definition_entity` | Inside a component definition, Edges are captured as `{"kind" => "edge", "points_m" => ...}` definition-local facts | A second, narrower Edge shape already exists |
| `export/geometry_snapshot.rb`, `Cursor` | Resumable traversal; a Face capture is the smallest unit | An Edge capture is cheaper than a Face capture |
| `export/geometry_snapshot.rb`, `walk` `cuts` flag | Faces inside a cutting component are not captured | The same rule must decide Edges inside cutting components |
| `colour_by/service.rb`, `Service#rebuild` and `add_entry` | Every entry is tessellated through `Tessellation.partition` into fills, outlines, hatch and wash; visibility by `OccurrenceVisibility` on `entry.path` | No place for a line that is not a Face's outline |
| `colour_by/tessellation.rb`, `each_face` | Yields Faces only; the comment says Edges contribute no Face geometry | An Edge entity entry yields nothing |
| `colour_by/overlay.rb`, `draw` | Fills per colour, unclassified outlines and hatch, HUD | No per-colour line pass |
| `colour_by/service.rb`, `rows` and `label_for` | Legend rows count entries per value and state | A run of several segments would count once per segment unless the primitive says otherwise |
| `features/windows/export.rb` | Reads `snapshot.records(Units::STORE.dictionary)` and Face entries | Unaffected by Edge entries |
| `tests/geometry_snapshot_test.rb`, `tests/colour_by_test.rb`, `tests/phase_one_export_test.rb` | Snapshot goldens, mode tests, export goldens | The regression set |

## Target design

### G-02: Edge entries in the snapshot

```ruby
EdgeGeometry = Struct.new(:points_m, :vertex_ids, :face_ids, keyword_init: true) do
  def to_h
    { "points_m" => points_m, "vertex_ids" => vertex_ids, "face_ids" => face_ids }
  end
end

# in walk, before the final else
elsif entity.is_a?(Sketchup::Edge)
  entry = if capture_faces
            Entry.new(:kind => "edge", :path => child_path.freeze, :transform => transform.to_a.freeze,
                      :dictionaries => dictionaries, :geometry => EdgeGeometry.capture(entity, transform))
          end
  block.call(entry)
```

`EdgeGeometry.capture` transforms both vertex positions to world metres, records the two vertices'
persistent ids and the persistent ids of `entity.faces`, all scoped to the same container as the
Edge (a sibling Face's path is `path[0...-1] + [face_id]`). Connectivity is by shared vertex id
within one container occurrence; coincident world points in different containers are not connected.
Non-finite coordinates raise `geometry.invalid`. Edges inside cutting components follow the Face rule
(`capture_faces` false drops them), so no duplicate opening geometry reaches translation.

Existing contributors filter by `kind`, so Edge entries change no export output; the snapshot goldens
gain Edge rows where fixtures hold loose Edges.

### G-03: a typed line primitive for Colour-by

```ruby
# One straight segment in world SI metres, contributed by a mode projection beside Face entries.
# `path` is the occurrence the segment belongs to, for visibility and the occurrence mask; `member`
# groups several segments into one legend count (a run); `width` is a pixel line width.
LineEntry = Struct.new(:points_m, :value, :label, :state, :path, :colour, :member, :width, keyword_init: true)
```

`Service#add_entry` branches on `LineEntry`: it checks the two points are finite, applies the same
`paint` for state and colour, counts `member` once per row, applies `OccurrenceVisibility` and the
filter on `path`, converts metres to inches once, and appends to `@lines[colour]` with the width.
`Overlay#draw` draws `@lines` per colour with `view.line_width = width` and `GL_LINES` after the
fills. A malformed entry makes the mode fail through the existing `failed` route, so the viewport
shows Off and a warning rather than a stale drawing. Filtering is per segment by `path`; a run with
several source Edges contributes one `LineEntry` per Edge with a common `member`.

No scene graph, no arbitrary draw callbacks, no polygon primitive until Spaces shows it needs one.

## Stages

### G-01: confirm the shapes with the adopter

State: Deferred to the [phase 3b ledger](../phase-03b-thermal-bridges/STATUS.md#deferred-foundation-stages).

With P3b-01 and P3b-06 of the thermal-bridge plan open, confirm: the minimum Edge facts (are
`vertex_ids` and `face_ids` enough for run formation; is visibility needed in the entry); whether
runs are filtered per segment (default here) or whole; the legend count rule through `member`; and
the line width policy. Record the answers in both packets.

Exit: the thermal-bridge plan references these shapes; any disagreement is resolved before G-03.

### G-02: Edge capture

State: Merged to main in PR 119. `FaceGeometry.check_transform!` is the shared singular-transform check
the Edge capture reuses. The stub's Vertex ids come from their own lazy sequence so existing
allocated ids do not move.

Files: `export/geometry_snapshot.rb`; tests `tests/geometry_snapshot_test.rb`,
`tests/export_collection_slices_test.rb`.

1. The SketchUp stub's `Vertex` (`tests/support/sketchup/entities.rb`) has a position and no
   `persistent_id`; the host's does. Give the stub's `Vertex` a persistent id allocated by its
   `Entities`, as other stub entities get theirs, and confirm the stub's `Edge` answers `faces`,
   `start`, `end` and `persistent_id`. Record the addition in `tests/sketchup_stub_deviations_test.rb`
   if that suite inventories stub additions.
2. Add `EdgeGeometry` and the `walk` branch.
3. Tests, one each: a root Edge with a `ph_composer.` dictionary is captured with finite SI endpoints
   and its data; nested, scaled and reflected occurrences transform once and keep distinct paths;
   two coincident Edges in separate containers share no vertex id; Edges inside a cutting component
   are absent; the cursor and the direct capture give equal entries; a degenerate transform raises
   `geometry.invalid`; existing Face and Window export goldens unchanged.
4. `make fixtures` for snapshot goldens; `"$RUBY" -Itests -rgeometry_snapshot_test -rexport_collection_slices_test -rphase_one_export_test -e ''`.

Exit: tests pass; export goldens unchanged except added Edge rows in snapshot fixtures.

### G-03: line primitive

State: Deferred to the [phase 3b ledger](../phase-03b-thermal-bridges/STATUS.md#deferred-foundation-stages).

Files: `colour_by/service.rb`, `overlay.rb`, `install.rb` (documentation comment); tests
`tests/colour_by_test.rb`, `tests/colour_by_panel_test.js` if the legend shape changes.

1. Add `LineEntry`, the `add_entry` branch, the `@lines` cache and the overlay pass.
2. Tests, one each with a synthetic outside mode: lines render into the cache with their colour and
   width; a hidden ancestor or a masked path drops the segment but not the legend count; `member`
   counts a run once; a non-finite point or missing path fails the mode through `failed`; existing
   Face modes unchanged.
3. `make runtime-manifest` is not needed (Ruby only); focused suites; `make lint-ruby`.

Exit: tests pass; the shared service names no feature.

### G-04: adopter integration and native proof

State: Deferred to the [phase 3b ledger](../phase-03b-thermal-bridges/STATUS.md#deferred-foundation-stages).

The thermal-bridge P3b-06 and P3b-08 stages consume the primitives; their native checks prove lines
are visible and runs export. This packet records the receipts by reference and closes F06 only when
both G-02 and G-03 have an adopter in use. Measure traversal and draw cost on the 50,000 Edge
fixture the thermal-bridge plan already names before changing any cache structure.

## Decisions and deviations

| Earlier default | Now | Reason |
| --- | --- | --- |
| Whole-run versus per-segment mask decided at G-01 | Per segment, one Edge per entry; no `member` key. G-01 answered on 2026-10-21 (thermal bridges D3b-23): the legend counts entries, so a type's row counts its Edges, and runs are a schedule and export grouping, not a legend one | A segment is the unit that has one occurrence path; the `LineEntry` that carried `member` was superseded by `derived` segments (G-03) |
| Polygon surface primitive for Spaces | Not until Spaces asks | No adopter |

The coding agent decides struct names and whether `EdgeGeometry` lives in `core/` beside
`FaceGeometry` or in `export/`.

Escalate to Ed: whole-run filtering as a visible behaviour (D-03) if the thermal-bridge interview
asks for it.

## Verification profile

High assurance for the serialization boundary: snapshot goldens, focused suites, dual-Ruby
`make ci`, one coherent review with the adopter's diff, and the adopter's native drawing proof. See
[ACCEPTANCE.md](ACCEPTANCE.md).
