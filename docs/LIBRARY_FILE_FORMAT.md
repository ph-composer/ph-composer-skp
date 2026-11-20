# Library file format

Use a UTF-8 JSON file or a folder of immediate JSON files to publish a library. PH-Composer
copies definitions into the SKP as editable records. The built-in wire kinds are `materials`,
`frames`, `glazings`, `psi_install_types`, `programs`, `schedules` and `equipment_sets`.

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
      "notes": "Synthetic example.",
      "datasheet_links": []
    }]
  }
}
```

Every envelope field shown above is required. `library.id` and `library.name` contain nonempty
text. `exported_at` is an ISO 8601 timestamp with a timezone. Each `kinds` entry is an array with
a version in `kind_schema_versions`. Every kind requires a row `id`, the provider's stable record
identity; PH-Composer gives a copied record its own local identity.

Each kind declares a display label from its values. The built-in kinds use `name`.
A missing or blank label skips the row with `library.row_label_invalid`. PH-Composer sorts by
library, case-insensitive label, original label and `id`, in that order.

Exporting local definitions publishes each local id as the wire record id. The optional
`record_origins` object groups informational origins by wire kind and exported record id.
An origin contains a sanitized provider-kind `label`, `provider_kind`, `library_id` and
`record_id`. Origins are informational. The reader and semantic fingerprint ignore them.

The export form defaults to all supported local definitions. Selected scope uses explicit record
ids and never derives its scope from a filter. New identity creates a library UUID; update keeps
the validated destination identity. A native review lists omitted local metadata and unsupported
records before a staged write replaces the destination. Cancellation or failure preserves its bytes.

## Materials version 1

Supply `id` and `name` on each row. Use SI numbers in the declared fields. Missing optional
fields use the defaults below and produce a warning. Invalid wire values skip the row.
Copy also validates the mapped Material, including hexadecimal color syntax.

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
carry local `source`, `user_data` or extension payloads. A Material copied from a library starts
with an empty `user_data` map. Replacing a local Material from a library keeps its local map and
extension payloads. When you export a Material whose record stores either one, the review before
the write lists that field as omitted. The [user data guide](USER_DATA.md) covers the map on every object.

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
by default). As for Materials, their wire rows carry no `user_data` or extension payloads: a copy
starts with an empty map, a replacement keeps the local map, and an export lists the maps it
leaves out. Their semantic fingerprints exclude local identity, source attribution and
extension payloads. Export uses the same mapped values and retains local ids as wire row ids.
The synthetic file at `tools/examples/library/materials.json` includes all four kinds.

A copied Frame can assign to one element side, and a Glazing to one element, in the copy's
single Undo step. Psi-Install Types can assign to a perimeter edge or the Model default.
The Installs editor stages selected library identities and review choices; Save resolves the
catalog generation again and copies products with all assignments in one Undo step. Cancelling
that session makes no Model change.

## Programs, Schedules and Equipment Sets version 1

These three kinds use the same envelope and identity rules. Values use the units the Program,
Schedule and Equipment Set records use, which `describe` lists for each kind. A row carries no
`source`, `user_data` or extension payloads.

**Schedules.** Supply `id`, `name` and `type`: `fractional`, `activity`, `temperature` or
`ventilation`. Give only the fields of that type's form; a field of another form skips the row.

| Type | Form fields | Missing value |
| --- | --- | --- |
| `fractional` | `start_h`, `end_h` (whole hours), `fraction_on`, `fraction_off` | On all day: 0, 24, 1.0, 0.0 |
| `activity` | `start_h`, `end_h`, `watts_on`, `watts_off` (W per person) | 0, 24, 120.0, 120.0 |
| `temperature` | `value_c` | 20.0 |
| `ventilation` | `periods`: `high`, `standard`, `basic` and `minimum` in that order, each with whole `hours` and a `fraction`, the hours totalling 24 | The standard period all day at 1.0 |

Every type also takes `days_per_week` (1 to 7, default 7) and `weeks_per_year` (1 to 52,
default 52). Because a row gives only its own form, a Schedule row is read with the
`library.row_optional_absent` warning.

**Programs.** Supply `id` and `name`. A Program has eight loads: `people`, `lighting`,
`electric_equipment`, `gas_equipment`, `service_hot_water`, `infiltration`, `ventilation` and
`setpoint`. Each load is an object holding any of its values; a missing load or value takes a new
Program's. A load may name `source`, the base program its values came from. A load names its
Schedules by their `id` in the `schedules` kind of the same library, such as
`"occupancy_schedule_id": "office-hours"`. Each named Schedule must be of the type its load reads;
a copy checks this and refuses with `validation.failed` otherwise.

**Equipment Sets.** Supply `id` and `name`. `devices` is an array of devices, each with its
`type`, one of the fourteen honeybee-ph equipment types, and any of that type's fields; missing
fields take the type's defaults. A device carries no `id`: PH-Composer gives each copied device its
own.

**Copying a Program.** Load the `schedules` kind as well as `programs`. Copying a Program copies
each Schedule it names in the same Undo step, or reuses the local copy of that Schedule from the
same library. The copy result lists each Schedule under `dependencies`. A Schedule that the loaded
`schedules` catalog does not hold refuses the copy with `library.dependency_missing`, and nothing
is written. A local Schedule with the same name and other values refuses the copy with
`library.review_required`. Replace that Schedule from the library first, or rename it, then copy the
Program again.

Exporting a Program also exports each Schedule it names, even when the selection or the chosen
kinds leave the Schedule out, so the file can supply it. An exported Equipment Set's devices carry
no `user_data`; the review before the write lists `devices[].user_data` as omitted.

A copied Program or Equipment Set can become the Model's default in the copy's Undo step. A
replacement of a local Equipment Set keeps each local device whose place in the list the library
device of the same type takes, with its `user_data`. It refuses rather than remove a device that
holds `user_data`. The synthetic file at `tools/examples/library/programs.json` holds a Program, its
two Schedules and an Equipment Set.

## Versions, identity and limits

Envelope version 1 and all seven wire kinds at version 1 are implemented. An unsupported envelope version
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

The provider refuses catalogs that exceed a limit.

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

See [library kinds](API_REFERENCE.md#library-kinds) for wire schemas. The
[copy walkthrough](../tools/examples/library/materials_walkthrough.rb) uses the
[synthetic fixture](../tools/examples/library/materials.json) to load a catalog, copy a Material
and read it back in a scratch model. The
[Program walkthrough](../tools/examples/library/programs_walkthrough.rb) does the same with the
[Programs fixture](../tools/examples/library/programs.json): it copies a Program with its Schedules
as the Model's default, then copies it again and reuses them.
