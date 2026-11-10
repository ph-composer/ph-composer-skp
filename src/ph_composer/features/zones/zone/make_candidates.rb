# frozen_string_literal: true

module PhComposer
  module Zones
    # The Groups directly inside one edit context that Make Zone could turn into a Zone, found with no
    # selection, each with the refusal Make Zone would give it there (Zones.make_refusal, the action's own
    # check after its edit-path check). Make Zone runs in the open edit context, so a context that is not
    # open says so instead of refusing: `context.open` opens it. Reads only: it selects, opens and writes
    # nothing, and walks only that context, with the Model's Zones read once for the page.
    module MakeCandidates
      QUERY = "#{FEATURE_ID}.make_candidates".freeze

      module_function

      def read(request)
        model = request.model
        container = OccurrencePath.resolve(model, request.params.fetch("parent_path", []))
        children = container.entities.to_a
        groups = children.grep(Sketchup::Group).sort_by(&:persistent_id)
        open = Occurrences.active_path(model) == container.path
        shared = context_refusal(model, container.path)
        shared ||= ContextCommands.open_refusal(model, container.path) unless open
        build = lambda do |rows|
          zones = rows.empty? || shared ? [] : Occurrences.zones(model)
          rows.map { |group| row(model, container, group, shared, zones) }
        end
        page, next_cursor = Pages.bounded(request, QUERY, groups, :key => ->(group) { [group.persistent_id] },
                                                                  :prepare => build)
        { "parent_path" => container.path, "open_required" => !open,
          "candidates" => page, "next_cursor" => next_cursor, "total" => groups.length,
          "loose_faces" => children.count { |entity| entity.is_a?(Sketchup::Face) },
          "loose_edges" => children.count { |entity| entity.is_a?(Sketchup::Edge) } }
      end

      # What the action refuses for every candidate here before it looks at one: a path the edit context
      # cannot be (a component on it), as resolving its parent refuses. A context that is not open adds what
      # opening it would refuse (a locked step), which `context.open` checks the same way.
      def context_refusal(model, path)
        Occurrences.entities_at(model, path)
        nil
      rescue CodedError => error
        error
      end

      def row(model, container, group, shared, zones)
        refusal = shared || Zones.make_refusal(model, container.instances, [group], :zones => zones)
        { "path" => container.path + [group.persistent_id], "name" => group.name.to_s,
          "hidden" => OccurrencePath.hidden?(group),
          "make_zone" => { "parent_path" => container.path, "entity_ids" => [group.persistent_id] },
          "refusal" => refusal && { "code" => refusal.code, "message" => refusal.message } }
      end
      private_class_method :context_refusal, :row
    end
  end
end
