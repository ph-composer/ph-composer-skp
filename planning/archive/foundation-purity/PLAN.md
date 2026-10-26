# Visible pure rules and native adapters

DATE: 2026-10-13
STATUS: Complete. P-01 to P-03 merged to main in PR 121 and archived.
ISSUE: [#120](https://github.com/bldgtyp/ph-composer/issues/120)
BASELINE: `cfe01a6aad99a0e09d5ecf0de5659c606d7ba4f9`
FINDING: [F03](../code-review/sections/01-foundation.md#f03-the-common-foundation-mixes-pure-and-native-geometry-responsibilities)
DEPENDS ON: nothing. Coordinate with [geometry contribution](../geometry-contribution-contracts/PLAN.md)
G-02 if both touch capture in the same period: one owner, one diff.

## Goal

`FaceGeometry`'s rules load and run in a Ruby process with no SketchUp and no test stub. Native
capture becomes a named adapter that builds the same value. Nothing else under `core/` moves.

## Verified at the baseline

| Where | What it does now | Consequence |
| --- | --- | --- |
| `core/face_geometry.rb`, `capture(face, transform)` | Reads `face.loops`, vertex positions, `face.normal`, `face.get_glued_instances`; calls `world_normal(normal, transformation)` with a `Geom::Transformation` and a `Geom::Vector3d` | The only native reads in the module |
| `core/face_geometry.rb`, everything else | `loop_area_m2`, `equivalent_full_face?`, `same_outline?`, `coplanar?`, `loop_equal?`, `canonical_loop`, `quantize`, the `Snapshot` struct | Pure over Arrays of Floats |
| `core/face_geometry.rb`, `world_normal` | Uses `transformation.to_a` and `normal.x`, `.y`, `.z` | Pure in substance; the signature binds it to host types |
| Callers of `FaceGeometry.capture` | `export/geometry_snapshot.rb` (2), `features/zones/faces/geometry.rb` (2), `faces/classify_tool.rb` (3), `adjacency/adjacency.rb` (2), `adjacency/face_split.rb` (3), `windows/units/place_step.rb`, `rehost_step.rb`, `host_guard.rb`, `windows/placement/host.rb` (2), `tools/examples/authoring/` (3) | Nineteen call sites, all one-line renames |
| Callers of the pure functions | `adjacency/overlap.rb`, `adjacency_steps.rb`, `classify_tool.rb` | Unchanged |
| `tests/face_geometry_test.rb` | Loads `test_helper`, which loads the SketchUp stub | Cannot show the rules run without the stub |
| `core/records/record_kind.rb` | Validation pure; carries its `store` | Left as is: the store is an explicit outer dependency the kind is given |

## Target design

```ruby
# core/face_geometry.rb: pure
module FaceGeometry
  # Builds the detached value from explicit world loops in metres and a unit normal.
  def self.build(loops_m:, normal:, has_glued_instances: false)
    # plane, area, canonical digest as `capture` computes them today
  end

  # The world normal of a local normal under a 4x4 column-major matrix given as 16 Floats.
  def self.world_normal(normal_xyz, matrix)
end

# core/face_capture.rb: the SketchUp adapter
module FaceCapture
  INCH_TO_M = FaceGeometry::INCH_TO_M

  def self.call(face, transform)
    loops = face.loops.map do |loop|
      loop.vertices.map do |vertex|
        point = vertex.position.transform(transform)
        [point.x.to_f * INCH_TO_M, point.y.to_f * INCH_TO_M, point.z.to_f * INCH_TO_M]
      end
    end
    normal = FaceGeometry.world_normal([face.normal.x, face.normal.y, face.normal.z], transform.to_a)
    FaceGeometry.build(:loops_m => loops, :normal => normal,
                       :has_glued_instances => face.get_glued_instances.any?)
  end
end
```

`FaceGeometry.capture` is removed once the nineteen callers say `FaceCapture.call`. Values and
digests are identical by construction: the same arithmetic runs on the same numbers.

## Stages

### P-01: pure build and the adapter

State: Complete; merged to main in PR 121. Deviation: the pure file is `tests/support/face_geometry_pure.rb`, not
`tests/face_geometry_pure_test.rb`, because `tests/all_tests.rb` loads every `*_test.rb` into the
stubbed process, where the no-SketchUp assertion cannot hold. It runs only as its own process.

Files: `core/face_geometry.rb`, `core/face_capture.rb` (new), `extension.rb` load order (both under
`core/`, alphabetical, `face_capture` before `face_geometry`, so `face_capture.rb` requires
`face_geometry` with `require_relative`); tests `tests/face_geometry_test.rb` (split into pure cases
and adapter cases) and a new `tests/face_geometry_pure_test.rb`.

1. Add `build` and the array-based `world_normal`; keep `capture` delegating to `FaceCapture.call`
   for this stage only.
2. The pure test file loads `core/errors.rb`, `core/json_walk.rb`, `core/deep_copy.rb`,
   `core/canonical_json.rb`, `core/vector3.rb` and `core/face_geometry.rb` directly, never
   `test_helper`, and runs in a subprocess from `tests/face_geometry_test.rb` with
   `"$RUBY" -I src/ph_composer tests/face_geometry_pure_test.rb` so a stray stub constant cannot leak
   in. Cases: concave and holed loops, large coordinates, reversed outlines, scaled, reflected and
   singular matrices, `equivalent_full_face?` and `coplanar?` fixtures copied from the existing tests.
3. Adapter cases stay in `tests/face_geometry_test.rb`: `FaceCapture.call` on stub Faces equals
   `FaceGeometry.build` on the same numbers, digest included, glue flag included.

Exit: the pure test passes in a bare process; `make test` passes.

### P-02: route callers and remove the shim

State: Complete; merged to main in PR 121.

1. Rename the nineteen call sites; delete `FaceGeometry.capture`; `grep -rn "FaceGeometry.capture"`
   finds nothing.
2. `make fixtures-check` (export goldens unchanged), `make lint-ruby`, affected Zones, Windows and
   export suites, `make coverage`.

Exit: goldens unchanged; no caller of the removed method.

### P-03: dependency map and docs

State: Complete; merged to main in PR 121.

1. Add a short "What is pure and what is an adapter" table to `context/TECH_STACK.md` or
   `context/EXTENSIBILITY.md` "Organization and dependencies": pure values and rules
   (`json_*`, `canonical_json`, `deep_copy`, `vector3`, `face_geometry`, record schemas and
   validation), application services (`records/engine`, `operations/proposal`), native adapters
   (`face_capture`, `dictionary_store`, `entity_store`, `pick`, `view_framing`, `model_operation`).
2. Point the contributor router at `tests/face_geometry_pure_test.rb` as the way to test a rule
   without the host.
3. One bounded review; `make ci` on the selected Ruby, plus 2.7 if load order changed.

Exit: `make ci` passes; the table matches the files.

## Decisions and deviations

The coding agent decides the adapter module's name and whether `INCH_TO_M` stays on `FaceGeometry`.

Nothing needs Ed. No package extraction, no repository interfaces, no move of `Engine`,
`DictionaryStore` or `RecordKind`.

## Verification profile

Standard: the bare-process pure test, adapter equivalence tests, goldens unchanged, one bounded
review, `make ci`. See [ACCEPTANCE.md](ACCEPTANCE.md).
