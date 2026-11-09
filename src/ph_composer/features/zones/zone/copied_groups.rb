# frozen_string_literal: true

module PhComposer
  module Zones
    # A plain Group copied whole, such as a storey Group holding Zones and Spaces: until the copy is given
    # its own definition its children are the original's under a second path, and no repair of a child
    # can write the copy alone (context/SKETCHUP_HOST_BEHAVIOR.md, "Window Units inside a copied Zone").
    # Each watcher that repairs a copy asks here first. Keyed by the containers the gesture added, so the
    # original is never touched, and idempotent, so either watcher may run first.
    module CopiedGroups
      ACTION = "#{FEATURE_ID}.isolate_copied_group"

      module_function

      # The root-to-Group paths of the added plain Groups above `paths` still sharing their contents. A
      # path whose added container is the occurrence itself has nothing above it to isolate.
      def roots(model, paths, added)
        paths.filter_map do |path|
          index = path.index { |persistent_id| added.include?(persistent_id) }
          next if index.nil? || index == path.length - 1

          root = path[0..index]
          entities = Repair.path_entities(model, root)
          group = entities.last
          root if group.is_a?(Sketchup::Group) && Occurrences.shared_storage?(group) &&
                  entities[0...-1].none? { |entity| Occurrences.shared_storage?(entity) }
        end.uniq
      end

      # Isolates the copied Groups above `paths`, joined to the copy. Answers whether any was. A refusal
      # leaves the copy's own repair to report it, as it does today.
      def isolate(session, paths, added)
        found = roots(session.model, paths, added)
        return false if found.empty?

        result = HostFollowUp.run(session, ACTION, found.map { |path| { "group_path" => path } })
        Diagnostics.log("copied_group_isolation", "status" => result.fetch("status"))
        result.fetch("status") == "completed"
      end
    end
  end
end
