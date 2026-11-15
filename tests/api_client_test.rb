# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# Offline: a client that knows only the public interface and docs/API_QUICKSTART.md makes a Zone,
# reads its Faces, classifies one, previews and makes an edit, verifies what changed, recovers from a
# stale revision, retries a lost response, gives the Face an Assembly and attaches user_data to the Face and
# its Material. It names no feature module;
# the host side of the test only draws geometry and selects it, as a user would.
class ApiClientTest < PhComposerTestCase
  API = PhComposer::API

  def setup
    super
    faces = 3.times.map do |index|
      Sketchup::Face.new(1202 + index, {}, :points => [Geom::Point3d.new(0, 0, index), Geom::Point3d.new(40, 0, index),
                                                       Geom::Point3d.new(40, 40, index)])
    end
    group = Sketchup::Group.new(1201, Sketchup::Entities.new(faces))
    Sketchup.active_model.entities << group
    Sketchup.active_model.selection.add(group)
  end

  def test_the_quickstart_runs_as_written
    context = connect
    zones, made = make_zone(context)
    classified, written = classify_first_face(context)
    edit, preview, updated = edit_zone(context, classified)

    assert_equal [made.dig("value", "zone_id")], made["affected"].select { |row| row["kind"] == "zone" }
                                                                 .map { |row| row["id"] }
    assert_equal 3, made["affected"].count { |row| row["kind"] == "face" }
    assert_equal "Wall", faces(context).find { |row| row["reference"] == written }.dig("values", "face_type")

    # 5. A write based on an old read refuses and changes nothing.
    stale = API.invoke(:context => context, :name => "ph_composer.zones.update", :params => edit,
                       :request => { "sequence" => 4, "expected_revision" => zones["revision"] })
    assert_equal %w[refused revision.stale none], stale.values_at("status", "code", "effect")

    # 6. The same request again returns the first outcome and writes nothing twice.
    undo_steps = Sketchup.active_model.instance_variable_get(:@undo_stack).length
    retried = API.invoke(:context => context, :name => "ph_composer.zones.update", :params => edit,
                         :request => { "sequence" => 3, "expected_revision" => classified["revision"],
                                       "proposal_digest" => preview["proposal_digest"] })
    assert_equal updated, retried
    assert_equal updated, API.outcome(:context => context, :request => { "sequence" => 3 })
    assert_equal undo_steps, Sketchup.active_model.instance_variable_get(:@undo_stack).length

    material = assign_an_assembly(context, updated)
    read_in_pages_and_export(context)
    attach_user_data(context, material)
  end

  def test_the_client_names_no_feature_module
    source = File.read(__FILE__)
    %w[Zones Faces FaceAssignment].each do |name|
      refute_match(/PhComposer::#{name}\b/, source.sub(/%w\[Zones Faces FaceAssignment\]/, ""))
    end
  end

  private

  # 1. Find the Model and connect.
  def connect
    found = API.discover
    session = found["sessions"].find { |row| row["active"] }
    assert_empty %w[params result examples] - API.describe(:name => "ph_composer.zones.make").keys
    assert API.describe(:name => "ph_composer.zones.faces.face").key?("occurrence_reference")
    API.connect(:session_id => session["id"], :capabilities => %w[read view model_write export])
  end

  # 7. Give the Face an Assembly.
  def assign_an_assembly(context, updated)
    material = API.invoke(
      :context => context, :name => "ph_composer.assemblies.materials.create",
      :params => { "values" => { "name" => "Mineral wool", "conductivity_w_mk" => 0.035 } },
      :request => { "sequence" => 5, "expected_revision" => updated["revision"] }
    )
    assembly = API.invoke(
      :context => context, :name => "ph_composer.assemblies.assemblies.create",
      :params => { "values" => { "name" => "Wall A" } },
      :request => { "sequence" => 6, "expected_revision" => material["revision"] }
    )
    assembly_id = assembly["value"]["id"]
    read = API.query(:context => context, :name => "ph_composer.assemblies.assemblies.list",
                     :params => { "ids" => [assembly_id] })
    layer = read["value"]["records"].first["values"]["layers"].first
    filled = API.invoke(
      :context => context, :name => "ph_composer.assemblies.assemblies.segments.set_material",
      :params => { "id" => assembly_id, "expected_values" => {}, "layer_id" => layer["id"],
                   "segment_id" => layer["segments"].first["id"], "material_id" => material["value"]["id"] },
      :request => { "sequence" => 7, "expected_revision" => read["revision"] }
    )
    face = faces(context).find { |row| row["values"]["face_type"] == "Wall" }
    assigned = API.invoke(
      :context => context, :name => "ph_composer.zones.faces.assign_assembly",
      :params => { "targets" => [{ "reference" => face["reference"], "expected_values" => face["values"] }],
                   "assembly_id" => assembly_id },
      :request => { "sequence" => 8, "expected_revision" => filled["revision"] }
    )
    assert_equal %w[committed committed committed committed],
                 [material, assembly, filled, assigned].map { |outcome| outcome["effect"] }
    assert_equal assembly_id, faces(context).find { |row| row["reference"] == face["reference"] }
                                            .dig("values", "assembly_id")
    material
  end

  # 9. Attach your own data to a Face and a Material: read, change one key, guarded write, read back, clear.
  def attach_user_data(context, material)
    read = API.query(:context => context, :name => "ph_composer.zones.faces.list")
    face = read["value"]["faces"].find { |row| row["values"]["face_type"] == "Wall" }
    assert_equal [{}, {}], face.values_at("user_data", "extension_data")
    mine = face["user_data"].merge("example_org" => { "review_status" => "needs_site_check", "detail" => "A-503/7" })
    tagged = write_face_metadata(context, face, mine, 9, read["revision"])
    assert_equal "committed", tagged["effect"], tagged.inspect
    steps = undo_steps
    noted = note_material(context, material)
    assert_equal steps + 1, undo_steps, "one write, one Undo step"

    face = faces(context).find { |found| found["reference"] == face["reference"] }
    assert_equal({ "example_org" => { "review_status" => "needs_site_check", "detail" => "A-503/7" } },
                 face["user_data"])
    cleared = write_face_metadata(context, face, {}, 11, noted["revision"])
    assert_equal "committed", cleared["effect"], cleared.inspect
    assert_equal({}, faces(context).find { |found| found["reference"] == face["reference"] }["user_data"])
    # A write guarded by maps that changed since they were read refuses and writes nothing.
    stale = write_face_metadata(context, face, { "late" => true }, 12, cleared["revision"])
    assert_equal %w[target.changed none], stale.values_at("code", "effect")
    # Clearing it again sends what is stored: no Undo step.
    cleared_face = faces(context).find { |found| found["reference"] == face["reference"] }
    steps = undo_steps
    again = write_face_metadata(context, cleared_face, {}, 13, cleared["revision"])
    assert_equal %w[completed none], again.values_at("status", "effect")
    assert_equal steps, undo_steps
  end

  # The core action writes any definition kind's map by {kind, id}.
  def note_material(context, material)
    params = { "kind" => "ph_composer.assemblies.material", "ids" => [material["value"]["id"]] }
    read = API.query(:context => context, :name => "ph_composer.records.list", :params => params)
    row = read["value"]["records"].first
    noted = API.invoke(
      :context => context, :name => "ph_composer.records.update_metadata",
      :params => { "updates" => [{ "reference" => { "kind" => row["kind"], "id" => row["id"] },
                                   "user_data" => row["user_data"].merge("example_org" => { "spec" => "07 21 00" }),
                                   "expected_metadata" => row.slice("user_data", "extension_data") }] },
      :request => { "sequence" => 10, "expected_revision" => read["revision"] }
    )
    assert_equal "committed", noted["effect"], noted.inspect
    back = API.query(:context => context, :name => "ph_composer.records.list", :params => params)
    # A read is a copy: changing the row read changes nothing stored.
    back.dig("value", "records", 0, "user_data", "example_org")["spec"] = "changed in the script only"
    again = API.query(:context => context, :name => "ph_composer.records.list", :params => params)
    assert_equal({ "example_org" => { "spec" => "07 21 00" } }, again.dig("value", "records", 0, "user_data"))
    noted
  end

  def undo_steps
    Sketchup.active_model.instance_variable_get(:@undo_stack).length
  end

  # The whole map to keep, guarded by the Face's two maps as `face` read them.
  def write_face_metadata(context, face, user_data, sequence, revision)
    API.invoke(
      :context => context, :name => "ph_composer.zones.faces.update_metadata",
      :params => { "updates" => [{ "reference" => face["reference"], "user_data" => user_data,
                                   "expected_metadata" => face.slice("user_data", "extension_data") }] },
      :request => { "sequence" => sequence, "expected_revision" => revision }
    )
  end

  # 8. Read in pages, and export. The task is cancelled before its runtime starts, as the offline suite
  # has no translation runtime; the host run takes it to its outcome.
  def read_in_pages_and_export(context)
    page = API.query(:context => context, :name => "ph_composer.zones.faces.list",
                     :params => { "fields" => %w[face_type boundary_condition], "limit" => 2 })
    assert_equal [%w[reference values]], page["value"]["faces"].map { |row| row.keys.sort }.uniq
    second = API.query(:context => context, :name => "ph_composer.zones.faces.list",
                       :params => { "fields" => %w[face_type boundary_condition], "limit" => 2,
                                    "cursor" => page["value"]["next_cursor"] })
    assert_equal 1, second["value"]["faces"].length

    assert_equal "completed", API.export_preflight(:context => context)["status"]
    Dir.mktmpdir("phc-quickstart-") do |directory|
      # The user approves the destination once, in the Libraries dialog; the client reads its id.
      PhComposer::ApprovedLocations.approve(:kind => "save_file", :path => File.join(directory, "model.hbjson"))
      location = API.query(:context => context, :name => "ph_composer.locations.list")["value"]["locations"]
                    .find { |row| row["kind"] == "save_file" }
      task = API.start_export(:context => context, :location => { "id" => location["id"] })["value"]
      assert_nil API.export_status(:context => context, :task_id => task["task_id"])["value"]["outcome"]
      API.cancel_export(:context => context, :task_id => task["task_id"])
      assert_equal task["task_id"], API.latest_export(:context => context)["value"]["task_id"]
    end
  end

  # 2. Make a Zone from the selection.
  def make_zone(context)
    zones = API.query(:context => context, :name => "ph_composer.zones.list")
    target = zones["value"]["make_zone"]
    preview = API.preview(:context => context, :name => "ph_composer.zones.make", :params => target)
    made = API.invoke(:context => context, :name => "ph_composer.zones.make", :params => target,
                      :request => { "sequence" => 1, "expected_revision" => zones["revision"],
                                    "proposal_digest" => preview["proposal_digest"] })
    assert_equal %w[completed committed], made.values_at("status", "effect")
    [zones, made]
  end

  # 3. Read the Zone's Faces and classify one.
  def classify_first_face(context)
    read = API.query(:context => context, :name => "ph_composer.zones.faces.list")
    face = read["value"]["faces"].first
    classified = API.invoke(
      :context => context, :name => "ph_composer.zones.faces.classify",
      :params => { "faces" => [face["reference"]], "expected_values" => face["values"],
                   "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                                 "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } } },
      :request => { "sequence" => 2, "expected_revision" => read["revision"] }
    )
    written = classified["affected"].first["reference"]
    assert_equal "committed", classified["effect"]
    assert_equal face["reference"].merge("entity_id" => classified.dig("value", "face_ids", 0)), written
    [classified, written]
  end

  # 4. Preview and edit the Zone, then verify by reading back.
  def edit_zone(context, classified)
    zone = API.query(:context => context, :name => "ph_composer.zones.list")["value"]["zones"].first
    edit = { "reference" => zone["reference"], "expected_values" => zone["values"],
             "values" => zone["values"].merge("name" => "North Zone") }
    preview = API.preview(:context => context, :name => "ph_composer.zones.update", :params => edit)
    updated = API.invoke(:context => context, :name => "ph_composer.zones.update", :params => edit,
                         :request => { "sequence" => 3, "expected_revision" => classified["revision"],
                                       "proposal_digest" => preview["proposal_digest"] })
    assert_equal "committed", updated["effect"]
    assert_includes updated["affected"].map { |row| row["id"] }, zone["id"]
    read_back = API.query(:context => context, :name => "ph_composer.zones.list")["value"]["zones"].first
    assert_equal edit["values"], read_back["values"]
    [edit, preview, updated]
  end

  def faces(context)
    API.query(:context => context, :name => "ph_composer.zones.faces.list").dig("value", "faces")
  end
end
