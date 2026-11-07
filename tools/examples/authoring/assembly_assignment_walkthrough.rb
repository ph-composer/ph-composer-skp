# frozen_string_literal: true

# Run in a Model with a current Surface pair. Uses only discovery and the public read/write API;
# the supplied session is explicit, and every edit carries its current revision and value guards.
module PhComposerAssemblyAssignmentWalkthrough
  API = PhComposer::API
  FACES = "ph_composer.zones.faces"
  ASSEMBLIES = "ph_composer.assemblies.assemblies"

  module_function

  def run(session_id:)
    context = API.connect(:session_id => session_id)
    sequence = 0
    invoke = lambda do |name, params|
      sequence += 1
      revision = query(context, "#{FACES}.all").fetch("revision")
      result = API.invoke(:context => context, :name => name, :params => params,
                          :request => { "sequence" => sequence, "expected_revision" => revision })
      raise "#{name}: #{result['code']} #{result['message']}" unless result["status"] == "completed"

      result
    end
    before = query(context, "#{FACES}.all").dig("value", "faces")
    left = before.find { |row| row["adjacency_state"] == "current" }
    raise "The walkthrough needs a current Surface pair." unless left

    counterpart = left.dig("values", "adjacency", "counterpart")
    right = before.find { |row| row.fetch("reference") == counterpart }
    raise "The Surface counterpart is not readable." unless right

    ids = %w[Original Replacement].map do |label|
      invoke.call("#{ASSEMBLIES}.create", "values" => { "name" => "Assignment walkthrough #{label}" })
            .dig("value", "id")
    end
    # One side is enough: the counterpart takes the same Assembly reversed.
    targets = [{ "reference" => left.fetch("reference"), "expected_values" => left.fetch("values") }]
    invoke.call("#{FACES}.assign_assembly", "targets" => targets, "assembly_id" => ids.first)
    assigned = query(context, "#{FACES}.all").dig("value", "faces")
    sides = assigned.select { |row| [left, right].any? { |old| old.fetch("reference") == row.fetch("reference") } }
    preserved = sides.all? do |row|
      old = [left, right].find { |entry| entry.fetch("reference") == row.fetch("reference") }
      assignment = %w[assembly_id assembly_reversed]
      row.fetch("values").reject { |key, _value| assignment.include?(key) } ==
        old.fetch("values").reject { |key, _value| assignment.include?(key) } &&
        row.dig("values", "assembly_id") == ids.first && row["adjacency_state"] == "current"
    end
    invoke.call("#{ASSEMBLIES}.delete", "id" => ids.first, "replacement_id" => ids.last)
    after = query(context, "#{FACES}.all").dig("value", "faces")
    replacements = after.select { |row| [left, right].any? { |old| old.fetch("reference") == row.fetch("reference") } }
    catalog = query(context, "#{ASSEMBLIES}.all").dig("value", "records")
    { "session" => session_id, "passed" => preserved && replacements.length == 2 &&
      replacements.all? { |row| row.dig("values", "assembly_id") == ids.last && row["adjacency_state"] == "current" } &&
      catalog.none? { |row| row["id"] == ids.first },
      "replacement_id" => ids.last, "faces" => replacements.map { |row| row.fetch("reference") } }
  end

  def query(context, name)
    result = API.query(:context => context, :name => name)
    raise "#{name}: #{result['code']} #{result['message']}" unless result["status"] == "completed"

    result
  end
end
