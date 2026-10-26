# Contributor architecture

DATE: 2026-09-30
STATUS: Accepted architectural direction. Registration, record kinds, metadata and extension data
merged through PR #1 from Phase 0 P0-D; see the example under `tools/examples/foundation/`. Phase 1
(PR #3, PR #6) added view commands, menu items, Colour-by modes, entity reference targets and
descriptors, and the `zones` feature built on them. Phase 2 (PR #15, merge `c687a73`) added
handler-side dependency reads, reference retargeters, table contributions, the library provider
and kind adapter contracts, registered file exports, and the `assemblies` and `windows` features
built on them.

PH-Composer exists to support an open-source community in the Phius sphere. A contributor
should be able to understand and extend one part without understanding the whole application.
Optimize for the amount a reader must learn before making a safe, useful change. Prefer explicit
code and stable boundaries even when they take more work or modestly more runtime resources.
Correctness, native host behavior and usable response times remain requirements.

This document owns contributor-facing architecture. [TECH_STACK.md](TECH_STACK.md) owns runtime
and host mechanics; [CODING_STANDARDS.md](CODING_STANDARDS.md) owns code-level readability rules.
Where a section below says it is implemented, the contract exists in code and is published in
[`docs/API_REFERENCE.md`](../docs/API_REFERENCE.md); the rest are requirements for their future
implementation, not claims that an API already exists. Feature scope and delivery order remain
with the owning packets.

## Organization and dependencies

Start with a modular application in one repository. Extract separately distributed packages when
a concrete adopter or independent release lifecycle justifies the additional maintenance.

Within the existing Ruby Model layer, separate pure domain records, calculations and validation
from SketchUp integration. Domain calculations accept explicit values and run without SketchUp.
Host adapters own geometry access, dictionaries, transactions and observers. Keep domain behavior
inside its owning feature unless several features need it and no feature owns it.

The foundation under `src/ph_composer/core/` keeps the split visible by file:

| Role | Files | Rule |
| --- | --- | --- |
| Pure values and rules | `json_value`, `json_walk`, `json_schema`, `canonical_json`, `deep_copy`, `vector3`, `face_geometry`, `schema_shapes`, record kinds, fields and validation (`records/record_kind`, `records/fields`, `records/authoring_fields`) | Explicit values in and out; no SketchUp constant. `tests/support/face_geometry_pure.rb` runs in a bare Ruby process and is the way to test a rule without the host |
| Application services | `records/engine`, `records/projected_engine`, `records/change_set`, `operations/proposal`, `operations/contributions` | Compose rules over records and proposals; reach the Model only through the adapters |
| Native adapters | `face_capture`, `records/dictionary_store`, `records/entity_store`, `operations/entity_scope`, `pick`, `view_framing`, `model_operation`; `diagnostics` asks the host only for its log folder; `support_dialog` drives the Save sheet, `UI.openURL` and the fallback message box | Every `core/` file that reads or writes SketchUp objects. `model_settings` and the services reach the Model through these |

The application shell supplies registration, commands and transport. Feature packages own their
operations and optional UI. The UI kit depends only on its published contracts, with no domain
calculation or honeybee dependency. Python translation consumes the authored snapshot; downstream
exporters consume HBJSON. Preserve the existing four-layer boundaries.

Zones, their Faces and the adjacency between them are one feature, `zones`
(`src/ph_composer/features/zones/`), because Zone containment, Face identity, stamps, Surface
endpoints and split and copy transitions are one authoring lifecycle. Its `install.rb` names the
layout: `zone/`, `faces/` and `adjacency/` hold each part's domain code and handlers, with pure
geometry and pair rules apart from the SketchUp write steps, and `declarations/` holds what each
part registers. Zone actions are `ph_composer.zones.*`; Face actions are `ph_composer.zones.faces.*`.
A feature that needs authored Face identity, such as window placement, depends on `zones` through
its queries, actions, reference targets and descriptors, never through its stores.

Features sit in three layers and depend only downward. Ed set this on 2026-10-01. The Ruby
feature dependencies, export contributors and translation sections all follow it: a contributor
reads another section only through `requires:`, which registration checks against the feature
dependencies, and a translation section joins an object another section built through a declared
attachment, so the section that builds Rooms names nothing attached to them (`context/CONTRACTS.md`,
"Translation sections and artifacts"):

1. **Definitions.** Materials, Assemblies, Frames, Glazings, Psi-Install Types, Window Types,
   Attached zones. A definition knows nothing about geometry or about what uses it.
2. **Geometry and assignment.** Zones and Faces. A Face names its Assembly, so `zones` requires
   the feature that owns Assemblies and reads them through its registered read.
3. **Things placed on geometry.** Window units, and later Spaces and thermal bridges. Each names
   a definition and sits on a host from the layer below.

A definition feature keeps one operations module per kind beside that kind's schema
(`Materials::Operations`, `Assembly::Operations`, `Types::Operations`; the three Window products
share `Products::Operations`, chosen by collection), with the reads and naming rules its kinds
share in the feature's `Definitions` module. Following one kind's create
never steps through another kind's branch. Declarations build params and results from
`SchemaShapes` (`core/schema_shapes.rb`), which each feature's `Shapes` module extends with only its
own constants.

A lower layer never names a higher one. When a definition is deleted with a replacement, the
references to it are rewritten by whoever declared them, through a foundation contract the
deleting feature calls without knowing who answers. When a higher layer has facts worth showing in
a lower layer's screen, such as how many Faces use an Assembly, its own panel module contributes
them. A feature that both requires another and is required by it is refused at registration.

Built-in features use the same public interfaces available to external contributors. A private
hook needed by a built-in feature exposes a missing public capability. Fix that contract before
presenting it as a supported extension point. Cross-feature access uses declared public contracts;
neither a global service locator nor an event bus should conceal business dependencies.

The handler-side dependency read and reference retargeter contracts are now implemented in the
foundation. Use `request.query` for a registered read of an explicitly required feature. A
reference owner registers `feature.reference_retargeter(name, target_kind:)`; a definition delete
calls `request.retarget_references` and gives its returned plan to `propose_delete`. The deletion
and all rewrites share one proposal and Undo entry. See [CONTRACTS.md](CONTRACTS.md), "Handler-side
dependency reads" and "Compound proposals", for schemas, refusals and final-state checks.

A feature's operations take their inputs as named arguments, beside the request that supplies the
engine, Model, session and revision. The declaration block unpacks `request.params` once and calls
the operation, for example
`Materials::Operations.update(request, proposal, id:, values:, expected_values:, user_data:)`. Anything
else that needs the same change, such as a library kind's assignment, calls the same operation with
its own values. A handler request is frozen. Only the foundation derives one (`request.with`), for a
nested read, a retargeter or a library callback; feature code never copies or alters a request, and
never reads another declaration's handler out of registration. Paged list queries are the
exception: they keep reading the request, because the shell's paging reads the cursor and the
filter from it.

Phase 2 built three features on these contracts. `assemblies` is a definition feature (layer 1)
and requires no geometry feature. `zones` requires `assemblies`, declares the Face's Assembly
reference and owns assignment, usage and retargeting. `windows` requires `zones` and spans two
layers inside one feature: Frames, Glazings, Psi-Install Types and Window Types are layer 1 and
call nothing in Zones; Window units and their placement are layer 3 and read Zones. Zones never
requires `windows`. The Assemblies inventory shows Face usage through a table contribution from
Zones' panel module, so the inventory names no Face.

A definition feature whose definitions have placed users keeps one authoring coordinator above its
operations. In `windows` that is `Windows::Authoring` (`features/windows/authoring.rb`): every
public command, library callback and library assignment that changes a product, a Type or the
Window defaults goes through it, and it runs one order: the copied-identity repair the feature
advertises on every action, the definition's record proposal, then what the placed Units must do to
follow it (a Type change moves them; a Type delete without a replacement removes its generated
definition). `Products::Operations`, `Types::Operations` and `Settings.propose` propose records only
and name no Unit, so they are tested with record dictionaries alone. The coordinator owns the
host-dependent order because only it sees both layers; it sits at the feature's top, not in the
definition layer, so the rule above still holds. A compound command that is its own coordinator,
such as the Installs save, runs the repair once and calls the operations directly.

The panel's files follow the same layers. The UI kit sits at the top of `html/`; the foundation's
own screens are under `html/sections/` (shell, Colour-by, Export) and `html/library/` (the Library
pane, its provider sidebar and the library export); each feature's screens are under
`html/features/<feature>/`, matching the Ruby feature of the same name. A module outside
`features/` depends on no feature module and names no feature id (`tests/panel_layout_test.js`).

Drawing dimensions use the kit's `workspace` facade: `ui.dimensionRule` renders a graphic SVG
rule from `{ axis, from, to, at, extension, points, scale }` in drawing coordinates;
`ui.dimensionValue` renders an HTML button or an accessible SVG value from
`{ text, label, svg, activate, className }`. Omit `svg` for an HTML button. Owners format units,
validate drafts and invoke their existing resize operations. `drawing_dimensions.css` owns the
shared rule weight, dots, value typography and drawing feedback; `--phc-dimension-scale` keeps
SVG text legible when its owner scales the drawing.

`ui.inlineDimension({ trigger, editor, input, compact, active, begin })` places an HTML dimension
value and its owner-supplied unit-bearing input in one slot. A click runs `begin`; returning `false`
refuses activation. Otherwise it reveals, focuses and selects the input. It returns
`{ root, trigger, show(active, focusTrigger) }`; the owner restores active state on repaint and
closes after acceptance or cancellation. The kit owns presentation only. Owners retain UnitField
parsing, units, blur/Enter/Escape policy, pending/refused drafts and resize operations.

`unit_field.ValueBubble` wraps one `UnitField` in an anchored Bubble. Supply a trigger/title or an
existing Bubble, the field descriptor and SI value, an `apply(value, accepted)` callback, and the
owner's `busy`/`active` predicates. Enter, blur and outside close share one commit path. Invalid or
refused drafts stay open; `refuse(message, focus)` shows the owner's refusal, and `accept(value, focus)`
settles a snapshot-driven request. Acceptance callbacks are invalidated by retries and disposal.
Escape restores and closes; a pending request holds the surface until the owner settles it.
Persistent fields remain subscribed until `dispose`; `once: true` disposes after closing a one-use
editor. Owners retain exact mutation parameters, transaction rules and snapshot authority.

For a drawing editor, `new ui.Bubble(trigger, title, { detachedTrigger: true })` leaves the
trigger in its original drawing parent. Mount `bubble.root` outside the drawing's scrollport
and any transformed ancestor. The Bubble retains trigger activation, focus, hover and dismissal;
use `ownTrigger: true` when an SVG value's owner already handles activation. This avoids a CSS
transform making a fixed editor use label-relative coordinates instead of viewport coordinates.

The panel has three contribution seams. `panel.section(name, render, { pane })` registers a
feature's section renderer in a pane ([TECH_STACK.md](TECH_STACK.md), "Panel"). The top-level tabs
and their panes are static markup in `index.html`, so a feature that needs a new top-level pane
edits `index.html`, which is a composition-root edit the rules permit; a section added to an
existing pane needs no markup.

A pane has three regions, and a section names one with `{ region }`: `main` (the default),
`inspector` or `tools`. Any other name is refused at registration.

`inspector` is one column beside the work surface that shows a single section. Each inspector
section names a `tier`, one of `tool`, `selection`, `record` or `ambient`, and may give
`when(state)`, which answers false, true or `"hold"`. The section shown is the first that holds,
or else the first that answers true, by tier in that order and then by `order`. A section holds
while it carries a draft the user must not lose sight of, so a tool started from the viewport
cannot hide it. With nothing to show the column is away, unless the pane keeps an always-wanted
`ambient` hint ranked last (`order: 1000`) so its work surface never changes width. A pane may
instead have no inspector and carry its selection's controls in the kit's floating selection bar
(`selection_bar.js`), as Zones / Faces does. If the section that had the focus is
hidden, the focus moves to the one now shown. A control that would open another inspector
section asks `panel.inspectorHeld(pane)` first and says why it cannot.

The kit owns visibility, here as with tabs: every section renders on every snapshot whether or
not it is shown, because rendering is how a section consumes its results. `when` runs after the
render pass, so it may read what its section's render just worked out.

`tools` holds view controls for the work surface's control row. The work surface places them
with `panel.region(pane, "tools")`, taking the pane from its own root. `actions` holds authoring
tools, the ones that change the Model, for the page header's toolbar; the work surface places them
with `panel.region(pane, "actions")`. A pane that offers either must place it; until it does it
leads the main region. A feature adds an inspector section, a tool or an action to a pane it does
not own without naming that pane's owner, which is how Classify faces (an
action, with its palette in the Zones / Faces selection bar) shares that pane. A pane whose sections all
use `main` is laid out as before.

A feature that owns a tab says so once with `panel.workedOn(prefix, tab)`, where `prefix` is its
feature id, which every section it owns starts with. A foundation screen then asks
`panel.tabFor(owner)` for `{ tab, label }` and can send the user to the place a gap is looked into
without naming a feature: Export does this with the section of each group of findings. The longest
registered prefix that is the owner, or ends at one of its dots, wins; an owner no feature registered
returns null. It is one tab per feature: a finding one feature reports about a record another tab
edits still opens the reporting feature's tab.

A view may also restate a refused or failed outcome of its own request in its users' words with
`panel.outcomeText(translate, { owner })`, which returns a disposer. `translate` receives a detached
copy of `{ request_id, session, outcome }` and answers a string or declines with null; it must
check that the request is its own, as the Zones screen does. A translator that throws or answers
anything but a string is skipped and logged under its `owner`, and the result still reaches its
requester. The host's message, code and tone stay the contract; the first nonempty string replaces
only the notice's words.

Shared UI hints use `ui.tooltip(node, text)`: a nonempty string sets `data-tooltip`; an empty
string clears it. The helper removes native `title` attributes so browser hints cannot obscure
the panel's styled tooltip. Keep the control's accessible name in `aria-label`; the tooltip
layer supplies its description while shown. SVG hints follow the same contract instead of
adding a `title` child. The panel attaches one shared layer across features and modal dialogs;
a standalone surface can call `ui.attachTooltip(root)`, which reuses an ancestor's layer.

The other two seams add to a screen another module owns:

- `ui.contributeTable(tableId, contribution)`, below, adds columns and row actions to another
  module's named table. Zones' Face usage column in the Assemblies inventory
  (`html/features/zones/assembly_assignment.js`) is the built-in example.
- `library.registerSurface(spec)`, exported by `html/library/section.js`, adds a record inventory
  to the Library pane. The spec is `{ id, label, order, recordKind, createLabel, build }`;
  `build(root, state, send)` returns the surface's view with `records`, `guard()`,
  `render(state)` and `dispose()`. A `recordKind` makes the surface's selected rows exportable
  through the view's `inventory`, which is an `html/inventory.js` `Inventory`; a `createLabel` puts
  a "+ New" button in the pane heading that calls the view's `create()` and is enabled by its
  `canCreate()`. The pane throws when a view lacks a member its spec needs. Surfaces appear by
  `order` (the built-ins use 10 to 32; an omitted order is 0), then by id. The `id` is also the
  sub-tab key the pane remembers for each Model session. Register when the module loads:
  the pane builds its surfaces once per Model session. A surface's tab-specific settings go in
  the `settings` option of its `Inventory` config, an array of nodes the feature owns, which the
  kit appends at the end of the action bar after the view controls; the Psi-Install Types tab's
  Model defaults (`html/features/windows/inventory.js`) are the built-in example. Every built-in
  inventory uses this seam: Materials (`html/features/assemblies/materials.js`), Attached zones
  (`html/features/zones/attached_zones.js`) and the Windows products, whose
  `html/features/windows/section.js` registers Frames, Glazings and Psi-Install Types from one
  definition table in a few lines. Shared inventory mechanics are in the kit:
  `html/inventory.js` (the table, view controls, cell and range edits) and `html/inventory_forms.js`
  (the color picker and Delete with a replacement).

`ui.contributeTable(tableId, contribution)` registers columns and row actions without retaining a
snapshot. The owner calls `ui.composeTable(tableId, options, state, send)` for each paint.
Callbacks receive the current row and snapshot; contributed actions invoke their own registered
operation. Duplicate column or action ids refuse composition. The returned registration disposer
removes the contribution. An absent contributor leaves the owner's table intact.

Snapshot sections using the same query and equal parameters share one read within one build.
Each receives a detached outcome; no Index or result survives into the next build. This lets the
Face table and Assembly usage share one walk while keeping the shell independent of feature names.

## Contribution contracts

Use several small contracts. A contributor implements only the capabilities their contribution
needs. One explicit registration entrypoint declares its dependencies and capabilities; class
names, monkey-patching and incidental load order must not discover behavior.

| Contribution | Owns |
| --- | --- |
| Record kind | Schema, identity and reference rules, validation and persistence behavior |
| Feature | Cohesive operations, optional UI and registrations |
| Importer | Source parsing and a proposed set of model changes |
| Library provider | Catalog definitions through the neutral library contract |
| Export contributor | Feature-owned data for canonical translation and its findings |
| Exporter | Conversion of HBJSON to another format |
| Colour-by mode | Values, colouring and legend information |
| View command | A change to what the host shows: selection, camera, the active Colour-by mode |
| Setup command | A change to session or machine state that never reaches the Model: library setup and loading |

An importer does not write raw model dictionaries. The application validates its proposed
changes and applies accepted changes through normal model operations and Undo. A model importer
and a library provider have distinct contracts even when both read JSON.

Feature action schemas register with the action interface. The shell owns common transport
envelopes; ordinary feature actions do not require new feature-specific message types in a central
table. Registries must diagnose duplicate registrations, missing dependencies and incompatible
contract versions. Keep supported public APIs distinguishable from implementation details.

Implemented registration checks: the JSON Schema subset's keyword values (counts, bounds, text,
an anchored `pattern` that compiles, non-empty enums whose values fit their type, no lower bound above its upper, a closed object requiring only what it declares); a description, a callable
handler and examples for every query, action, view command, setup command and file export, where an operation whose params
accept `{}` may omit examples and every example must validate; participants checked the same way,
with their `participants:` edges resolved against the caller's dependencies; callable menu items,
subscriptions and Colour-by projections; and a described `noun.condition` form for each
`feature.code`, declared once, under a noun no other feature declares and outside the foundation's
nouns. A test over the built-in registry
(`tests/api_reference_test.rb`) also requires a description on every top-level param, and an id
param carries the `pattern` of its prefix, such as `^asm_[A-Za-z0-9]{12}$`. Write each operation's
description, Undo name and side effects by hand at its declaration, not by interpolating its name. Every published declaration owns
deep-frozen copies of its values, and record kinds copy theirs when built, so a test or a
contributor registers a new declaration rather than editing one: editing a builder you kept after
install changes nothing. Store admission, the publish order and the ownership rule are in
[CONTRACTS.md](CONTRACTS.md), "Registration".

A feature names each condition it reports by one code under its own noun, built where the condition
is detected and never derived from message text, and declares it once with `feature.code`
(`features/windows/codes.rb` is the example). The same code reaches every read, refusal and export
preflight row; a finding that a single action repairs names that action and its params rather than
leaving the panel to derive it (`ph_composer.windows.units.list`). A feature that depends on another's
readiness reads a published field, such as `export_ready` and `export_blockers` on
`ph_composer.assemblies.assemblies.all` rows, rather than matching that feature's codes.

Every query, action, view command, setup command and file export declares `refuses:`, the codes it
can refuse with beyond the common sets of its kind (context/CONTRACTS.md, "Outcomes and codes").
A small operation lists them at its declaration:

```ruby
feature.action("ph_composer.zones.settings.update",
               :description => "...", :params => params, :result => result,
               :undo_name => "Change Zone Settings", :side_effects => "...",
               :refuses => %w[record.unreadable target.changed validation.failed]) { |request, proposal| ... }
```

Operations registered in a loop share one list, and a feature whose operations share paths keeps
named lists beside its `codes.rb` (`features/windows/refuses.rb`). A code reached through a dependency's query,
locator or participant counts, because it reaches the caller unchanged. Registration refuses an
operation without `refuses:`, a code nothing declares, another feature's code unless the operation's
feature requires it, a repeat, and a code its common sets already hold. The offline suite installs a `Refusals.audit` that fails any test whose operation refuses
with a code outside its list and common sets, so coverage keeps the lists complete: a missing code
is declared, never suppressed. A library kind's local callbacks declare their own `refuses:` lists.
The effective list for `ph_composer.library.copy` includes every installed kind's `local_read`,
`create`, `replace` and optional `assign` refusals; `ph_composer.library.in_file` includes only
`local_read` refusals. Discovery, generated references and the audit use the same projection.
The coordinator lists its own failures and names no receiving feature.

A composition-root registration or generated build inventory is permitted. Requiring a new
feature branch inside shell, session, export orchestration or UI-kit internals is a contract
defect. Explicit registration does not promise dynamic plugin loading, a marketplace or separate
installation in the MVP.

### Records inside a Zone occurrence

A feature whose records live inside Zone occurrences (Window Units and Spaces) follows the
Zone when an occurrence becomes independent by declaring a transition contributor for
`ph_composer.zones.occurrence_independent` ([CONTRACTS.md](CONTRACTS.md), "Compound proposals").
Zones names no child: its action lists the transition, and each child adds its own restorable step to
the same proposal, so the copy, the Zone repair and every child's repair are one Undo step. The child
owns its records and plans only inside `zone_path`. Make Unique replaces the entities inside the copy
before the child's step applies (measured, [SKETCHUP_HOST_BEHAVIOR.md](SKETCHUP_HOST_BEHAVIOR.md),
"Window Units inside a copied Zone"), so the step binds logically, by record id and pre-image,
re-enumerates at apply, refuses drift with `target.changed`, and restores what it wrote. Payload
references are remapped with the description's `mapping` and typed `references`. Windows is the
first example (`features/windows/units/zone_copy.rb`); Spaces the second (`features/spaces/zone_copy.rb`),
which reuses the plan and step of its own Make independent over the Zone's path. A Zone stamp on a
container a child keeps is Zones' to rewrite, never the child's. A test-only second child built from public contracts
alone is in `tests/support/zone_child_fixture.rb`. The accepted pattern and why containment and
implementation ownership stay separate are in
[ZONE_CHILD_PATTERN.md](../planning/archive/code-review-refactoring/ZONE_CHILD_PATTERN.md).

### Library providers and kind adapters

`feature.library_provider(name, contract_version: 1, kinds: [...], &factory)` registers a
factory that is called with the published registry and returns configured provider instances. Named wire kinds must already
have adapters in the registration batch. `kinds: ["*"]` explicitly serves all registered wire
kinds; the wildcard is exclusive and cannot mix with named ids. The file provider uses this
capability, so adding an adapter requires no edit to its declaration. A factory reads the registered
library kinds from the registry it is given, never `Registry.current`; a lambda factory must take that one argument. It receives no Model
or request; private configuration belongs to the provider and its setup store.

`feature.library_kind(name, contract_version: 1, record_kind:, adapter:)` registers the owner's
adapter for a catalog record kind it owns. Entity reference targets cannot be imported as catalog
kinds. A wire kind has one adapter. `Declarations::LibraryAdapter` declares `wire_kind`,
`wire_version`, `fingerprint_version`, `wire_schema`, `mapped_schema`, ordered `fingerprint_fields`,
`display_label`, `map`, `reverse`, `fingerprint`, `local_read`, `create`, `replace` and optional
`assign`. Supported contract, wire and fingerprint versions are 1. The wire schema must declare `id`
as a required string. `display_label` is `->(mapped) { text }`: the shared library UI, admission
ordering and copy resolution read it, so a kind needs no `name` field. Admission skips a row whose
label is not nonblank text, or whose projection raises, with `library.row_label_invalid`; a local
record without a label is resolved by source only. The development example
`tools/examples/library_provider/` registers such a kind. Fingerprint fields are unique mapped-schema
property names in canonical order. Pure mapping and reverse mapping use detached values; the
fingerprint returns a lowercase SHA-256 hex string and excludes provenance and local identities.

Local operations are `Declarations::LibraryCallback` values with `params`, `result` schemas,
`refuses:` and `handler(request, proposal)`. Use an empty refusal list when the callback has no
specific refusal. Registration validates these lists like operations: declared own-noun codes,
shared foundation codes, or another owner's codes with an explicit dependency. Do not repeat
the common codes all operation kinds share or dispatch-only codes. Published lists are detached
and frozen. The request's engine is projected through the caller's proposal
(`engine.projected`): every engine read sees the records the proposal has staged. Local reads
receive no mutable proposal and cannot stage writes. They return detached
projections with `id`, semantic `mapped` values, raw authored `expected_values` and optional
`source`. Create and replacement run under the adapter's owner and share the coordinator's
proposal. Their schemas describe the owner's normal values and guards. Replacement preserves
identity, references and metadata. Optional assignment accepts the generic wrapper
`{ "target" => owner_target, "local_id" => copied_id }`; only the kind owner translates the
wrapper, by calling the operation its assignment action calls. Copy and assignment refuse together.

A feature requiring `ph_composer.library` may join a library copy to its own proposal: its action
lists `participants: ["ph_composer.library.copy_into_proposal"]` and calls
`request.participate("ph_composer.library.copy_into_proposal", copy_params)`. It is the shipping
example of a proposal participant, whose declaration and invocation rules are in
[CONTRACTS.md](CONTRACTS.md), "Compound proposals"; the Windows Installs save is its caller. It uses
the public copy operation's closed parameter and result schemas and the same trusted catalog
resolution and owner callbacks, inside the caller's active proposal. Preview remains detached; the
enclosing action provides the only native transaction. Any participant refusal poisons the caller's
active proposal, even when the caller catches it. This supports staged imports without exposing a
nested action dispatcher.

Registration validates ownership, unique ids and supported versions, plus schema and callable
contracts. Any diagnostic refuses the whole batch. Published declaration metadata and schemas are
defensively frozen. Invocation validates detached inputs and results and enforces catalog write
ownership, with refusal retained on the shared proposal. These checks supplement the trusted Ruby
contributor contract; callbacks never write raw dictionaries or open their own Model operation.

Provider row admission and coordination live under `library/`. A record kind's adapter lives in
its owning feature; adding one requires no case in the neutral coordinator. Materials is the
implemented example at `features/assemblies/library_kind.rb`. Providers use the
[published file envelope](../docs/LIBRARY_FILE_FORMAT.md). The
[panel-closed walkthrough](../tools/examples/library/materials_walkthrough.rb) uses public reads
and actions after private per-machine setup. The separate synthetic provider extension at
`tools/examples/library_provider/` passes the shared provider contract, load-order diagnostics,
registration refusal and panel-closed public API copy/read-back on both Rubies. Its native
installation and standalone repository remain open. A connection provider is still proposed.

### Registered file exports

`feature.file_export(name, description:, params:, result:, refuses:, examples:, &handler)` declares a
synchronous file write under the owner's namespace and the explicit `export` grant. It runs
without a Model proposal, sequence or Undo operation. The handler receives the validated request;
the result is detached and validated against its declared schema. A destination only the user can
choose is declared, not asked for: `approval: Declarations::Approval.new(kind: "save_file", title:,
default_name:)`. The handler then reads `request.approval.path` and `.replace`, opens no dialog, and
refuses an existing destination the user did not agree to replace. A setup command takes the same
`approval:` with kind `open_file` or `open_folder`. A check that can refuse before any location is
chosen, such as a stale `expected_revision`, is declared as `precondition: ->(request) { }` raising a
coded error; dispatch runs it before a native dialog opens and again before the handler. The panel
and native menus obtain the answer through `NativeApproval`, a shell internal and not a supported
API.

Every other caller passes a location the user approved, and the declaration gets that for free:
registration adds the optional `location` param to its params (a feature schema that declares or
requires its own `location` is refused), dispatch resolves the id into the same `request.approval` and hands the
handler params without it, and a call with neither answer is refused with `access.user_required`
([AGENT_INTERFACE.md](AGENT_INTERFACE.md), "Locations only the user can choose"). From a location,
`request.approval.state` is the destination state the caller reviewed and `.location_id` is set;
from the native dialog both are nil. Dispatch refuses `replace` without `expected_destination`, so
a location's consent always names a reviewed state; a save handler that can replace a file compares `state` with
its own fingerprint of the destination, as `Library::ExportWorkflow` does with
`Library::FileWriter.state`, and its preview reports that fingerprint through
`ApprovedLocations.observe(id) { |path| ... }`. Test the location route offline by approving a
temporary path with `ApprovedLocations.approve(kind:, path:)` and calling the public API with its id
(`tests/approved_location_use_test.rb`). Ruby contributors remain trusted code and own safe writes.

The library exporter uses reverse mappings from each registered kind and checks semantic equality
after mapping the wire row back. Invalid or lossy reverse mappings refuse in `export_preview`, which
the panel reads before it offers the save dialog, and again in the export itself.
Local record ids remain the wire ids; attribution is informational and excluded from semantic
comparison. Only declared wire fields and sanitized origins reach the file.

### Colour-by modes

Implemented in P1-D. A feature declares a mode in its own `install`, through the same
`FeatureScope` its queries and actions use:

```ruby
feature.colour_mode("ph_composer.zones.by_zone", label: "Zone", entity_kind: "zone",
                    colours: ColourBy::Palette.ramp) do |read|
  Zones::Occurrences.zones(read.model).map do |zone|
    ColourBy::Entry.new(entity: zone.entity, transform: zone.transform, path: zone.path,
                        value: zone.record.fetch("id"), label: zone.record.fetch("name"))
  end
end
```

The mode owns a pure projection over its own feature's entities and a colour function over the
values that projection produces. The projection receives a read request, the shape a query handler
receives, with no params and no proposal: `read.model`, `read.engine` for its owner's records, and
`read.query` for a declared dependency's registered read. Zones' Assembly mode reads Assembly names
and colours that way. A projection never connects to the public API. `entity_kind` is open prose: the service tessellates whatever
entity an entry carries, so a later feature may colour a kind this one never anticipated. An
entry's `transform` maps that entity's own contents to world. A value of nil is unclassified, and
a projection that knows a record is only half filled in says `state: :incomplete`; the service
owns the appearance of both, so those two states look the same in every mode.

A legend row's state answers for the one field its mode paints. The Faces table's row state answers
for the whole record, and is stricter about two things a mode cannot see without a Model walk: a
dangling Attached zone reference and an adjacency that has gone stale. A Face can therefore read
complete in the viewport and incomplete in the table. Both call a Face with no record unclassified.
In the Face type and Boundary condition modes, a record missing the painted field is incomplete in
both. An Assembly is optional, so the Assembly mode shows a record with no `assembly_id` as
unclassified while the table can call it classified. Neither is the validation register, which owns
severities and finding codes.

An entry's `value` is the legend's key, a string, and the legend's select and isolate commands send
it back unchanged. When the colour is a property of the record a value names rather than a function
of the value (an Assembly's own colour), the entry supplies `colour: [r, g, b]` and the service uses
it ahead of the mode's colour function; Zones' Assembly mode does this, with a colour function that
answers nil. The ramp colours one value at a time, so two values can share a hue; a projection that
must tell every value apart supplies each entry's `colour` from `ColourBy::Palette.spread(values)`,
distinct up to the ramp's length, or passes its entries through `ColourBy::Palette.spread_entries`,
which colours those without a colour of their own. Every built-in ramp mode does one or the other.
An entry's `label` may be a list of parts, as a readout line is (plain text or `[quantity, si_value]`), so
a unit-bearing label ("2.5 m") follows the display units; and an entry may supply `figure`, one
`[quantity, si_value]` the legend sums per row and shows beside the count, or a list of them summed
position by position and shown joined ("60 m³/h / 40 m³/h"); Spaces' modes sum weighted area, airflows,
floor area or net volume. Labels and figures are formatted where they are shown, in the HUD and in
`colour_by.state`, never at rebuild, so a unit switch needs no rebuild. A row sums the same quantities
throughout; an entry giving others, or a figure that is not quantity pairs, fails the mode.
An entry may also supply `hatch_outline: false` to retain its unclassified hatch while leaving
boundary edges to SketchUp. Omission preserves the solid unclassified boundary. This flag affects
only the unclassified rendering; classified fills keep their existing colour and geometry.
The Assembly mode uses it for Faces with no assigned Assembly so native selection edges remain visible.

An entry may supply `path`, the full root-to-entity array of persistent IDs. Supply it when
the entity belongs to an occurrence inside Groups or Components: the shared renderer then
checks hidden and tag visibility along that occurrence's entire path. A tag is hidden while it, or
any tag folder holding it, is hidden; a tag or tag folder change rebuilds the drawing. Supplied paths with missing
entities or mismatched endpoints draw nothing. Omitting `path` preserves the original entity-only
visibility contract.
Visibility affects the drawing; the legend continues to count the mode's complete projection.
The view command `ph_composer.colour_by.filter` accepts `paths: null` to colour all geometry,
`paths: []` to mute all geometry, or full persistent-ID occurrence paths to colour matching geometry
and mute the rest. Container projections partition their geometry at each Face, so a mask can match
part of a Group. Paths include descendants and distinguish repeated occurrences. A projection
without a path is muted under an explicit mask because its occurrence cannot be identified.
The mask is session state, retained through mode switches and while Colour by is off. This command
supersedes row isolation and writes no records, visibility flags or Undo entries.

A mode may also declare `group:`, a name several modes share, so a screen can offer them from one
place without naming a mode another feature owns: the Zones / Faces Assembly column binds to
group `"construction"`, which Zones' Assembly mode and Windows' Window Type mode declare. A group
name is a public contract between the features that declare it; a feature that renames one changes
what other screens offer. In the panel, `sections/colour_by.js` `HeaderToggle({ mode })` or
`HeaderToggle({ group })` binds a column header to a mode or a group, and `modes(state)` lists every
registered mode for a screen's options menu. `colour(state, binding, value)` supplies an active
mode's swatch for a matching column's Show choices. `filter(state, paths)` coalesces a screen's
occurrence mask through the public view command. The panel has no legend strip; row selection
and isolation remain public view commands for scripts.

A mode may declare `stroke:`, the width in pixels of the lines its derived shapes draw ("Colour-by
derived geometry"). Thermal bridges' mode, which draws Edges, declares 5.

The shared service owns registration, the one `Sketchup::Overlay` a Model gets, the viewport HUD
legend and cache invalidation. It reads no record and knows no mode, and turning a mode on writes
nothing to the Model, so it is not a registered action: it is reached through the native Colour by
menu, which is built from whatever modes are registered, and read back through the registered
`ph_composer.colour_by.state` query. Nothing in `shell/` or `session/` names a mode or a feature.

### Colour-by derived geometry

Implemented in P3a-05. An `Entry` may carry `derived:`, world-space shapes the service draws in the
entry's colour and state, with or without a backing entity:

```ruby
ColourBy::Entry.new(path: volume.path, value: "2.50", label: "2.50 m",
                    derived: ColourBy::Derived.new(polygons: [floor, roof, *sides], segments: []))
```

- **Shapes.** A polygon is one planar outer loop of three or more points, convex or concave, with
  no holes; the service triangulates it in its own plane and outlines its loop. The projection owns
  planarity: a loop whose points are not coplanar is degenerate, as are collinear, repeated or
  non-finite points and a loop that crosses itself, and a degenerate polygon draws nothing rather than
  being fitted to a plane or drawn in part. A segment is two points, drawn as a line. Nothing raises
  inside `draw`; a malformed `derived` (not points, wrong arity) fails the mode through the existing
  route, so the viewport shows Off and a warning.
- **Coordinates.** Points are `Geom::Point3d` in world coordinates in SketchUp's inches, as every point
  the host hands a projection already is, whatever the Model's display units. The projection owns the
  conversion, from SI values or local coordinates, through the occurrence transform it already holds;
  the service converts nothing.
- **Appearance.** Polygons fill and outline in the entry's colour: translucent, lifted toward the eye
  and depth-tested like Face fills; an unclassified entry's polygons take the hatch and an incomplete
  one's the amber. Segments and outlines draw at the overlay's outline weight, or at the mode's
  `stroke:` when it declares one: a whole number of pixels from 1 to 10, checked at
  registration, set once before the mode's line batches are drawn. It widens every derived line the
  mode draws, polygon outlines included, and nothing else: unclassified outlines and the hatch keep
  their own weights. An entry with both an entity and shapes draws both.
- **Edges.** An Edge contributes no Face geometry, so an entry whose `entity` is an Edge draws only its
  shapes. Thermal bridges' mode gives each assigned Edge occurrence one world segment, so the Edge
  still serves visibility along its path, select and Locate, and Show only this:

  ```ruby
  feature.colour_mode("ph_composer.thermal_bridges.by_type", label: "Thermal bridges",
                      entity_kind: "edge", stroke: 5, colours: ->(_value) { nil }) do |read|
    Scan.walk(read.model).first.map do |edge|
      ends = [edge.edge.start, edge.edge.end].map { |vertex| vertex.position.transform(edge.transform) }
      ColourBy::Entry.new(entity: edge.edge, transform: edge.transform, path: edge.path,
                          value: type_id, label: type_name, colour: type_rgb,
                          derived: ColourBy::Derived.new(polygons: [], segments: [ends]),
                          figure: ["length", metres])
    end
  end
  ```
- **Visibility.** With `path`, shapes are drawn only while every entity along the path is visible
  (not hidden, tag visible), the same walk the service makes for an entity; with no entity the path
  still names the occurrence the shapes belong to, so the identity check against `entity` is
  skipped. Without `path`, shapes are drawn whenever the mode is, and are muted under an explicit
  occurrence mask, as an entity entry without a path is.
- **Mask and isolation.** The occurrence mask (`filter`) and Show only this apply to the entry's path
  as a whole; shapes are not partitioned. A muted or set-aside entry's polygons join the wash and its
  segments are not drawn.
- **Legend.** One entry counts once, whatever it carries. An entry with neither entity nor shapes
  draws nothing and still counts. Select and Locate act on entries with an entity; shapes alone frame
  the view but select nothing, so a row of shape-only entries is framed and answers that nothing was
  selected rather than refusing.
- **Cache.** Shapes are built at rebuild into the per-colour fill batches and one per-colour line
  batch; the drawing stays whole and keyed on the session revision, and `draw` computes nothing.
  Readouts are cached beside it, keyed on the revision and, for a `selection: true` readout, on a
  selection generation the service advances on `selection_changed`, which the revision does not.
- **One line primitive.** Coloured lines are derived segments. The deferred geometry stage's
  `ColourBy::LineEntry` is not built: an Edge is drawn as an entry with the Edge as `entity` and its
  one world segment in `derived`, as above. A heavier line is the mode's `stroke:`; there is no
  per-entry weight.
- `group:` and the column-header toggles are unaffected: a shape belongs to its entry, an entry to its
  mode.
- **Worked example.** Spaces' four modes (`features/spaces/colour_modes.rb`: By Space, By ventilation,
  By weighting factor, By height) each carry the Volume preview prism (`features/spaces/prism.rb`, pure,
  in world metres, the same value the export writes) as their entries' `derived`, so the prisms show
  while one of those modes is on and never otherwise, with no preview switch of their own. Its two
  readouts (`features/spaces/readouts.rb`) are the readout example: Space labels anchor each Space at its
  reference point, the plan centroid of its largest Floor Segment at that segment's mean height, with
  optional lines set per Model session by a view command and a native menu, which force a readout
  rebuild because the revision does not change; selection totals sum the Spaces a selection touches, each
  once.

### Colour-by readouts

Implemented in P3a-05. A readout is a separately registered pure projection that returns viewport
text, shown with any mode and with none:

```ruby
feature.colour_readout("ph_composer.spaces.labels", label: "Space labels", selection: false) do |read|
  ColourBy::Readout.new(anchors: [ColourBy::Anchor.new(point: centre, parts: ["101 ", ["area", 12.4]])],
                        hud: [])
end
```

- **Input.** The read request a mode's projection receives. A readout declared `selection: true` also
  gets `read.selection`, the selected occurrences as full persistent-id paths, and is rebuilt when the
  selection changes (the `selection_changed` host event); other readouts and every mode are not. Like
  a mode's projection, a readout only reads: it never writes, connects to the public API, changes the
  selection or touches the panel.
- **Output.** `anchors`, each a world point (inches) and one line of parts, drawn with
  `view.draw_text` at the point's screen position, not depth-tested; an anchor behind the camera is
  skipped. An anchor may carry `path`, under the same visibility and mask rules as derived shapes;
  without it, it is drawn whenever the readout is on. `hud` is lines of parts drawn under the legend,
  or at the legend's place when no mode is on. A part is plain text or `[quantity, si_value]`; the
  overlay formats quantities with `PhComposer::Units.format` in the session's display units
  (`context/TECH_STACK.md`, "Display units"), so a readout never formats a unit-bearing number.
- **State.** Readouts are on or off per Model session, independently of the active mode, and are not
  remembered across sessions as the last mode is. The overlay is attached while a mode or any readout
  is on. `ph_composer.colour_by.state` lists the registered
  readouts and which are on; the view command `ph_composer.colour_by.readout` turns one on or off; the
  native Colour by menu lists them under the modes. A readout that raises is turned off with a notice,
  as a mode is.
- **Registration.** `colour_readout` takes the same diagnostics as `colour_mode`: a duplicate name or
  an owner that is not installed refuses the install.

**The example and the contributor tasks.** `tools/examples/colour_by/example_colour_by.rb` is the
example to copy: an outside feature with a prism mode and a selection-reading readout, tested by
`tests/example_colour_by_test.rb`, with no line under `colour_by/` naming it. "Add the By height mode
with its prism" (Spaces, P3a-09) changes only
`features/spaces/`: a `colour_mode` whose projection makes one entry per Volume, with the Volume's
path, no entity and a prism (the floor loop, a roof at the Volume's height and its sides) in
`derived`. "Add operation marks to By type" (Windows, P3a-05 slice B) changes only
`features/windows/colour_modes.rb`: each Unit entry keeps its entity and gains segments for its
elements' operations, from the pane plan the Unit's definition is built from, placed by the Unit's
transform. A thermal-bridge mode (Phase 3b) carries each Edge as `entity` and its segment in
`derived`. None of the three adds a line under `colour_by/`.

### Zone views

Implemented in P3a-06. The Zones tab is one table of Zones read through views (D3a-16). A view is a
panel contribution registered with the kit part `table_views` under a host id, as
`table_contributions` keys tables by name. `table_views.js` is a kit module and names no feature. A
screen declares itself a host (`table_views.host(id)`); Zones' screen (`features/zones/overview.js`)
is the host for `"ph_composer.zones"`, may name Zones, and reads the views registered there without
naming any. Faces (`features/zones/faces_view.js`) registers through the same contract as any other.

```js
PhComposerUI.get("table_views").register("ph_composer.zones", {
  id: "example.zones.areas", label: "Areas", order: 90,
  sections: ["ph_composer.zones.overview"],     // listed only while the snapshot publishes these
  zoneFields: [],                                // the Zone cells it shows; all three when omitted
  columns: function (vs, profile) { return [["gross_m2", "Gross area"]]; }, // after the Zone cells
  value: function (vs, row, field, profile) {}   // a cell's text, for Zone rows and the view's own rows
});
```

Every hook receives the view's own state first: what `create(host)` returned, or `{}` without one.
`host` is the view's only reach into the screen: `session`, `send`, `snapshot`, `revision`, `edits`
and `look` (the screen's request channels), `gated` (the read-only Zone occurrences by path),
`draftReason()`, `refuse(reason)`, `disposed`, `activeView()` (the id shown now) and `show(id)` (shows
a view through the tab's and the view row's guards, and answers whether it did). A hook a view leaves out takes the host's default,
so `tools/examples/zones/example_zone_view.js`, two columns and `value`, is a complete view.

| Hooks | What the host asks |
| --- | --- |
| `attach({ surface, mount, toolbar, hiddenColumns })`, `prepare(rows, state)`, `painted()` | Once, the view's own surface, table mount and tools slot in the controls row (Spaces binds its range-edit grid there; `help` puts a help button first); each paint, its rows before the table paints (to refresh cell drafts), and a call after every paint, a row opened from its chevron included |
| `create`, `dispose`, `consume(state, send)` | The view's state for one Model, and what it reads from each snapshot before rows are built. Every listed view consumes, shown or not, so work that arrives for a hidden view (a native handoff, a tool that turned on late) still reaches it |
| `zoneRecord(record)`, `children(row)`, `initiallyOpen(row)`, `extraRows()`, `tiers` | What a Zone row carries for the view, the rows beneath it (none by default), whether a row the view adds opens by default (`null`: the host's rule), top-level group rows after the Zones (records outside every Zone; `record.zone` is null; they follow the Zones in any sort, count as no Zone, and show while the text filter and the view's filters pass them), and how many tree levels open (2 by default; Spaces, four deep, gives 3) |
| `columns`, `leadingColumns`, `value`, `cell(td, row, field)`, `decorate`, `zoneMarker(row)` (asked of every row, the host's Zone states first), `widths`, `hiddenColumns`, `optionalColumns` | The view's columns (`leadingColumns` sit before Name), their text or in-place control, a cell's flag, the Zone row's marker after the host's own, default widths, the columns hidden at first, and the `[field, label]` pairs Table options shows or hides |
| `tableOptions(toggle)` | The view's own Table options choices after its columns, each through `toggle(text, pressed, run)` (Spaces adds its readouts and, while Space labels are on, their lines; `sections/colour_by.js` `readouts(state)` and `showReadout(state, name, on)` reach any feature's readouts without naming one) |
| `colourBy`, `sorted`, `filteredFields`, `filterValues`, `filterLabel`, `headerAction`, `menuValueAction`, `menuExtra` | The view's columns' Colour-by bindings, sort and value filters, and anything its column header and menu add (Faces adds the Classify paint, Spaces the Mark floor paint); the host closes the menu once a value action has run |
| `zoneMatch`, `rowMatch`, `search`, `queryMatch(row, query, zone)`, `sortValue(record, field)`, `sort(list, field, direction)`, `viewportPaths` | How the view's filters and sort reach Zone rows (`sortValue` gives a Zone row's value in the view's sorted columns), its own rows and the viewport mask (by default each Zone that passes `zoneMatch`, whole). When the text filter matches a Zone only through the view's `search` text, `queryMatch` says which of the view's rows still show (by default all) |
| `actions(row)`, `zoneActions(row)`, `action(row, item, control)`, `inspect`, `locate(row)`, `clearLocate`, `selected(row)` | Row actions (`control` is the pressed button, to anchor what it opens), the Zone row's actions after Make independent, Locate (`clearLocate` answers whether it cleared anything), and which rows paint as selected (Spaces: the row open in the edit context) |
| `checkedZones()`, `checkZones(keys)` | The Zone rows every row beneath which this view has checked, and checking everything beneath Zones another view handed over |
| `check(context)`, `selectionBar(overview)`, `settings`, `navigate(intent)`, `count`, `placeholder` | Checkboxes for the rows it checks, a selection bar, a settings control for the page header, a navigation intent's `check`, what the control row's count adds after the Zones ("4 Spaces"), and the text filter's placeholder |
| `draftReason`, `cancelDrafts`, `canCancelDrafts`, `leaveReason`, `leave`, `escape` | Work a filter, a switch or shutting a row must not hide, and how the guard's notice cancels it (offered only while `canCancelDrafts` answers, never for an edit already sent); what holds a switch; what stops on a switch away; Escape, true when the view used it |

- **Listing.** A view is listed while the snapshot publishes every section it names, so a build
  without a feature shows none of its views, with no line in the composition root. With one view
  listed the view row is hidden; with none the host shows the Zone rows alone.
- **The host keeps** the Zone rows and their Name column, the Zone row's in-place cells
  (`zone_cells.js`: Building-Segment, Level, Ground depth), Make independent, the text filter, the
  Zone filters (Building-Segment, Level), which rows are expanded (Expand all and Collapse all reach
  every row with rows beneath it), and the panel hooks (`navigationGuard`, `outcomeText`, `workedOn`).
- **A view owns** its rows, its columns, their header Colour-by toggles and value filters, its sort,
  its checked rows, its selection bar, its settings and its tools. Checked Zones are shared: on a
  switch the host asks the old view which Zone rows are fully checked (`checkedZones`) and, when there
  are any, hands those Zones to the new view (`checkZones`), which checks everything beneath them in
  place of what it had checked. A view otherwise keeps its own checks through a switch away and back. Each view has its own surface and
  table mount, so its column widths, hidden columns and column menus are its own. The host keeps one
  controls row and moves the view's column filters and sort out of it and back on a switch; a Zone
  filter stays while the next view shows its column and otherwise leaves with the view that does, so
  no filter applies without a column to clear it from; hiding a column through Table options drops its
  filter for the same reason, and showing a Zone column again drops the older copy a view kept. Table
  options changes nothing while a Zone edit is held. A column has a menu when it sorts (`sorted`) or
  filters (`filteredFields`), and offers only those. All of it survives a switch away and back.
- **Switching** is a host action that sends nothing to the Model and never changes the SketchUp
  selection. It is refused while `draftReason` or `leaveReason` answers; otherwise it calls the old
  view's `leave` (Faces stops its paint tool and hides its bar), restores
  the new view's filters and sort, repaints the page header's settings slot from the new view, and
  remembers the choice on this computer (the `table_view` display preference, keyed by host id), as
  the last Colour-by mode is remembered. A view state is never written to the Model, which would
  dirty it and add an Undo entry. A session opens on the remembered view while it is listed, else the
  first. A shown view that stops being listed leaves the same way, unless `draftReason` or
  `leaveReason` answers: it stays listed until that work is done. Table options offers Colour by for
  every mode no column of the shown view displays.
- **Gestures.** The host owns the gestures that clear Locate (a pointer press elsewhere, Escape). A
  Locate outline outlasts a switch, so they reach every view's `clearLocate`. Escape unwinds one layer
  at a time: an open bubble or column menu, then the shown view's `escape` (Faces: the Classify
  palette, then the checked set, then its Locate outline), then an outline another view left. A
  press on the view row does not clear it. A navigation intent names its view
  (`panel.navigate("overview", { view, check, locate })`); the host switches to it, guards included,
  sets `intent.viewShown`, and applies `check` only when the view is shown.
- **The view row** is the shared subtabs nav (`subtabs.js`, `aria-label` "Zone views") above the
  "Zones" heading, as Window Types places its row, with one surface per view.
- **Registration** refuses a view without an id or label and a duplicate id under one host when it
  registers. A view registered before its host declares itself is held and listed once it does; the
  panel reports one whose host never declares when it is ready.

**Contributor tasks traced.** "Add the Spaces view" (P3a-07) adds one module under
`html/features/spaces/` registering under `"ph_composer.zones"`: Space, Volume and Floor Segment rows
three deep through `children`, sums on the Zone row through `value`; no Zones file changes. "Add an
Occupancy view" registers `columns` and `value` with no `children`, as the example does.

### Native menu items

Implemented in P1-D. Some things a user asks for change no record and open no operation: starting a
viewport tool, choosing its palette, turning a Colour-by mode on. They are not actions, because an
action is a validated Model change, and registering them as one would manufacture an Undo entry for
something that changed nothing. A feature declares them as menu items instead:

```ruby
feature.menu_item("ph_composer.zones.faces.classify_face_type_wall",
                  label: "Wall", menu: "Classify faces",
                  state: ->(session) { ... MF_CHECKED or MF_UNCHECKED }) do |session|
  Zones::Faces.classify_tool(session).choose("face_type", "Wall")
end
```

`menu` is the submenu's label and is open prose; items are grouped under it in registration order,
and `separator_after` closes a group. The handler receives the current `ModelSession`. `state` is
optional and is what makes an item show whether its choice is the current one.

`shell/` builds the Extensions submenu and the viewport context menu from whatever is registered,
so an outside feature reaches both without a line added to it. Nothing in `shell/` or `session/`
names a menu item, a mode or a feature, and no feature's words appear there: a label comes from the
declaring feature, which is also where `context/UBIQUITOUS_LANGUAGE.md`'s glossary words live.

A menu item is the native-menu route to those things. The same state has to be reachable from the
panel and from a client, and that is a view command.

Native menu handlers also serve as entry points to registered Model actions. They obtain explicit
references and the read revision, then invoke the same public action used by the panel and agents;
they never write Model records directly. A selected-Face choice applies one attribute immediately.
Without selected Faces, the same choice loads the paint tool through its view command.

`available: ->(read) { ... }` controls context-menu visibility. An optional
`feature.menu_entries(name, menu: ..., available: ...) { |read| [Declarations::MenuEntry.new(label: ..., handler: ...)] }`
supplies current record-dependent items, such as Attached zones. Both receive the same read request
as a Colour-by projection, under the declaring feature's owner, with `read.session` for
session-owned state. Menu handlers and `state:` tests still receive the session; a handler that
reads or invokes is a client and keeps one long-lived context per session, as the Zones selection
client and the Windows menu do. A test or provider that raises is logged and its item left out;
the rest of the context menu is still built. Providers run only while building a context menu;
the Extensions menu is installed once. The shell validates the supplied entry shapes and remains
independent of contributor vocabulary and record kinds.

### View commands

Implemented in P1-D. A view command changes what the host shows and nothing else: the selection, the
camera, the active Colour-by mode, a running tool's palette. It is the write channel for viewport
state, and it is a third verb beside `query` and `action` because neither one fits. A query cannot
do it: `context/AGENT_INTERFACE.md` says a read never changes the camera or the selection. An action
cannot do it either: an action's contract is a named native operation the user can undo, and there is
nothing here to undo.

```ruby
feature.view_command("ph_composer.zones.faces.locate",
                     description: "Bring an explicit set of Faces into view and outline them, " \
                                  "leaving the selection alone.",
                     params: LOCATE_PARAMS, result: LOCATE_RESULT, refuses: []) do |request|
  Zones::Faces.locate(request)
end
```

The handler takes the same `request` a query's does and returns a JSON value against its declared
result schema. What it must not do is write a record, open a `ModelOperation` or advance the session
revision; a handler that needs to wants `action`.

A view command that fails part-way leaves viewport state unspecified. Its outcome reports `effect`
`none`, which is a statement about the Model: the SKP is untouched, because nothing here opens an
operation. A client that needs to know what the viewport now shows re-reads it rather than assuming.

Every client reaches one the same way: `API.view(context:, name:, params:)` with no sequence number
and no expected revision, because there is nothing to retry and nothing for a stale revision to
protect. It refuses while the session is busy, as a read does, so it cannot move the camera out from
under an operation that is still running. Access is the `view` capability, separate from `read`
because a read never moves either, and separate from `model_write` because nothing it does reaches
the SKP. The panel sends `view.invoke` and settles the answer in its own result slot.

### Setup commands

A setup command changes session or machine state and never the Model or the viewport: reading a
configured library into session memory (`ph_composer.library.load`), adding a library file or folder
on this machine (`.providers.add_file`, `.providers.add_folder`), removing one
(`.providers.remove`) and clearing a stored setup that can no longer be read (`.providers.reset`).
It is a fourth verb because none of the other three fits: a read never
changes state, an action is an undoable Model operation, and a view command changes only what the
host shows.

```ruby
feature.setup_command("ph_composer.library.providers.remove",
                      description: "Remove a configured library from this machine.",
                      params: REMOVE_PARAMS, result: PROVIDERS,
                      refuses: %w[library.setup_unavailable library.setup_unreadable]) do |request|
  Library::Setup.remove(request.params.fetch("provider_id"))
end
```

The handler takes the same `request` a query's does. It must not write a record, open a
`ModelOperation` or advance the revision. Every client calls `API.setup(context:, name:, params:)`
with no sequence and no expected revision; it refuses while the session is busy. Access is the
`setup` capability, which `API.connect` never grants by default: changing what is configured on the
user's machine is granted explicitly, as `export` is. The panel sends `setup.invoke` and settles
the answer in its own result slot. A setup command takes the same optional `approval:` and
`precondition:` a file export does (see "Registered file exports").

### Viewport tools

Classify, Window Place, Spaces' Mark floor (`features/spaces/mark_tool.rb`, started by the
`ph_composer.spaces.mark_tool.start` view command with a weighting factor) and the thermal-bridge edge tool
(`features/thermal_bridges/edge_tool.rb`, armed by `ph_composer.thermal_bridges.edge_tool.choose` with a type
and quantity; it picks with `Pick.edge_path` and asks `zones.containment` per hovered path) use this
contract. A feature that authors by pointing writes a `Sketchup::Tool` and starts it from a menu item or a
registered view command. The rules below come from Classify's host gate
([evidence](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-classify-tool.md)).

- **Pick, never walk.** `Pick.face_path(view, x, y)` answers what is under the pointer as a
  root-to-leaf instance path. `Pick.face_point` adds the world-space camera-ray intersection
  with that same Face from one pick. A feature turns the path into an occurrence without touching the
  Model. A pointer move happens tens of times a second; a Model walk per move costs what P1-D
  measured a walk to cost. `core/pick.rb` and `core/drag_set.rb` name no feature.
- **The tool owns the gesture, not the change.** It calls a registered action through `API.invoke`
  with its own caller handle and sequence numbers, exactly as any other client does. It opens no
  `ModelOperation` itself, so an abandoned gesture writes nothing and leaves no Undo entry, and one
  completed gesture is one Undo step however many entities the pointer crossed.
- **Freeze intent and revision at button-down.** Both belong to the gesture, not to the tool. A
  palette changed mid-drag must not change what the drag in progress writes, and a gesture applied
  against the revision it began at refuses as `revision.stale` rather than writing through a change
  someone else committed underneath it.
- **Bound the collection one past the limit** so the operation that owns the limit refuses, rather
  than the tool silently applying the first N of what the pointer crossed. The Classify limit is
  `GESTURE_FACE_LIMIT`, owned by the Face schema, and Mark floor's `FLOOR_GESTURE_LIMIT`, owned by the
  Floor Segment schema; see [TECH_STACK.md](TECH_STACK.md#envelope-what-ph-composer-owns-that-the-predecessor-did-not).
- **Talk to the status bar, not only the session.** The panel is the only subscriber to a session
  notice, and a viewport tool is used with the panel closed, so a refusal delivered only that way
  is silent exactly where it matters. Results and refusals reach both `Sketchup.status_text=`
  and the session notice. Routine activation guidance uses the status bar alone so it does not
  cover the panel controls; see [D7 F8](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-overview.md).
- **Cancel on every route, and leave nothing behind.** Escape, deactivation, a suspended context
  and a callback that raised all abandon the pending gesture. Track whether the button is actually
  down: a press whose release the host never delivered must not leave later hovers collecting. The
  tool is session feature state, so `detach` must take it, and anything it forced on, with a
  closing Model.
- **Give the Colour-by mode back.** A tool that turns a mode on holds it through a
  `ColourBy::Lease` (`colour_by/lease.rb`): `take` turns it on without remembering it, and `release` on
  deactivation puts back the mode from before the first take, or none, unless the user picked another
  meanwhile.
- **Do not reach for gestures the host reserves.** A custom tool receives no
  double-click-to-enter-group; that belongs to the Select tool, as it does for every native drawing
  tool. Reach geometry inside a container through the picked path instead.

## Metadata and structured extension data

Every authored domain entity supports a JSON-compatible `user_data` mapping, including definitions
and assignment records where applicable. Contributors use namespaced keys, for example:

```json
{"user_data": {"example_org": {"review_status": "needs_site_check"}}}
```

Ordinary edits and supported persistence round trips preserve this metadata. Public operations
read and update it without requiring raw dictionary access; updates participate in Undo. Catalog
records take it through their kind's update action (`engine.propose_update`); Zones, Faces and
Window Units, whose records live on entities, take it through their owner's `update_metadata`
action, which applies the same rules ([CONTRACTS.md](CONTRACTS.md), "Records and extension data"). Core
calculations do not silently interpret arbitrary metadata. Absence in an older record is valid.

Export inclusion is deliberate. A record's `user_data` passes through to the HBJSON object Honeybee
gives it, uninterpreted, where the owner opts in (`reader.entity_record(..., user_data: true)` or
`reader.records(kind, user_data: true)`): Zone to Room, Face to Face, Window Unit to each of its
Apertures, Assembly to Construction (Ed, 2026-10-13). The translation writes it beside PH-Composer's
own reserved `ph_composer` key; a user key named `ph_composer`, or after any namespace an export
contributor declares in `user_data_keys:`, blocks the export; every string and
key still passes the local-path check, and the report counts the HBJSON objects that carry it. Elsewhere `user_data`
is left out with a finding. An export contributor whose translation writes its own HBJSON
`user_data` declares those keys at registration (`user_data_keys:`); under a declared namespace the
artifact guard refuses any key no contributor declared. Do not promise lossless round trips through
formats that cannot preserve it.

A feature whose extension lives on another feature's entities (a review on Zones' Faces) exports it
by claiming it, never by the entity owner naming it: its export contributor declares
`entity_projections:` and reads the declared fields with `reader.entity_projection`; its Python
section attaches to the HBJSON object (`Attachment(FACE, ...)`) and writes under the `user_data` keys
it declares ([CONTRACTS.md](CONTRACTS.md), "Records and extension data"). The development example
(`tools/examples/foundation/`, step 7 of its README) is the walkthrough.

Maintained extensions can register structured extension data with a namespace, schema version,
validator and migrations. Preserve payloads belonging to unavailable extensions during ordinary
edits and save/reopen. Preserved data is not necessarily understood or validated: even at the
installed version, an envelope is understood only when its payload passes the installed validator
and it declares the installed references. Otherwise it is invalid, kept as stored for unrelated
edits and refused for copy, migration and export until valid data replaces it. Report the
missing capability explicitly when it affects export correctness. An unsupported schema must
not be silently rewritten or dropped.

Ed confirmed the following copy policy on 2026-09-18:

- Duplicating a distinct authored object creates a new identity and an independent copy of its
  `user_data`. References to shared definitions continue to name those definitions.
- When an operation duplicates a collection, declared references between objects included in the
  copy point to their new counterparts. References to definitions outside the copy remain shared.
- Arbitrary metadata values remain unchanged. Never infer that a string in `user_data` is an
  object reference.
- Structured extension data declares its references and copy rules. If an unavailable extension
  prevents safe duplication, report the limitation instead of silently changing or dropping data.
- Another placement of a shared component follows the owning feature's identity rules. It is not
  automatically a new authored definition.

Ed also confirmed the unavailable-extension and unsupported-schema policy on 2026-09-18:

- Preserve the unrecognized payload unchanged through save/reopen. Allow unrelated edits only
  when they can safely leave it untouched.
- Refuse operations that require interpreting or rewriting that payload, with a clear explanation
  of the missing capability. A copy requiring unavailable reference rules is refused without a
  partial copy.
- A failed migration preserves the original data and rolls back the affected operation.
- Block export when unknown data affects export correctness, following the existing export rules.
  Merely preserving data does not establish that it can be exported correctly.

The reference declaration API (`Records::Reference`, `Records::ReferenceTarget`,
`Records::Descriptor`, `Records::ReferencePlan`, below) and the explicit export mapping for
`user_data` (`user_data_keys:` on an export contributor) are implemented. A new storage use still
states how its operations depend on extension data so the confirmed refusal policy is enforced,
as the copied-Zone and split repairs do by refusing unsafe payloads before any write. Test the relevant round trips
and actual references. Arbitrary metadata is not a substitute for a typed core domain field.

### Entity-owned reference targets

A feature registers read-only entity identities through `feature.reference_target` rather than
exposing its entity store as catalog CRUD. The declaration is a `Records::ReferenceTarget` with
an `id`, `label`, `records:` provider and pure `validate:` callback. The provider returns detached
`Records::ReferenceEntry` values with `kind`, an occurrence `key`, and the stored `record`.
The key identifies the storage occurrence, not the UUID. Repeated placements and orphan records
must be included when they could make a UUID ambiguous. The callback returns validation findings.

A reference target also describes its kind: `schema_version:`, `values:` (the values JSON Schema),
`occurrence:` (the schema of the reference naming one occurrence) and `references:` (its outgoing
core references, as `Records::Reference` fields). These form a `Records::Descriptor`, the same
shape a catalog `RecordKind` publishes, so discovery, validation and the reference scan read one
description whoever stores the kind. The engine's incoming-reference scan reads core references
from every kind's descriptor: an entity record naming a catalog record blocks that record's
deletion exactly as a catalog record does. A proposal that rewrites those entity records before
the delete passes them to `propose_delete` as a `reference_plan`. Describing a kind grants the
engine no authority to create or delete what stores it.

An extension's `target_kind` may name a catalog kind or a registered reference target. The
built-in targets are `ph_composer.zones.zone` and `ph_composer.zones.faces.face`; a Face's
`attached_zone_id` is a declared core reference to `ph_composer.zones.faces.attached_zone`.
`Records::Engine#resolve_reference(kind, id)` returns exactly one validated, detached entry;
missing or ambiguous identities refuse without repairing storage. The owning feature continues
to control all writes through its normal public actions.

A target may also declare `locate:`, the owner's resolver from an occurrence reference to the live
entity: `->(model, reference, mutable:, index:) { Records::LocatedEntity }`, raising the owner's
`target.*` refusals. A feature that requires the owner reaches it through
`request.locate(kind, reference)`, or keeps `request.locator(kind)` for a step to call at apply.
A target may also declare `locate_index:`, `->(model) { index }`, the owner's read-phase index. A
caller that locates many references while planning, before anything is written, builds it once
with `request.locate_index(kind)` and passes it as `index:` to each `locate`, so the owner walks
the Model once for the batch rather than once per reference. The index is opaque to the caller
and valid only until the next write: a step never keeps it for apply, where it locates on the
live Model. `index:` is nil when the caller has none or the owner declares no index. The owner stays the one authority on
what a valid target is, so a rule it adds reaches every caller. The permitted use is to read the
entity's geometry and glue to it. Writes to its records stay with the owner, through its actions.
Ruby cannot enforce that limit; it is a rule of this contract and is checked in review. The Face
target `ph_composer.zones.faces.face` and the Zone target `ph_composer.zones.zone` are locatable (a
located Zone's `transform` is its parent-to-world transform, so its contents map through
`transform * entity.transformation`); Window placement locates its host Face this way
(`features/windows/placement/host.rb`). Zones' frame-and-outline view command,
`ph_composer.zones.faces.locate`, is a different thing with the same verb; its sibling
`ph_composer.zones.faces.select` replaces the selection.

Identity-changing proposals use a typed `Records::ReferencePlan` of the exact occurrences they
will replace. This establishes the final identity set, including the untouched original or
retaining split piece, before copied payloads are accepted. A remap applies only to the declared
target kind and objects included in that copy. A list of newly allocated UUID strings alone is
not evidence that their reference targets exist.

Incoming references outside a copied collection remain unchanged. After explicit split repair
they name the piece retaining the old UUID. If a solver cut retains no original native Face,
removing its authored identity must not leave incoming references dangling: the operation refuses
and rolls back instead of choosing a replacement by geometry. Incoming checks cover catalog and
entity-owned records, including declared references in readable unavailable envelopes. An
unreadable envelope cannot establish safe identity removal and causes conservative refusal.
When this is learned during a native cut, the failed result retains the rollback-certainty code
and effect and includes the declared domain reason in its message and `detail.cause`.
Unexpected exceptions retain the generic message; their internal details are not exposed.

## Scripting as an entry point

[AGENT_INTERFACE.md](AGENT_INTERFACE.md) extends this interface to users' external agents,
including discovery, focused reads, visual context and reliable writes across host lifecycle changes.

Provide a small public interface for finding and reading entities, inspecting fields and
references, running validated operations, updating metadata, and requesting validation or export.
Reads return safe views or values. Writes use named operations with the same validation,
reference checks and transactions as the UI. Reading must not mutate or repair the model.

A script can become a reusable operation, then acquire a button or editor, then become a
maintained feature. Each stage uses the same business operation. A contributor should not need
to learn the UI framework to automate a model task.

## Evidence that the architecture is extensible

Prove implemented contracts with small synthetic examples and reusable contract tests:

- Update metadata through a console script.
- Register a record kind and a simple editor.
- Register an importer that proposes changes and applies them through model operations.
- Register an exporter that consumes only HBJSON.
- Register a provider from a separate extension. The [provider example](../docs/LIBRARY_PROVIDER_EXAMPLE.md)
  proves the shared contract and public copy/read-back without editing core composition.
- Register a Colour-by mode through the shared overlay interface. Phase 1's Face and Zone modes
  register through the public `colour_mode` call
  ([walkthrough](../tools/examples/authoring/colour_by_walkthrough.rb)).

Each example has a short walkthrough identifying the entrypoint, relevant contract and required
files. A newcomer should be able to trace one request through validation, mutation and its result.
Check that these examples require no private hooks or special cases for their feature names.
Persistence examples exercise metadata preservation, references, Undo/Redo and save/reopen;
unavailable-extension examples distinguish retained data from validated behavior.

Land each example with its owning capability. The foundation packet starts with a synthetic
feature and record; this list does not authorize implementing later features during transplant.
The first two merged through PR #1: the example feature's walkthrough (P0-D) and its
synthetic editor (P0-E, `tools/examples/foundation/editor.js`), a panel section registered with
`panel.section` that edits through `request.js` and the unit field. Adding the editor changed no
file in `shell/`, `session/`, `core/` or `html/`; its development entry hands the script to the
panel. P0-F added the example's export contributors (`export_contributor` in its `install`) and
their Python sections (`tools/examples/foundation/example_translation.py`), checked end to end
against one shared extraction and result fixture, and a test-only exporter that receives only the
HBJSON text and a copy of its options (`tests/python/test_exporters.py`). Neither changed a file in
`export/` or the translation package.
Do not claim an extension point is ready until its example and required host gate pass.

## API decisions settled and open

Phase 1 settled the scripting methods and mutation contract (`PhComposer::API`: discover, describe,
connect, query, view, preview, invoke, outcome and the export task methods), registration schemas
and their validation at load, and the reference declaration and extension-data refusal policy for
entity records. The compatibility policy across API major versions and the extension-data lifecycle
for later record kinds remain for their owning plans. These are details within the accepted
direction, not a reason to reopen the community goal or to invent all interfaces in advance.

## Development review

Use the repository-local
[architecture review skill](../.agents/skills/ph-composer-architecture-review/SKILL.md)
when designing an affected boundary and as the rubric for the existing coherent-diff review.
Review findings cite the rule, source evidence and contributor consequence. Readability concerns
need a concrete explanation; metric scores do not replace judgment.
