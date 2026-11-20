# frozen_string_literal: true

module PhComposer
  module Shading
    # The native selection as references, each with what assign and clear would do to it at this revision:
    # the read the right-click menu and a script take their targets from. Faces, Groups and components under
    # the active path are rows; anything else selected is counted as ignored and never written.
    module Selection
      # Selected entities that are not Faces, Groups or components are listed up to this many and counted in full.
      IGNORED_ROWS = 50

      module_function

      def read(request)
        model = request.model
        taken, others = model.selection.to_a.partition { |entity| Mark.kind(entity) }
        Mark.check_limit!(taken.length)
        parent = Array(model.active_path).map(&:persistent_id)
        paths = taken.map { |entity| parent + [entity.persistent_id] }.sort
        rows = Targets.facts(request, paths).map { |facts| row(facts) }
        { "entities" => rows,
          "ignored" => others.first(IGNORED_ROWS).map do |entity|
            { "persistent_id" => entity.persistent_id, "type" => entity.typename }
          end,
          "ignored_total" => others.length }
      end

      def row(facts)
        { "reference" => { "entity_path" => facts.path }, "kind" => facts.kind, "marked" => facts.marked,
          "assign" => outcome(Eligibility.assign(facts)), "clear" => outcome(Eligibility.clear(facts)) }
      end

      def outcome(judged)
        found, refusal = judged
        { "outcome" => found, "code" => refusal&.fetch("code"), "message" => refusal&.fetch("message") }
      end
    end
  end
end
