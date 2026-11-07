# API quickstart

DATE: 2026-10-01
STATUS: Implemented and merged to main for in-process Ruby clients. No external connection is
supported yet; see [AGENT_ACCESS.md](AGENT_ACCESS.md).

This walks one session from discovery to a verified edit using only the public interface. Every
operation name, params schema and result schema it uses is in the generated
[API_REFERENCE.md](API_REFERENCE.md), and `PhComposer::API.describe(name:)` answers the same at
run time. A client needs nothing else: no feature module, store or dictionary name.

The offline suite runs these steps as written (`tests/api_client_test.rb`).

## 1. Find the Model and connect

```ruby
found = PhComposer::API.discover
session = found["sessions"].find { |row| row["active"] }
context = PhComposer::API.connect(session_id: session["id"], capabilities: %w[read view model_write export])
```

Ask only for the grants you need; `export` is required for step 8 alone. `setup`, for loading
and configuring libraries on this machine, is never granted unless asked for.

`discover` lists the registered queries, actions, view commands, setup commands, file exports and
record kinds by name.
`describe` returns one of them in full:

```ruby
PhComposer::API.describe(name: "ph_composer.zones.make")        # params, result, an example
PhComposer::API.describe(name: "ph_composer.zones.faces.face")  # values, references, occurrence
```

`ph_composer.context.read` says where the session stands before you act: its revision, whether it
is busy, the edit path the user is in, and the selection. Some writes need a Group open, as a user
would open it by double-clicking; the view commands `ph_composer.context.open` (a path of persistent
ids from the root) and `ph_composer.context.root` move the edit path for you, and each declares in
`side_effects` what leaving a context can trigger.

## 2. Make a Zone from the selection

The Zones read offers the params Make Zone takes for whatever the user has selected, or null.
Preview first; the preview's digest makes the invoke refuse if the change would now differ.

```ruby
zones = PhComposer::API.query(context: context, name: "ph_composer.zones.list")
target = zones["value"]["make_zone"]
preview = PhComposer::API.preview(context: context, name: "ph_composer.zones.make", params: target)
made = PhComposer::API.invoke(context: context, name: "ph_composer.zones.make", params: target,
                              request: { "sequence" => 1, "expected_revision" => zones["revision"],
                                         "proposal_digest" => preview["proposal_digest"] })
made["affected"]  # the Zone written, with its kind, id and change
```

`sequence` counts this caller's writes from 1. `expected_revision` is the revision of the read the
write is based on; the result's `revision` is the one to use next.

## 3. Read the Zone's Faces and classify one

A Face is named by an occurrence reference, never by its SketchUp id alone. Send the values you read
as `expected_values`, so a Face that changed in the meantime refuses rather than being overwritten.

```ruby
faces = PhComposer::API.query(context: context, name: "ph_composer.zones.faces.list")
face = faces["value"]["faces"].first
classified = PhComposer::API.invoke(
  context: context, name: "ph_composer.zones.faces.classify",
  params: { "faces" => [face["reference"]], "expected_values" => face["values"],
            "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                          "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } } },
  request: { "sequence" => 2, "expected_revision" => faces["revision"] }
)
classified["affected"].first["reference"]  # the Face occurrence, now with its record id
```

## 4. Preview and edit the Zone

```ruby
zone = PhComposer::API.query(context: context, name: "ph_composer.zones.list")["value"]["zones"].first
edit = { "reference" => zone["reference"], "expected_values" => zone["values"],
         "values" => zone["values"].merge("name" => "North Zone") }
preview = PhComposer::API.preview(context: context, name: "ph_composer.zones.update", params: edit)
updated = PhComposer::API.invoke(context: context, name: "ph_composer.zones.update", params: edit,
                                 request: { "sequence" => 3, "expected_revision" => classified["revision"],
                                            "proposal_digest" => preview["proposal_digest"] })
```

Read the Zone again and compare its `values` with what you sent; `updated["affected"]` names the
Zone. A managed Zone's Building Segment and Level values are stable option IDs. Read
`ph_composer.zones.options.all` for choices; use `options.create` to define a choice before assigning
its ID. Arbitrary category text does not create options. Older Models require explicit
`options.adoption_preview` / `options.adopt` before category edits.

## 5. Recover from a stale revision

A write based on an old read refuses with `revision.stale` and changes nothing. Read again, rebuild
the params from what you now see, and send them under the next sequence. Before you call, `describe`
lists the codes an operation refuses with as `refuses`, and `discover` lists the codes every operation
of its kind can answer as `common_refusals`.

```ruby
stale = PhComposer::API.invoke(context: context, name: "ph_composer.zones.update", params: edit,
                               request: { "sequence" => 4, "expected_revision" => zones["revision"] })
stale["code"]    # "revision.stale"
stale["effect"]  # "none"
```

## 6. Retry after a lost response

If a response never arrives, send the same request again with the same sequence. The first outcome
comes back and nothing is written twice. `PhComposer::API.outcome(context:, request: { "sequence" => n })`
answers the same without resending. A request refused as `request.malformed` never took its
sequence, so the corrected request may reuse it.

## 7. Give the Face an Assembly

Materials and Assemblies are records in the Model. Create a Material and an Assembly, put the
Material in the Assembly's one Layer-Segment, then assign the Assembly to the classified Face. Each
Builder gesture is its own action, naming its Layer and Layer-Segment by id. Sending `{}` as
`expected_values` skips the stale-value check; the Assembly's values as last read keep it.
Sequence 4 went to the refused write in step 5, because a refusal after acceptance still takes its
sequence, so this step starts at 5.

```ruby
material = PhComposer::API.invoke(
  context: context, name: "ph_composer.assemblies.materials.create",
  params: { "values" => { "name" => "Mineral wool", "conductivity_w_mk" => 0.035 } },
  request: { "sequence" => 5, "expected_revision" => updated["revision"] }
)
assembly = PhComposer::API.invoke(
  context: context, name: "ph_composer.assemblies.assemblies.create",
  params: { "values" => { "name" => "Wall A" } },
  request: { "sequence" => 6, "expected_revision" => material["revision"] }
)
assembly_id = assembly["value"]["id"]
read = PhComposer::API.query(context: context, name: "ph_composer.assemblies.assemblies.list",
                             params: { "ids" => [assembly_id] })
layer = read["value"]["records"].first["values"]["layers"].first
filled = PhComposer::API.invoke(
  context: context, name: "ph_composer.assemblies.assemblies.segments.set_material",
  params: { "id" => assembly_id, "expected_values" => {}, "layer_id" => layer["id"],
            "segment_id" => layer["segments"].first["id"], "material_id" => material["value"]["id"] },
  request: { "sequence" => 7, "expected_revision" => read["revision"] }
)
face = PhComposer::API.query(context: context, name: "ph_composer.zones.faces.list")["value"]["faces"]
                      .find { |row| row["values"]["face_type"] == "Wall" }
assigned = PhComposer::API.invoke(
  context: context, name: "ph_composer.zones.faces.assign_assembly",
  params: { "targets" => [{ "reference" => face["reference"], "expected_values" => face["values"] }],
            "assembly_id" => assembly_id },
  request: { "sequence" => 8, "expected_revision" => filled["revision"] }
)
```

Read the Faces again: the Wall's `values` now carry `assembly_id`, and the Assembly's row in
`assemblies.list` reports its thickness and U-values, or why they are withheld.

## 8. Read in pages, and export

Every list read answers one page. Name the values you need and pass `next_cursor` back for the next
page; a cursor only answers the same query and filter at the same revision.

```ruby
page = PhComposer::API.query(context: context, name: "ph_composer.zones.faces.list",
                             params: { "fields" => ["face_type", "boundary_condition"], "limit" => 100 })
page["value"]["faces"]        # reference and the two values, nothing else
page["value"]["next_cursor"]  # nil on the last page
```

Export is a task, not a Model change. It writes only to a destination the user approved once in the
Libraries dialog, never to a path you pass. Read the approved destinations, preflight to see what
blocks the export, then start it with the destination's id and poll until the status carries an
outcome. An existing pair is replaced only with `replace: true` and the `expected_destination` that
`export_preflight` reported for that location.

```ruby
locations = PhComposer::API.query(context: context, name: "ph_composer.locations.list")["value"]["locations"]
location = locations.find { |row| row["kind"] == "save_file" }
PhComposer::API.export_preflight(context: context)["value"]["findings"]
task = PhComposer::API.start_export(context: context, location: { "id" => location["id"] })["value"]
status = PhComposer::API.export_status(context: context, task_id: task["task_id"])["value"]
status["outcome"]             # nil while running; then completed, refused, failed or cancelled
PhComposer::API.latest_export(context: context)
```

When the outcome is `export.complete`, its `value.artifacts` says where the pair is, for you alone
as the caller that started it. Read the file and check its hash before parsing it:

```ruby
written = status["outcome"]["value"]["artifacts"]["hbjson"]
bytes = File.binread(written["path"])
# A later export to the same destination replaces the file; stop rather than parse another run's model.
raise "the export was replaced since this task" unless Digest::SHA256.hexdigest(bytes) == written["sha256"]
model = JSON.parse(bytes)
```

A Face without an authored Assembly blocks the export as `export.blocked`, and the preflight
findings name each one with the code `construction.missing`. Assign Assemblies with
`ph_composer.zones.faces.assign_assembly` before starting a real export. An interior Face (a
Surface pair) needs an Assembly only when its two Zones are in different Building-Segments.
Assigning one side gives the other side the same Assembly, reversed.
