# frozen_string_literal: true

# Run in SketchUp with the panel closed, in a Model holding no Programs or Schedules of its own:
#   LibraryProgramsWalkthrough.run(file_path: "/absolute/path/to/programs.json")
# Use the sibling synthetic fixture. Setup is a per-machine prerequisite; every catalog and Model operation
# below uses the public API. A library Program is copied with the two Schedules it names and made the Model's
# default in one Undo step, then copied again, which reuses the Program and its Schedules and writes nothing.
module LibraryProgramsWalkthrough
  API = PhComposer::API
  PROVIDER_ID = "example.library_programs_walkthrough"
  LIBRARY = "ph_composer.library"
  PROGRAMS = "ph_composer.programs"
  LIBRARY_ID = "example.programs"
  RECORD_ID = "example-office"
  UNDO_NAMES = ["Copy Library Record"].freeze

  module_function

  def run(file_path:, session_id: nil)
    discovery = API.discover
    session_id ||= discovery.fetch("sessions").find { |row| row.fetch("active") }&.fetch("id")
    raise ArgumentError, "No open Model session." unless session_id

    context = API.connect(:session_id => session_id, :capabilities => %w[read view model_write setup])
    require_no_stored_programs!(context)

    configured = false
    PhComposer::Library::Setup.add_file(:id => PROVIDER_ID, :label => "Synthetic programs", :path => file_path)
    configured = true
    generations = %w[schedules programs].to_h { |kind| [kind, load(context, kind)] }
    copy_and_read_back(context, session_id, generations)
  ensure
    PhComposer::Library::Setup.remove(PROVIDER_ID) if configured
  end

  def require_no_stored_programs!(context)
    %w[programs schedules].each do |collection|
      records = checked(API.query(:context => context, :name => "#{PROGRAMS}.#{collection}.all")).fetch("records")
      raise ArgumentError, "Use a Model with no Programs or Schedules of its own." if records.any? { |row|
        row["stored"]
      }
    end
    if PhComposer::Library::Setup.providers.any? { |provider| provider.fetch("id") == PROVIDER_ID }
      raise ArgumentError, "The walkthrough provider id is already configured."
    end
  end

  def load(context, kind)
    loaded = checked(API.setup(:context => context, :name => "#{LIBRARY}.load",
                               :params => { "provider_id" => PROVIDER_ID, "kind" => kind }))
    raise "The synthetic #{kind} catalog did not load." unless loaded.fetch("state") == "loaded"

    loaded.fetch("generation")
  end

  def copy_params(generations, choice, settings)
    { "provider_id" => PROVIDER_ID, "kind" => "programs", "generation" => generations.fetch("programs"),
      "library_id" => LIBRARY_ID, "record_id" => RECORD_ID, "choice" => choice,
      "assignment" => { "mode" => "model_default", "expected_settings" => settings } }
  end

  # Preview, then apply with the preview's digest.
  def copy(context, params, sequence)
    preview = API.preview(:context => context, :name => "#{LIBRARY}.copy", :params => params)
    checked(preview)
    request = { "sequence" => sequence, "expected_revision" => preview.fetch("revision"),
                "proposal_digest" => preview.fetch("proposal_digest") }
    [preview, API.invoke(:context => context, :name => "#{LIBRARY}.copy", :params => params, :request => request)]
  end

  def copy_and_read_back(context, session_id, generations)
    settings = checked(API.query(:context => context, :name => "#{PROGRAMS}.settings.get"))
    preview, first = copy(context, copy_params(generations, "create", settings), 1)
    raise "The copy needs review." unless preview.dig("value", "resolution", "outcome") == "create"

    copied = checked(first)
    program = record(context, "programs", copied.fetch("local_id"))
    schedules = checked(API.query(:context => context, :name => "#{PROGRAMS}.schedules.all")).fetch("records")
                                                                                             .select { |row|
      row.dig(
        "values", "source", "library_id"
      ) == LIBRARY_ID
    }
    default = checked(API.query(:context => context, :name => "#{PROGRAMS}.settings.get"))
    named = [program.dig("values", "people", "occupancy_schedule_id"),
             program.dig("values", "ventilation", "schedule_id")]

    settings_now = checked(API.query(:context => context, :name => "#{PROGRAMS}.settings.get"))
    preview, second = copy(context, copy_params(generations, "keep_local", settings_now), 2)
    again = checked(second)
    after = checked(API.query(:context => context, :name => "#{PROGRAMS}.schedules.all")).fetch("records")
                                                                                         .count { |row|
      row.dig(
        "values", "source", "library_id"
      ) == LIBRARY_ID
    }
    passed = first.fetch("effect") == "committed" && copied.fetch("assigned") &&
             copied.fetch("dependencies").map { |row| row.fetch("outcome") } == %w[created created] &&
             schedules.length == 2 && named.sort == schedules.map { |row| row.fetch("id") }.sort &&
             default.fetch("default_program_id") == copied.fetch("local_id") &&
             preview.dig("value", "resolution", "outcome") == "reuse" &&
             again.fetch("local_id") == copied.fetch("local_id") && second.fetch("effect") == "none" && after == 2
    { "session_id" => session_id, "passed" => !!passed, "program_id" => copied.fetch("local_id"),
      "schedule_ids" => schedules.map { |row| row.fetch("id") }.sort, "dependencies" => copied.fetch("dependencies") }
  end

  def record(context, collection, id)
    page = checked(API.query(:context => context, :name => "#{PROGRAMS}.#{collection}.list",
                             :params => { "ids" => [id] }))
    page.fetch("records").first || raise("#{collection} #{id} was not read back.")
  end

  def checked(outcome)
    raise "Public operation failed: #{outcome['code']}" unless outcome["code"] == "ok"

    outcome.fetch("value")
  end
end
