# 03. Libraries, Colour-by and external IO

Reviewed source: `library/`, `colour_by/`, `runtime/` and their registration contracts.

## Section-by-section assessment

| Section | Actual seam | Assessment |
| --- | --- | --- |
| Provider / Batch | Detached immutable catalog rows, freshness and code-only unavailable/warning data | Strong provider boundary; no Model writes |
| LibraryFile / FileProvider / Admission | Envelope parsing, wire-schema normalization, semantic admission and limits | Adapter-driven; one latent required-field assumption remains |
| Catalog / State / Setup | Per-session catalog generations and per-machine provider configuration | Keeps private paths and rebuildable catalog state out of the Model |
| Resolver / Coordinator | Source identity versus semantic content; explicit create/keep/replace/assign | Preserves editable Model-local authority; neutral coordinator names no built-in kind |
| CallbackInvoker / CopyParticipant | Owner callbacks, projected catalog reads, one shared proposal | Particularly useful extension pattern; feeds F04's uniform participant recommendation |
| ExportProjection / FileWriter / ExportWorkflow | Allowlisted reverse mapping, semantic round trip, digest and approved destination | Good proof of a format boundary; don't replace it with a dictionary dump |
| ColourBy::Entry / Service | Mode projection, legend rows, cache invalidation, filter/isolation | Open mode identifiers and no feature record knowledge |
| Tessellation / Overlay / Palette | Host geometry conversion and cached native drawing | Current implementation is surface-oriented; a mode alone cannot add line geometry |
| RuntimeHost / AssetServer / Http / Manifest / Gate | Lazy Pyodide dialog, pinned loopback assets, timers, resources and message correlation | An outer adapter; no live business calculation in the panel and no required hosted service |

## F05. A registered library kind can be valid yet fail because sorting requires `name`

**Classification:** reproduced contributor-contract defect. **Planning priority:** medium.

[Library kind registration](../../../../src/ph_composer/shell/registry_validation.rb#L489) validates
the adapter wire schema as an object and its mapping/callback protocols. It does not require a
shared `name` field. LibraryFile normalizes a schema with `id` and `label` successfully, using
`to_s` for its own sort. [FileProvider#merge](../../../../src/ph_composer/library/file_provider.rb#L119)
then calls `row.dig("snapshot", "name").downcase` without that normalization.

The probe registers a synthetic label-based adapter, parses its one valid row and obtains a
`NoMethodError` from FileProvider.list. The registered callback implementations are borrowed for
this boundary probe and never invoked; the demonstrated failure is wire-row sorting. All current
built-in kinds use `name`, so this is a latent adopter failure rather than a built-in catalog outage.

**Smallest adequate correction:** settle a neutral row-label contract. Either require a nonempty
`id` and `name` on every wire schema at registration and document it, or declare a display-label
projection per adapter and use it across Ruby admission and JavaScript tables. A fallback sort by ID
prevents the exception, but alone does not explain what the catalog UI displays.

**Verification:** a new kind with a different authored vocabulary either registers with an explicit
label mapping and lists/copies/exports successfully, or is refused at registration with an actionable
diagnostic. Cover file and outside-provider paths, optional/null label fields, and deterministic sort.

## F06. The geometry seams cannot yet serve ordinary Edges or derived line overlays

**Classification:** directly evidenced capability gap for planned features, not a defect in current
Face export. **Planning priority:** settle with Spaces/thermal bridges before dependent implementation.

An Edge mode is accepted because `entity_kind` is open prose, but
[Tessellation.each_face](../../../../src/ph_composer/colour_by/tessellation.rb#L81) only yields Faces
or Faces inside containers. [Overlay](../../../../src/ph_composer/colour_by/overlay.rb#L29) draws
fills and unclassified surface outlines/hatching; it has no contributed classified line primitive.
The probe supplies a native Edge and receives empty triangles and segments.

The same Edge, with an authored dictionary, also disappears from
[GeometrySnapshot.walk](../../../../src/ph_composer/export/geometry_snapshot.rb#L83): the non-Face,
non-container branch yields nil. Edges inside a component definition may be captured as native
definition facts, but ordinary occurrence Edges have no entries, identities, dictionaries or
adjacency in the shared export snapshot.

This is directly relevant to [the thermal-bridge PRD](../../phase-03b-thermal-bridges/PRD.md),
whose assignments live on Edges and whose exported runs derive from connected edges, and to its
planned line display. A contributor cannot supply those through the current capture/render
contracts alone. The existing feature plan already anticipates some shared extension; do not call
that planned work an overlooked current bug.

**Smallest adequate correction:** extend shared host capture with neutral Edge occurrence facts
(SI endpoints, path/transform, dictionaries and the connectivity/Face links the accepted run rules
need), and drawing with explicit typed surface/line primitives. Features still own run formation,
quantities, classification and colors. Do not put thermal-bridge names or run rules in export or
the overlay. Keep one traversal and one cached renderer.

**Verification:** synthetic Edge contributor needs no feature branch in shared capture/service;
nested/repeated/hidden/tagged occurrences remain distinct; ordinary Edges and transformed paths
are available to export; line widths and filtering follow declared mode data; current surface
fixtures remain valid. Measure large-model traversal/render costs and retain native acceptance.

## Observations to retain

Providers are optional factories rather than privileged server clients. Catalog copy and assignment
share the normal proposal and callback owner operations. Reverse mapping has a real semantic
round-trip check. These are the right interfaces for a firm's private catalog or workflow.

The runtime adapter is deliberately supplied only on demand and has its own lifecycle/resource
checks. It is not a general plugin sandbox or external-agent server. Changes to shipped Python or
runtime/panel assets would require the manifest and full gates; no such changes are made here.
