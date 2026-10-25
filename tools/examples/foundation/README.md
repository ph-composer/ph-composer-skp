# Example feature: `example.foundation`

A complete feature built only from PH-Composer's public contracts, for contributors to read and copy.
It is development only: the shipping composition root does not list it and the RBZ builder refuses
any `examples` path.

## Files

| File | What it shows |
| --- | --- |
| `example_foundation.rb` | The feature: two record kinds, two structured extensions (one stored on Zones' Faces), one query, four actions, one proposal participant, one snapshot section and three export contributors, all declared in `install(registry)` |
| `example_kit.rb` | A second feature that requires the first and composes its participant into one action |
| `example_translation.py` | The feature's translation sections: definitions, and parts that require definitions by durable id |
| `example_doors.py` | An attaching translation section: Doors that join the Faces another feature translates, with no edit to that feature (`tests/python/test_example_doors.py`) |
| `load.rb` | The development composition entry: registers both features and hands the editor to the panel |
| `walkthrough.rb` | Two clients driving the feature through `PhComposer::API` with the panel closed |
| `editor.js` | The synthetic editor: a panel section for the parts, built from the shared unit field, record form and request channel |

The offline tests are `tests/example_foundation_test.rb`, `tests/example_editor_test.js`,
`tests/export_test.rb` and `tests/python/test_example_translation.py`; the browser preview
(`tools/ui-preview/`) loads the editor too. `tests/fixtures/foundation/{extraction,result}.json`
is one extraction the export contributors produce and the result the sections translate it to.

## What a contributor writes

1. **Record kinds.** `Records::RecordKind` with fields declared as JSON Schema. SI numbers name
   their unit in the key and in `x-unit` (`length_mm`, `"x-unit": "mm"`). A `Records::Reference`
   names another kind; the engine checks the target exists and remaps it when a duplicated
   collection contains it.
2. **Extensions.** `Records::Extension` for versioned structured data on records: its reference
   paths, export relevance, copy rule, validator and migrations.
3. **Operations.** `feature.query(...) { |request| value }` reads. `feature.action(...) { |request,
   changes| value }` proposes record writes through `request.engine` into `changes` and returns a
   value. It never writes, opens an operation or shows a dialog: the dispatcher validates the
   proposal, opens one native Undo step and applies it, or writes nothing. Each names `refuses:`,
   the codes it can refuse with beyond its kind's common set; the engine's codes count, since they
   reach the caller unchanged.
4. **Registration.** `install(registry)` declares everything under the feature's own namespace.
   The registry validates the declarations together and publishes nothing if any is wrong.
5. **A panel section.** `PhComposerUI.get("panel").section(name, render)` mounts a section in a
   pane. `render(root, state, send)` reads the feature's snapshot section through `snapshot.js` and
   sends edits through a `request.js` channel; the panel supplies the session and the revision it
   showed, and shows a refusal as a warning. Unit-bearing values go through `unit_field.js`, which
   keeps SI in storage and follows the display preference. A shipping feature declares its section
   as a module in `html/`; this development editor is a plain script the panel runs after the kit
   starts.
6. **Export.** `feature.export_contributor(name, section_version:, result:, report:) { |reader|
   records }` adds a section to the export extraction. The block reads through `reader.records(kind,
   extensions: { namespace => fields })`, which exports declared values and the named extension
   fields only, leaves `user_data` out with a finding unless the call passes `user_data: true`, and
   blocks on data it cannot safely leave out. `result` declares the result fields the translation adds, which the privacy check then
   admits; `report` renders them. The matching Python `Section` (`example_translation.py`) reads
   the section one record at a time and declares the other sections it requires with a typed
   `Requirement`; a build lists it in `python/ph_composer_translation/composition.py`.
7. **Data on another feature's entities.** The example stores a review on Zones' Faces
   (`example.foundation.face_review`). Zones exports Faces and names no review: the
   `example.foundation.export.face_reviews` contributor claims the payload with
   `entity_projections: [{ "namespace", "target_kind", "source_section", "fields" }]` and reads the
   declared fields with `reader.entity_projection(namespace, target_kind)`, one
   `{"id", "path", "payload"}` row per Face. Its Python section attaches to each Face
   (`Attachment(FACE, ...)`) and writes `user_data["example"]["foundation"]["face_review"]`, the key
   the contributor declares in `user_data_keys:`. An unclaimed required payload still blocks export.

## Keyboard and lifecycle in the editor

The New part dialog shows who owns what in a form built from the kit.

- **Field commit versus form submit.** The length `UnitField` owns its draft: it parses, keeps an
  invalid entry with its message, and on Enter commits and swallows the key. The form owns submit.
  So the form takes Enter while the event travels down to the length input, with a capture listener
  on the form, and calls the one `submit` the Create button and Enter in the label also reach.
  `submit` parses the length and checks the label; an invalid draft sends nothing and stays on
  screen until it is corrected or cancelled. The Assembly builder's dimension fields are the
  shipping precedent.
- **Pending.** `RecordForm.run` allows one request in flight, so a repeated Enter or Create sends
  nothing more; the result settles once and a completed create closes the dialog. The kit leaves
  Create's availability to the form, so the form makes Create available again when a refused or
  failed create settles, keeping its message until the user corrects the draft or cancels.
- **Withdraw versus dispose.** `withdraw` forgets the pending request and closes the dialog; the
  form stays usable. `dispose` is permanent and runs when the panel shows another Model: the form
  withdraws, removes its Enter route and disposes the length field it built, which ends that
  field's unit-preference subscription. Afterwards its `submit`, `run` and `show` do nothing, and
  the header button opens only the form it was painted with. A form disposes the children it built.

## Composing another feature's step

`example.foundation.add_part` is a proposal participant: a step another feature composes into its
own action's proposal. `example.kit.add_pair` requires the example feature, lists the participant in
`participants:` and calls `request.participate("example.foundation.add_part", params)` twice, so both
parts are one Undo step. The foundation checks the dependency, the edge, the active proposal and the
params, runs the participant under its own owner with an engine that writes only the example's
kinds, and refuses the whole proposal if anything fails. `ExampleWalkthrough.composition` previews
(nothing written), invokes and reads back; the offline test also undoes it once. The rules are in
`context/CONTRACTS.md`, "Compound proposals".

## Registration as an outside contributor

`ExampleWalkthrough.registration` installs a second small feature, `example.notes`, with its own
duck-typed store (`NoteStore`, not `DictionaryStore`) and a nested reference, through the same
`Registry.install`. It then edits the field schema and reference it kept and shows discovery still
reports the admitted values, and installs a third contribution whose store dictionary is outside
`ph_composer.`: that batch is refused with `registration.schema_invalid`, registers no dictionary,
and the example's own summary query still answers (`tests/example_foundation_test.rb`).

## Try it in a host

With PH-Composer installed and the development bridge running:

```sh
uv run tools/hostkit/host_bridge.py eval \
  'load "/absolute/path/to/ph-composer/ph-composer-skp/tools/examples/foundation/load.rb"; ExampleWalkthrough.run'
```

The result lists each step, what happened and whether it matches the contract. The steps: create
two parts, read, update with expected values and metadata, read back, a second client refused on a
stale revision, a retry that returns the first outcome, a duplicate that remaps an internal
reference and keeps the shared definition, and a summary query.
