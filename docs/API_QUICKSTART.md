# API quickstart

Use `PhComposer::API` from Ruby inside SketchUp. Open a scratch model and select a Group
or loose geometry suitable for Make Zone. The examples create and edit records in that model.
The [API reference](API_REFERENCE.md) lists operation schemas and examples. For a separate MCP
client, use [Agent Access](AGENT_ACCESS.md).

The [Ruby client test](../tests/api_client_test.rb) covers editing, retries, paging and export task setup.

## 1. Find the Model and connect

```ruby
found = PhComposer::API.discover
session = found["sessions"].find { |row| row["active"] }
context = PhComposer::API.connect(session_id: session["id"], capabilities: %w[read view model_write export])
```

Request the grants your script needs. This example uses `export` in step 8. Add `setup` only
for library loading or changes to this computer's setup.

Use `discover` to list registrations. Use `describe` to read a declaration's schema and example.

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

Read `make_zone` for the current selection. If it is null, select eligible geometry first.
Preview the change and pass its digest to `invoke` to apply the reviewed proposal.

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

Use the Face's occurrence reference and pass its last-read values as `expected_values`.
The write refuses if those values changed.

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

If a reply is lost, retry the identical request with the same sequence to recover its outcome.
Use `PhComposer::API.outcome(context:, request: { "sequence" => n })` to look it up without a retry.
A request refused as `request.malformed` leaves the sequence available for the corrected request.
Use `PhComposer::API.outcomes(context:, limit:, cursor:)` to page this caller's outcome summaries,
newest first. The session retains up to 256 outcomes across callers for up to 15 minutes.

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

Approve a destination in Libraries or with **Allow agents to export here** in the Export tab.
Use its ID to preflight the export and resolve any blocking findings. To replace an existing pair,
send `replace: true` and the destination state reported by preflight as `expected_destination`.
Pass the reviewed model revision as `expected_revision:` to catch intervening edits.

```ruby
locations = PhComposer::API.query(context: context, name: "ph_composer.locations.list")["value"]["locations"]
location = locations.find { |row| row["kind"] == "save_file" }
destination = { "id" => location.fetch("id") }
preflight = PhComposer::API.export_preflight(context: context, location: destination)
preflight["value"]["findings"] # Resolve blockers and run preflight again before starting.
task = PhComposer::API.start_export(context: context, location: destination,
                                   expected_revision: preflight["revision"])["value"]
status = PhComposer::API.export_status(context: context, task_id: task["task_id"])["value"]
status["outcome"]             # nil while running; then completed, refused, failed or cancelled
PhComposer::API.latest_export(context: context)
```

Run the status call again after SketchUp processes the task. When the outcome code is
`export.complete`, read the artifact receipt as the caller that started it. Verify the bytes
before parsing.

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
