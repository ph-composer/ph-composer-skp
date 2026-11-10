# AW-05 · Complete occurrence, geometry and schedule reads

STATUS: Proposed, not authorized. ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/435 (review/planning publication only).
DEPENDS ON: AW-03 and AW-04 budgeting. FINDING: R07 occurrence portion. CONTRACTS: C03/C04.
ACCEPTANCE: A07b.

## Outcome

Agents can retrieve every Unit, restore target, calculated Face area and Thermal Bridge member or
finding, including a single object too large for one reply.

## Work

1. Add Window Unit field projection and exact metadata/detail retrieval using AW-04's contract.
   Keep native name, identity, host and state unambiguous; outlines are not a substitute for record values.
2. Make host extent compact, with independently retrievable outer-ring points, holes and neighbouring
   Units. Add scoped/paged gross/glazed/net-opaque Face results using existing area semantics, including
   withheld results and unhosted Units. Cover Assembly usage references without client recalculation.
3. Separate Zones' row page from restore offers and other whole collections. Include options adoption
   sources/usage where needed for complete recovery; keep the full panel projection.
4. Give Thermal Bridge runs compact fields and separate member Edge/geometry pages. Page every orphan,
   unreadable and per-run finding; do not repeat only the first 50 on all pages. Preserve coincident
   filtering and totals scope. Expose raw assignment inventory through AW-03, not a derived run as identity.
5. Measure Window conversion reviews with one large connected group. If oversized, give its reviewed
   group a stable detail handle/digest without splitting the apply scope. Audit Spaces' existing detail
   pages and envelope totals under the same contract; do not rewrite working readers gratuitously.

## Source and tests

Windows `units/{actions,areas,host_extent,outlines}.rb`, snapshot/declarations and conversion reads;
Zones `zone/operations.rb` list and options; Thermal Bridges `runs/schedule.rb`, `scan/occurrences.rb`
and schedule declarations; Spaces scoped reads. Extend existing area, placement, Unit, Zone, Spaces
paging and thermal schedule/export tests. Promote the retained 450-hole Face, 450-restore-target,
799-Edge run, 30 KB Unit and 180-Face cases. Add more than 50 orphan diagnostics.
Round-trip the reconstructed Unit metadata through guarded `update_metadata`, including both prior
maps, then read back; a concurrent metadata edit must refuse the whole write.

## Native gate and done

Read complete synthetic nested geometry and validate SI transforms against the host; compare area
and run totals with existing owner projections. No read moves the view or repairs a record. Each
query/detail page reaches the actual executor and reconstructs all expected rows without duplicates
or loss. Record main-thread time/fixture size separately from reply size; improve only measured
hotspots. Complete PLAN gates and update recipes/schema/reference through docs-pass.
