# frozen_string_literal: true

# Panel-closed public API example for Spaces, on any Model with two Zones:
#   SpacesWalkthrough.run
# Two kinds of step, kept apart. Native fixture setup (the `fixture_` methods) does what a user does with
# SketchUp's own tools: it draws three 1 m floor surfaces loose in the first Zone, 0.5 m above its origin,
# a fourth in the new Space, and later copies a Volume as a native copy leaves it. Everything else is the
# client, through PhComposer::API alone: it moves the edit path only with `ph_composer.context.open` and
# `.root`, finds the loose Face with `spaces.candidate_faces.list`, and never assigns a path or walks
# geometry. The client creates the Space from the three floor surfaces, which touch nowhere and so make three
# Volumes, then adds a fourth Volume, marks one Floor Segment as not counting, sets a height, two airflows and
# one cleared, reads back, recovers from a stale edit,
# reads the copy's duplicate identity and makes it independent, and moves the Space into the second
# Zone. Each write is one Undo step; navigation adds no operation of its own, though SketchUp records
# leaving a Group on its Undo stack. The refusals segment shows a stale path, a locked step and a wrong
# session each leaving the path and the Model as they were. `height_from_solid` then sets a Volume's
# height from a solid the operator draws.
module SpacesWalkthrough
  API = PhComposer::API
  PREFIX = "ph_composer.spaces"
  INCHES = 1.0 / 0.0254
  Client = Struct.new(:context, :sequence, :steps, keyword_init: true)

  module_function

  def run(session_id: nil, model: Sketchup.active_model)
    discovery = API.discover
    session_id ||= discovery.fetch("sessions").find { |row| row.fetch("active") }&.fetch("id")
    raise ArgumentError, "No open Model session." unless session_id

    client = Client.new(:context => API.connect(:session_id => session_id), :sequence => 0, :steps => [])
    client.steps << { "step" => "discover", "passed" => discovery.fetch("features").any? { |row| row["id"] == PREFIX } }
    zones = query(client, "ph_composer.zones.list").fetch("zones").map { |row| row.fetch("reference") }
    # Checked before anything is written, so a Model that cannot run the script is left as it was.
    raise ArgumentError, "Make two Zones first: the Space moves from the first to the second." if zones.length < 2

    zone = zones.first

    navigate(client, "open", "path" => zone.fetch("zone_path"), "expected_path" => edit_path(client))
    faces = [0, 1.5, 3].map { |x| fixture_outline(model, zone.fetch("zone_path"), x, 0) }
    created = invoke(client, "create", "zone" => zone, "name" => "Walkthrough", "faces" => faces.map do |face|
      zone.fetch("zone_path") + [face.persistent_id]
    end)
    space = space_row(client, created.fetch("space_id"))
    navigate(client, "open", "path" => space.dig("reference", "entity_path"))
    fixture_outline(model, space.dig("reference", "entity_path"), 0, 2)
    loose = query(client, "#{PREFIX}.candidate_faces.list", "space" => space.fetch("reference"))
            .fetch("candidate_faces").find { |row| row.fetch("candidate") == "volume" }
    invoke(client, loose.fetch("operation").delete_prefix("#{PREFIX}."),
           "space" => space.fetch("reference"), "faces" => [loose.fetch("entity_path")])
    space = space_row(client, created.fetch("space_id"))
    navigate(client, "root")
    first = space.dig("volumes", 0, "floor_segments", 0)
    invoke(client, "floors.mark", "faces" => [first.dig("reference", "entity_path")], "weighting_factor" => 0.0)
    invoke(client, "update", "reference" => space.dig("volumes", 0, "reference"),
                             "values" => { "avg_ceiling_height_m" => 2.7 },
                             "expected_values" => { "avg_ceiling_height_m" => space.dig("volumes", 0, "values",
                                                                                        "avg_ceiling_height_m") })
    invoke(client, "update", "reference" => space.fetch("reference"),
                             "values" => { "v_sup_m3h" => 60.0, "v_eta_m3h" => 40.0 }, "expected_values" => {})
    invoke(client, "update", "reference" => space.fetch("reference"), "values" => { "v_eta_m3h" => nil },
                             "expected_values" => { "v_eta_m3h" => 40.0 })
    recover_from_stale_edit(client, created.fetch("space_id"))
    result = read_back(client, session_id, created.fetch("space_id"))
    copy_and_repair(client, model, created.fetch("space_id"))
    move_to_second_zone(client, created.fetch("space_id"))
    refusals(client, created.fetch("space_id"))
    result.merge("passed" => client.steps.all? { |row| row.fetch("passed") }, "steps" => client.steps)
  end

  # A Volume copied as SketchUp copies a Group (a new placement of its definition carrying its
  # dictionaries) shares its identity: both read the duplicate, and Make independent on the copy clears it.
  # Height from solid, after `run`: draw a closed Group in a Space with a Volume, such as the walkthrough's
  # (on the host, a box pushed up from a rectangle), then pass its root-to-entity path. Previews, then sets
  # that Space's first Volume's height from it; one Undo step. Answers the preview and the written height.
  #   SpacesWalkthrough.height_from_solid([zone_id, space_id, solid_id])
  def height_from_solid(solid_path, session_id: nil)
    session_id ||= API.discover.fetch("sessions").find { |row| row.fetch("active") }&.fetch("id")
    client = Client.new(:context => API.connect(:session_id => session_id), :sequence => 0, :steps => [])
    space = query(client, "#{PREFIX}.all").fetch("spaces").find do |row|
      path = row.dig("reference", "entity_path")
      solid_path[0, path.length] == path
    end
    raise ArgumentError, "Draw the solid inside a Space with a Volume." unless space && !space.fetch("volumes").empty?

    volume = space.fetch("volumes").first
    params = { "volume" => volume.fetch("reference"), "solid" => solid_path }
    preview = query(client, "#{PREFIX}.volumes.height_from_solid_preview", params)
    invoke(client, "volumes.height_from_solid",
           params.merge("expected_values" => { "avg_ceiling_height_m" => preview.fetch("current_height_m") }))
    { "preview" => preview, "height_m" => space_row(client, space.fetch("id")).dig("volumes", 0, "values",
                                                                                   "avg_ceiling_height_m"),
      "steps" => client.steps }
  end

  def copy_and_repair(client, model, space_id)
    space = space_row(client, space_id)
    copy = fixture_copy(model, space.dig("volumes", 0, "reference", "entity_path"))
    copied = space_row(client, space_id).fetch("volumes").find do |row|
      row.dig("reference", "entity_path").last == copy.persistent_id
    end
    duplicate = space_row(client, space_id).fetch("volumes").count { |row| duplicate?(row) }
    client.steps << { "step" => "copy read as duplicate", "passed" => duplicate == 2 }
    invoke(client, "make_independent", "reference" => copied.fetch("reference"))
    clear = space_row(client, space_id).fetch("volumes").none? { |row| duplicate?(row) }
    client.steps << { "step" => "copy independent", "passed" => clear }
  end

  # Move Space to Zone needs the edit context closed; the Space keeps its ids and lands in the second Zone.
  def move_to_second_zone(client, space_id)
    navigate(client, "root")
    space = space_row(client, space_id)
    zone = query(client, "ph_composer.zones.list").fetch("zones").map { |row| row.fetch("reference") }
                                                  .find { |reference| reference != space.fetch("zone") }
    invoke(client, "move_to_zone", "space" => space.fetch("reference"), "zone" => zone)
    moved = space_row(client, space_id)
    client.steps << { "step" => "moved", "passed" => moved.dig("zone", "zone_id") == zone.fetch("zone_id") }
  end

  def duplicate?(row)
    row.fetch("findings").any? { |finding| finding["code"] == "space.duplicate_identity" }
  end

  # A stale path, a locked step and a wrong session each refuse with the path and the revision unchanged.
  def refusals(client, space_id)
    volume = space_row(client, space_id).dig("volumes", 0, "reference", "entity_path")
    before = [edit_path(client), revision(client)]
    stale = API.view(:context => client.context, :name => "ph_composer.context.open",
                     :params => { "path" => volume[0, 1], "expected_path" => volume })
    locked = API.view(:context => client.context, :name => "ph_composer.context.open", :params => { "path" => volume })
    stranger = begin
      API.connect(:session_id => "no-such-session")
    rescue PhComposer::CodedError => e
      e.code
    end
    unchanged = [edit_path(client), revision(client)] == before
    client.steps << { "step" => "refusals", "passed" => unchanged && stale["code"] == "target.edit_path_changed" &&
                                                        locked["code"] == "target.locked" &&
                                                        stranger == "session.unknown" }
  end

  # The Space has its four Volumes, one per separate floor surface, 3 m² weighted (one of four 1 m² Floor
  # Segments counts nothing), and the supply set, the extract cleared to a zero that counts and transfer unset.
  def read_back(client, session_id, space_id)
    space = space_row(client, space_id)
    metrics = space.fetch("metrics")
    weighted = (metrics.fetch("weighted_area_m2") - 3.0).abs < 1e-6
    flows = space.fetch("airflows") == { "v_sup_m3h" => 60.0, "v_eta_m3h" => 0.0, "v_tran_m3h" => 0.0 }
    client.steps << { "step" => "read back", "passed" => space.fetch("volumes").length == 4 && weighted && flows }
    { "session" => session_id, "space_id" => space_id, "metrics" => metrics,
      "passed" => client.steps.all? { |row| row.fetch("passed") }, "steps" => client.steps }
  end

  # A stale write refuses with nothing written; reading again and retrying succeeds.
  def recover_from_stale_edit(client, space_id)
    space = space_row(client, space_id)
    stale = attempt(client, "update", "reference" => space.fetch("reference"), "values" => { "name" => "Kitchen" },
                                      "expected_values" => { "name" => "Not what is stored" })
    client.steps << { "step" => "stale edit refused", "passed" => stale["code"] == "target.changed" &&
                                                                  stale["effect"] == "none" }
    fresh = space_row(client, space_id)
    invoke(client, "update", "reference" => fresh.fetch("reference"), "values" => { "name" => "Kitchen" },
                             "expected_values" => { "name" => fresh.dig("values", "name") })
  end

  # Native fixture setup: a 1 m square a user draws loose in the Group at `path`, at (x, y) metres and
  # 0.5 m up so it never splits an envelope Floor.
  def fixture_outline(model, path, x, y)
    corners = [[x, y], [x + 1, y], [x + 1, y + 1], [x, y + 1]]
    fixture_entity(model, path).entities.add_face(corners.map do |px, py|
      Geom::Point3d.new(px * INCHES, py * INCHES, 0.5 * INCHES)
    end)
  end

  # Native fixture setup: the Volume at `path` copied as SketchUp copies a Group, a new placement of its
  # definition carrying its dictionaries, beside it in its Space.
  def fixture_copy(model, path)
    volume = fixture_entity(model, path)
    copy = fixture_entity(model, path[0...-1]).entities.add_instance(volume.definition, volume.transformation)
    Array(volume.attribute_dictionaries).each do |dictionary|
      dictionary.each { |key, value| copy.set_attribute(dictionary.name, key, value) }
    end
    copy.locked = true
    copy
  end

  def fixture_entity(model, path)
    entities = model.entities
    path.map do |persistent_id|
      entity = entities.to_a.find { |candidate| candidate.persistent_id == persistent_id }
      entities = entity.respond_to?(:entities) ? entity.entities : nil
      entity
    end.last
  end

  # The client's edit path and the Model revision, from the context read.
  def edit_path(client)
    query(client, "ph_composer.context.read").fetch("edit_path").map { |step| step.fetch("persistent_id") }
  end

  def revision(client)
    query(client, "ph_composer.context.read").dig("session", "revision")
  end

  # `ph_composer.context.open` or `.root`, a view command: it moves the edit path and writes nothing.
  def navigate(client, command, params = {})
    outcome = API.view(:context => client.context, :name => "ph_composer.context.#{command}", :params => params)
    client.steps << { "step" => "context.#{command}", "passed" => outcome["status"] == "completed" }
    raise "context.#{command} failed: #{outcome['code']}: #{outcome['message']}" unless outcome["status"] == "completed"

    outcome.fetch("value")
  end

  # A Space with its Volumes and their Floor Segments, read as a client with a reply budget reads them:
  # the summary, then each child by reference.
  def space_row(client, id)
    space = query(client, "#{PREFIX}.list", "ids" => [id]).fetch("spaces").first
    return nil unless space

    volumes = every_page(client, "#{PREFIX}.volumes.list", { "space" => space.fetch("reference") }, "volumes")
    space.merge("volumes" => volumes.map do |volume|
      volume.merge("floor_segments" => every_page(client, "#{PREFIX}.floor_segments.list",
                                                  { "volume" => volume.fetch("reference") }, "floor_segments"))
    end)
  end

  # Every row of a paged read: each page within the reply budget, followed by its cursor.
  def every_page(client, name, params, key)
    page = query(client, name, params)
    rows = page.fetch(key)
    while (cursor = page["next_cursor"])
      page = query(client, name, params.merge("cursor" => cursor))
      rows += page.fetch(key)
    end
    rows
  end

  def query(client, name, params = {})
    outcome = API.query(:context => client.context, :name => name, :params => params)
    raise "#{name} failed: #{outcome['code']}" unless outcome["code"] == "ok"

    outcome.fetch("value")
  end

  def attempt(client, name, params)
    revision = API.query(:context => client.context, :name => "#{PREFIX}.settings.get").fetch("revision")
    client.sequence += 1
    API.invoke(:context => client.context, :name => "#{PREFIX}.#{name}", :params => params,
               :request => { "sequence" => client.sequence, "expected_revision" => revision })
  end

  def invoke(client, name, params)
    outcome = attempt(client, name, params)
    passed = outcome["effect"] == "committed"
    client.steps << { "step" => name, "passed" => passed, "code" => outcome["code"] }
    raise "#{name} failed: #{outcome['code']}: #{outcome['message']}" unless passed

    outcome.fetch("value")
  end
end
