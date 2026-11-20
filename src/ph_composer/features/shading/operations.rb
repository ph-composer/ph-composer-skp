# frozen_string_literal: true

module PhComposer
  module Shading
    # Assign and Clear over explicit references. Each resolves every target strictly, so a stale path refuses
    # the whole command; judges each with Eligibility; and writes what can change in one step, so the command is
    # one native operation and one Undo step. What cannot change is named in `left_out` with its code. The
    # command refuses whole only when every target is left out; the dispatcher owns the operation.
    module Operations
      module_function

      def assign(request, proposal, targets:)
        run(request, proposal, targets, :done => "assigned", :change => "created", :verb => "take the mark") do |facts|
          Eligibility.assign(facts)
        end
      end

      def clear(request, proposal, targets:)
        run(request, proposal, targets, :done => "cleared", :change => "removed", :verb => "lose a mark") do |facts|
          Eligibility.clear(facts)
        end
      end

      def run(request, proposal, targets, done:, change:, verb:)
        # The params schema bounds `targets` at Mark::TARGET_LIMIT.
        paths = targets.map { |target| target.fetch("entity_path") }.uniq
        judged = Targets.facts(request, paths).map { |facts| [facts, *yield(facts)] }
        value = { done => references(judged, done), "unchanged" => references(judged, "unchanged"),
                  "left_out" => judged.select { |_facts, outcome, _refusal| outcome == "left_out" }
                                      .map { |facts, _outcome, refusal| reference(facts).merge(refusal) } }
        refuse!(value, verb) if value.fetch(done).empty? && value.fetch("unchanged").empty?

        propose(request.model, proposal, value.fetch(done), change)
        value
      end

      def references(judged, outcome)
        judged.select { |_facts, found, _refusal| found == outcome }.map { |facts, _found, _refusal| reference(facts) }
      end

      def reference(facts)
        { "entity_path" => facts.path }
      end

      # Every target left out: the first one's code, with the whole result in the detail.
      def refuse!(value, verb)
        rows = value.fetch("left_out")
        first = rows.first
        message = if rows.length == 1
                    first.fetch("message")
                  else
                    "None of the #{rows.length} entities can #{verb}. The first: #{first.fetch('message')}"
                  end
        raise CodedError.new(first.fetch("code"), "#{message} Nothing was written.", value)
      end

      def propose(model, proposal, references, change)
        return if references.empty?

        updates = references.map do |row|
          { "entity_path" => row.fetch("entity_path"), "change" => change, "marked" => change == "removed" }
        end
        scopes = references.map { |row| scope_path(model, row.fetch("entity_path")) }.uniq.map do |path|
          PhComposer::Operations::EntityScope.new(path)
        end
        proposal.add_step(Mark::WriteStep.new(:updates => updates), :scopes => scopes)
      end

      # The Groups from the root above the entity, up to the first component: the deepest collection the
      # operation's abort check can resolve, and it holds the entity at some depth.
      def scope_path(model, path)
        above = Targets.resolve!(model, path)[0...-1]
        above.take_while { |entity| entity.is_a?(Sketchup::Group) }.map(&:persistent_id)
      end
    end
  end
end
