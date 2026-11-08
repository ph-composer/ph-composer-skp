# Library file format

The library file provider reads a UTF-8 JSON file, or the immediate JSON files in a folder. A
library supplies definitions that the user copies into the SKP and edits locally. The implemented
wire kinds are `materials`, `frames`, `glazings` and `psi_install_types`. Hosted libraries that sign in use a separate extension; this file format is unchanged by them.

## Envelope

```json
{
  "format": "ph-composer.library",
  "schema_version": 1,
  "kind_schema_versions": { "materials": 1 },
  "library": { "id": "example.synthetic", "name": "Synthetic Materials" },
  "exported_at": "2026-10-01T12:00:00Z",
  "kinds": {
    "materials": [{
      "id": "example-insulation",
      "name": "Synthetic insulation",
      "category": "insulation",
      "conductivity_w_mk": 0.04,
      "density_kg_m3": 40.0,
      "specific_heat_j_kgk": 1000.0,
      "emissivity": 0.9,
      "color": "#c8d8b0",
      "notes": "Synthetic example, not a product specification.",
      "datasheet_links": []
    }]
  }
}
```

Every envelope field shown above is required. `library.id` and `library.name` contain nonempty
text. `exported_at` is an ISO 8601 timestamp with a timezone. Each `kinds` entry is an array with
a version in `kind_schema_versions`. Every kind requires a row `id`, the provider's stable record
identity; PH-Composer gives a copied record its own local identity.

A row has no label field of its own. Each kind declares how a label is read from its values: the
Materials and Window product kinds use `name`, and a kind without a `name` uses its own words, such
as a designation. A row whose label is missing or blank is skipped with the warning
`library.row_label_invalid`. Rows are listed by library, then label without regard to case, then
label as written, then `id`, so equal labels with different ids are all kept.

Exporting local definitions publishes each local id as the wire record id. The optional
`record_origins` object groups informational origins by wire kind and exported record id.
An origin contains `label`, `provider_kind`, `library_id` and `record_id`. The label is a sanitized
provider-kind label. Origins contain no configured path, credentials or raw source snapshot;
the reader ignores them and they do not affect semantic fingerprints.

The export form defaults to all supported local definitions. Selected scope uses explicit record
ids and never derives its scope from a filter. New identity creates a library UUID; update keeps
the validated destination identity. A native review lists omitted local metadata and unsupported
records before a staged write replaces the destination. Cancellation or failure preserves its bytes.

## Materials version 1

Only `id` and `name` are required on a wire row. Supply SI numbers directly; PH-Composer never
guesses a unit or converts a differently named IP field. Missing optional fields produce a
structured warning and use the defaults below. A value that violates a declared wire field schema skips the row. Copy also checks the mapped
Material value contract, including hexadecimal color syntax.

| Field | Type and unit | Missing value |
| --- | --- | --- |
| `id` | Nonempty string, unique within a library and kind | Row skipped |
| `name` | Nonempty string | Row skipped |
| `category` | Category id string | Uncategorized, stored as `""` |
| `conductivity_w_mk` | Positive number in W/mK, or null | null |
| `density_kg_m3` | Positive number in kg/m3, or null | null |
| `specific_heat_j_kgk` | Positive number in J/kgK, or null | null |
| `emissivity` | Number from 0 through 1, or null | null |
| `color` | Six-digit hexadecimal string, such as `#ffffff` | `#ffffff` |
| `notes` | String | `""` |
| `datasheet_links` | Array of strings | `[]` |

The thirteen category ids are:

| Id | Category |
| --- | --- |
| `insulation` | Insulation |
| `finishes` | Finishes |
| `woods` | Woods |
| `metals` | Metals |
| `masonry` | Masonry |
| `stud_layers_steel` | Stud-Layers (Steel) |
| `stud_layers_wood` | Stud-Layers (Wood) |
| `air_horizontal_heat_flow` | Air: Horizontal Heat Flow |
| `air_upward_heat_flow` | Air: Upward Heat Flow |
| `air_downward_heat_flow` | Air: Downward Heat Flow |
| `rainscreen_insulation` | Rainscreen Insulation |
| `doors` | Doors |
| `membrane` | Membrane |

An unknown category becomes Uncategorized locally. Its original text remains in the copied
source snapshot. PH-Composer omits undeclared row fields with a warning. Wire records do not
carry local `source`, `user_data` or extension payloads.

## Window products version 1

Frames, Glazings and Psi-Install Types use the same envelope and identity rules as Materials.
Only `id` and `name` are required on a wire row. Missing optional fields produce structured
warnings. Missing quantities remain null. Numbers are SI values with the units in their key
names; unsigned fields permit zero, and junction psi-values may be negative. Invalid mapped
values refuse copying. Frame and Glazing colors use six-digit hexadecimal strings.

| Kind | Quantity fields | Other fields and defaults |
| --- | --- | --- |
| `frames` | `width_m`: nonnegative m; `uf_w_m2k`: nonnegative W/m²K; `psi_g_w_mk`: signed W/mK | `manufacturer`, `brand`, `product_code`, `position`, `operation`: empty strings; `color`: `#ffffff` |
| `glazings` | `ug_w_m2k`: nonnegative W/m²K; `g_value`: 0 through 1 | `manufacturer`, `product_code`, `description`: empty strings; `color`: `#ffffff` |
| `psi_install_types` | `psi_w_mk`: signed W/mK | No manufacturer or color field |

All three kinds also accept `notes` (empty string by default) and `datasheet_links` (empty array
by default). Their semantic fingerprints exclude local identity, source attribution and
extension payloads. Export uses the same mapped values and retains local ids as wire row ids.
The synthetic file at `tools/examples/library/materials.json` includes all four kinds.

A copied Frame can assign to one element side, and a Glazing to one element, in the copy's
single Undo step. Psi-Install Types can assign to a perimeter edge or the Model default.
The Installs editor stages selected library identities and review choices; Save resolves the
catalog generation again and copies products with all assignments in one Undo step. Cancelling
that session makes no Model change.

## Versions, identity and limits

Envelope version 1 and all four wire kinds at version 1 are implemented. An unsupported envelope version
rejects that file. An unknown kind or unsupported kind version marks that library and kind
unavailable while other supported kinds can load. In folder mode, a malformed file produces a
code-only warning; valid neighboring files can load.

Record ids must be unique across all files sharing a library id and kind. A duplicate withholds
that entire library and kind. Different library ids may use the same record id. Files sharing a
library id must also agree on its name.

| Limit | Implemented maximum |
| --- | --- |
| One JSON file | 32 MiB, 33,554,432 bytes |
| All immediate candidate JSON files in a configured provider | 64 MiB, 67,108,864 bytes |
| Rows across their kind arrays, including unsupported kinds and skipped rows in parsed files | 20,000 |

The provider refuses an over-budget catalog rather than truncating it. These are implemented
bounds with exact-limit and one-above offline checks. Current-host measurements meet all three
limits; other hosts remain subject to their own acceptance checks.

## Copy and read back

The configured file or folder path stays in per-machine setup. Public catalog results and copied
source attribution contain stable ids, never that path. A successful load publishes an immutable
session generation; a failed refresh retains the last valid generation with its failure state.
Reconfiguring or removing a provider invalidates its session catalogs.

Copy resolves exact source identity first, then the local label, trimmed and without regard to
case. A local record without a label is matched by source identity only. Equal mapped values permit reuse;
different values require an explicit choice. Replacement preserves the local id and references,
with guarded authored values and metadata preservation. Optional assignment shares the copy's
single Model transaction. Preview and invoke use the same revision-bound copy timestamp for that
gesture. The timestamp is excluded from the semantic fingerprint.

The [public API reference](API_REFERENCE.md) describes catalog reads and guarded copy operations.
The [panel-closed walkthrough](../tools/examples/library/materials_walkthrough.rb) uses the
[synthetic fixture](../tools/examples/library/materials.json) in a Model with empty Materials and
Assemblies inventories. It removes its temporary provider configuration after read-back and
leaves the copied Material in the SKP. Native Undo/Redo and save/reopen are separate acceptance
checks.
