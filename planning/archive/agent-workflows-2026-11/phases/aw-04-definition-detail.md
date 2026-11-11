# AW-04 · Complete definition and metadata reads

STATUS: Complete. Merged to main (#443, `1996d6fe`), API 1.37; host case `AW04` pass. ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication.
DEPENDS ON: AW-02. FINDING: R07 definition/metadata portion. CONTRACT: C03. ACCEPTANCE: A07a.

## Outcome

Large accepted definitions, nested Window grids and arbitrary public metadata remain exactly readable
under the MCP reply budget. A small summary does not become the only available representation.

## Work

1. Define shared whole-envelope byte accounting and stable detail/fragment cursors using existing
   `Pages`, not a replacement query engine. Preserve whole panel queries and old field meanings.
2. Give generic `records.list` an explicit compact metadata policy/projection and a companion exact
   detail route. A single 30 KB value must be retrievable, not merely omittable. Bind fragments to
   source identity/revision and return typed reconstruction/hash information.
3. Add bounded Assembly Layer/Layer-Segment and Window Type element/topology/derived-result reads.
   Reuse the owner's existing thermal/topology calculations; do not reproduce them in clients or MCP.
4. Page or separately read potentially large use/reference arrays in definition rows. Keep unavailable
   extension status and unreadable record reporting visible without returning huge payloads by default.
5. Apply the budget contract to compound previews: keep a compact digest/summary and complete detail
   retrieval for the same inputs/revision. Prove that a large proposal can be reviewed and then applied
   without omitting consequences or holding a transaction open.

## Source and tests

`shell/{pages,record_queries,definition_lists}.rb`, record descriptors/view/metadata, Assemblies
snapshot/read paths, Windows snapshot/Type topology/thermal readers and declarations. Extend
`definition_lists_test`, `api_client_test`, `entity_metadata_test`, Window topology/records tests,
and add a transport-level case from `evidence/envelope_probe.rb`.

Required fixtures: valid 10 x 10 Window Type; oversized Assembly with many Layers/Layer-Segments;
one 30 KB metadata scalar; many metadata keys; large
uses arrays; absent/null/false values; unavailable extension; non-ASCII text across fragments.
Reassemble exact published values and derived topology; each full executor reply fits; concurrent
edit expires chunks and never mixes versions. Probe a synthetic outside catalog kind using only the
generic route. Include one oversized compound preview and digest/detail retrieval. No accepted-size
limit may be lowered just to make the test pass.

## Done

No Model mutation from any new read. Generated schemas/examples and guide show summary-to-detail
retrieval; original callers still work. Complete PLAN gates. A focused panel-closed native smoke
confirms host object projections; no new native transaction claim follows from pure pagination.
