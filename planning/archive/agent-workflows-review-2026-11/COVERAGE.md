# Feature and data access coverage

Baseline: `f65ccee6`, API 1.31. Operation names below omit the leading `ph_composer.`. They describe
implemented contracts, not every input field. [discovery.json](evidence/discovery.json) is the full
operation/record inventory; `describe` and generated `docs/API_REFERENCE.md` are the schema sources.
“Available” means a supported source route exists, not that every native case was rerun here.

## Definitions and relationships

| Data structure | Read and discover | Create/update/delete and relationships | Assessment |
| --- | --- | --- | --- |
| Material | `assemblies.materials.list/all`, generic records; values, units, metadata, usage | Create/update/duplicate/delete; delete replacement retargets Layer-Segments | Available; typed summary projections work. Large arbitrary metadata needs detail retrieval, R07 |
| Assembly | `assemblies.assemblies.list/all`; layout, layers, segments, thickness, U-values, export readiness and findings | Create/update/duplicate/delete; named Layer and Layer-Segment insert/remove/move/resize/material operations, flip and air barrier; Face assignment via Zones | Strong programmatic parity with Builder. Large nested values/metadata must remain readable, R07; reserved export metadata preflight, R09 |
| Assembly Layer / Layer-Segment | Nested in Assembly, stable local IDs, Material references, dimension rules | Explicit child-targeted actions, each one proposal/Undo | No separate independent record lifecycle needed; a large parent needs bounded child reads |
| Building-Segment / Level | `zones.options.list/detail/usage/all`, `adoption_preview`; generic records | Options create/update/remove/merge/manage/adopt; default and atomic retargeting; Zone fields carry IDs | Available. Defaults/adoption live in larger `all` or settings record; usage mainly counts, targets reconstructed from Zones. Include these in budget audit |
| Zone option settings | Generic `records.list` for option-settings kind; combined options read | `options.manage/adopt` owns changes | Catalog discovery omission makes the generic read difficult to learn, R05 |
| Attached zone | Generic records kind; Face references show uses | Save/duplicate/delete with reference replacement; atomic `faces.attached_zone.create_and_assign`; classify with existing ID | Available once kind known. Generic discovery and metadata limits apply; a dedicated reverse-use page is optional |
| Frame / Glazing / Psi-Install Type | Windows product `.list/all`; thermal values, notes, provenance and metadata | Product create/update/duplicate/delete with supported reference handling; Type assignments | Available; preserve absent vs zero values and reference replacement |
| Window Type | `windows.types.list/all`; grid, elements, frame/glazing/install references, metrics, topology and copy slots | Create/update/duplicate/delete, grid gestures, flips, product assignment, `types.installs.save` | Broad parity; a valid 10 x 10 Type defeats current parent projections, R07 |
| Window Type elements / installation edges | Nested element IDs and layout; `display.install_topology`, classification, copy key/slots | Explicit element/edge params; installs batch save; scalar/default and assigned Psi-Install resolution | No picking requirement. Need bounded element/topology reader with identical domain results |
| Thermal Bridge Type | `thermal_bridges.types.list/all`; psi, group, colour, readiness, metadata | Create/update/duplicate/delete; replace or clear Edge references atomically | Available. Negative and zero psi remain valid; missing psi remains distinguishable |

Primary sources: `src/ph_composer/features/assemblies/declarations/`, `assembly/operations.rb`,
`materials/operations.rb`; `features/zones/options/commands.rb:10-31,71-142`,
`options/operations.rb:101-160`, `declarations/faces.rb:360-418`;
`features/windows/declarations/`, `types/`, `products/`;
`features/thermal_bridges/declarations/types.rb:45-139`; `shell/record_queries.rb` and
`shell/definition_lists.rb`. The registry inventory distinguishes exact names where a table groups a family.

## Geometry, occurrence records and assignment

| Data structure | Read and target | Authoring and repair | Assessment |
| --- | --- | --- | --- |
| Raw Group / Component / Face / Edge | Context exposes selected entities and edit path; containment/host_context resolve supplied paths | Native geometry is input; PH operations can group/split/place geometry within their owned workflows | No general child/candidate enumeration, raw drawing/transform/copy or document save/open, R06. General CAD authoring is a separate scope decision |
| Zone | `zones.list/all/selection/containment`; ID/path, fields, state, areas and recovery offers | Make from explicit existing geometry; update/update_field/update_metadata; independent/copy/split/identity/restore operations | Creation is explicit but initial IDs need discovery. Ownership/identity/lock gaps R01-R03; restore arrays R07 |
| Membership stamp | Reference target and Restore/adoption inventories | Indirectly maintained by classification/Zone/options/repair; Restore regroups eligible same-context geometry | Not ordinary CRUD. Recovery semantics are appropriate; page restore targets separately |
| Envelope Face | `zones.faces.list/all/selection/host_context`, stored classification, Assembly/Attached zone, area, metadata and state | Classify keep/set/clear; auto-classify; assign Assembly; reverse; metadata; explicit select/locate | Most semantic work available. Stale-null guard R02. Lists are not a general geometry/topology read; add needed detail through R06/R07 |
| Surface adjacency pair | Pair endpoints/proof in Face values and adjacency state; Solve and preflight findings | Scoped `zones.solve_adjacency`, `retire_adjacency`, split identity recovery | Available. Derived relationship does not need independent pair CRUD; Solve may split geometry and must retain its preview/Undo guarantees |
| Face Assembly assignment | `assembly_choices/assembly_usage`, Face values; counterpart state | `assign_assembly` or classify intent; paired interior side updated in same proposal; delete replacement retargets references | Available, panel-independent. Explicit expected values and reversed construction semantics must survive changes |
| Window Unit | `windows.units.list/all/selection/outlines`; native name, Type, host, placement/status/metadata | Place by explicit host/anchor/metre offsets; rename, remove, rehost, swap/reset Type, restore/return-to-host, flipped Type, copied-identity repair, metadata | Broad parity. Mandatory large metadata breaks readback, R07. A valid host extent reader already exists |
| Drawn rectangles converted to Windows | `windows.units.convert_review` returns reviewed groups/layouts/omissions | `units.convert` creates Types and Units atomically; optional copy-from Type; dialog is an optional human review route | Available with explicit known geometry; initial candidate discovery still matters |
| Window host geometry and calculated Face areas | `units.host_extent` provides placement frame, outline/holes and existing Windows; `units.glazed_area_by_face` computes gross/glazed/net opaque area | Read-only; place uses the same geometry rules | Bounding dimensions are available, contrary to stale help. Large holes and whole-model area table need bounds, R07 |
| Space | `spaces.list/all/findings.list`; values, metrics, Zone, Building-Segment and children counts | Create from existing floor Faces, typed update/batch_update, metadata, move-to-zone/unhost, independent, remove keeping floors or delete geometry | Strong semantic coverage after target acquisition. First-Space discovery R06; accepted-input receipt R04; cross-owner deletion R01 |
| Volume / logical Floor | `spaces.volumes.list(space:)`, volume metrics/state/protection, logical `floor_id`; scoped findings | Create/remove/unprotect/restore_position/height_from_solid, typed updates/metadata and context/locate | A logical Floor is derived one-per-Volume, not independent catalog data. Height-from-solid needs known/selected geometry; orphan discovery starts from findings |
| Floor Segment | `spaces.floor_segments.list(space: or volume:)`; optional loops, weighting, area/height metrics | `floors.mark/unmark`, typed update/batch_update/metadata, locate | Available. Actual floor outline editing remains native geometry |
| Unmarked floor candidates | `spaces.candidate_faces.list(space: or volume:)`, eligible operation and refusal, optional loops | Volume create or floor marking from explicit paths | Existing child workflow is good; root/plain-wrapper first-Space case missing, R06 |
| Thermal Bridge Edge assignment | `edges.selection` supplies complete refs/values; schedule supplies member paths | Explicit assign/clear, at most 250 Edges, one atomic Undo; pointer tool uses same action | No selection-free candidate or assignment-by-path read, R06. Unreadable/outside-Zone records lack semantic cleanup, R10 |
| Thermal Bridge run | `schedule.list/all`; derived ID, lengths, heat loss, totals/findings and member paths | Change member assignments or Type; `runs.locate` selects/frames | Correctly derived, no run CRUD needed. Large run and orphan findings require child pages, R07 |

Primary sources: `features/zones/declarations/{zone,faces,adjacency,repair}.rb`,
`zone/{operations,occurrences,steps}.rb`; `features/windows/declarations/units.rb`,
`units/{actions,areas,host_extent,outlines}.rb`; `features/spaces/{authoring,scoped_reads,create_faces}.rb`,
`declarations/{spaces,context,height_from_solid}.rb`;
`features/thermal_bridges/assignment/{selection,operations}.rb`, `runs/schedule.rb`,
`scan/occurrences.rb`. All paths start at `src/ph_composer/`. See the retained feature/envelope probes
for exercised operations and fixtures; native setup of those fixtures is explicitly separate from API calls.

## Libraries, metadata, validation and application state

| Surface | Agent route and current boundary | Assessment |
| --- | --- | --- |
| Provider setup / hosted libraries | `library.providers`, setup state; load, add approved file/folder, remove/reset; hosted provider descriptors and connection operations | Optional and provider-neutral. Native credential sign-in stays with the user. A loaded catalog is session state, so a read-only token may need a user/setup-granted caller to load it first |
| Catalog and in-file comparison | `library.catalog/in_file` scoped by provider/kind, optional generation and pages; source identity and copy decisions | No per-row filter/projection; warnings, notes and comparisons can exceed the transport budget at limit 1, R08 |
| Copy into model / replacement | `library.copy` preview/invoke; local copies; optional assignment and proposal participant | Uses normal owner operations, refs and Undo; optional assignment schema is opaque externally, R15. Provider text is untrusted data. Do not bypass the copy plan with raw dictionaries |
| Library export | `export_preview`, registered `export_file`, approved `.json` destination, scope and projection digest | Available; oversized omission detail can hide required review digest, R08 |
| `user_data`, sources, structured extension payloads | Definition/entity metadata reads; ordinary catalog operations write `user_data`; entity metadata actions and contributor-owned operations write structured payloads | No generic public mutation for every installed extension. Complete retrieval of a large accepted payload is missing on some readers, R07; extension descriptors are incomplete externally, R05. Export preservation varies by target; storing data does not promise export |
| Export preflight / repairs | Aggregate API preflight and feature queries; action names/params for supported repairs | Whole finding collections can exceed MCP cap; known metadata blocker misses preflight; runtime findings may differ, R09 |
| HBJSON task / report / bytes | Start/status/cancel/latest; caller ownership, approved destination, hash/size/path receipts; independent runtime lifecycle | Strong normal route; blocked-run diagnostic retrieval missing, R09. METr exporter is still deferred |
| Model feature settings | Zone suggestion settings, Space last height, Window install defaults exposed through owner get/update | Available; default inheritance and SI values should remain discoverable |
| Native selection / edit context / camera | `context`; explicit context open/root; owner locate/select routes; Colour-by selection | Read-only context is useful, commands are separate grants. No arbitrary native entity select or camera pose setter; current commands frame known targets |
| Colour-by / labels / overlay state | `colour_by.state/activate/filter/isolate/select_row/readout` | Accessible semantic state and view commands; capture does not show overlays, R14 |
| Capture | `view` tool invoking `view.capture` with separate capture grant; bounded image, provenance, retention | Geometry-only by contract; local-path delivery requires client filesystem ability, R14 |
| Display units / table layout / panel navigation | Panel protocol/preferences, not registered domain operations | Convenience gap, not missing PH data: APIs already publish SI units. Optional future public preference read/change can help shared view coordination; avoid exposing arbitrary panel DOM |
| Help / diagnostics / token management | Native Help & Diagnostics and Agent Access; private support report and call ring | Agent-issued tokens are deliberately forbidden. A bounded scoped incident/history reader is optional, R14; operating guide should be discoverable, R12 |
| Mechanical / equipment / ducts / piping / climate / sun path / METr | Existing product plans only; absent from current feature composition | Not access defects. Each future feature should satisfy the acceptance matrix below through registration, not adapter-specific branches |

Primary sources: `library/install.rb:24-36,87-150`, `library/connection/commands.rb`,
`library/export_registration.rb:68-96`; `core/records/metadata.rb`, `shell/record_queries.rb`;
`export/{tasks,task_contract}.rb`, `shell/dispatch.rb`; `colour_by/install.rb`;
`shell/{context_commands,preferences,support_report}.rb`, `agent_access/`. Confirm exact paths at
implementation entry because the concurrent feature program is changing source organization.

## Workflow acceptance that every future feature should meet

For each durable record, child collection and assignment, a client starting with only the installed
connection must be able to discover its schema, enumerate all relevant objects, inspect exact
references/values/units and derived results, preview and apply supported edits, retrieve the outcome,
read it back and locate it. If an action is intentionally native-only, publish that prerequisite
and a meaningful handoff. A missing inverse is acceptable when the product has no such operation;
an undocumented inverse required to repair the feature is not.

Use real transport budgets and empty initial selection, not only in-process calls over fixture IDs.
Exercise unassigned, invalid, unavailable-extension, orphaned and copied objects as well as healthy
ones. Test latest state and original failed-run state separately. Record what cannot be exported.
Retain native Undo/Redo, save/reopen and concurrent-user evidence at the owner that changes those
boundaries. This matrix supplements the existing Phase 4 and later packets without duplicating them.
