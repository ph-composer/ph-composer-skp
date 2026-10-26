# frozen_string_literal: true

require_relative "../../core/view_framing"

module PhComposer
  module ThermalBridges
    # runs.locate: select a run's Edges and bring them into view. A run has no stored identity, so the
    # caller passes its Edge paths as the schedule read them. The Edges' container opens as the edit
    # context through the foundation's ph_composer.context.open (context/AGENT_INTERFACE.md, "Model
    # context"), so its refusals and every feature's boundary apply; nothing here navigates on its own.
    module RunLocate
      module_function

      def call(request, edge_paths:)
        model = request.model
        containers = edge_paths.map { |path| path[0...-1] }.uniq
        if containers.length > 1
          raise CodedError.new("params.invalid", "Locate one run at a time: these Edges sit in different containers.")
        end

        children = Zones::ChildLookup.new
        chains = edge_paths.map { |path| along(model, path, children) }
        if chains.any? { |chain| chain.any? { |entity| hidden?(entity) } }
          raise CodedError.new("thermal_bridge.hidden", "An Edge of the run, or a Group holding it, is hidden or on " \
                                                        "a hidden tag; show it and locate again. Nothing moved.")
        end

        ContextCommands.move(request.with(:params => {}), containers.first)
        edges = chains.map(&:last)
        model.selection.clear
        model.selection.add(edges)
        frame(model, chains)
        { "path" => EditContext.current_ids(model), "selected" => edges.length }
      end

      # The entities a root-to-Edge path names, each the unique child of the one before. One lookup serves
      # every path of the call, so a run of many Edges scans their container once.
      def along(model, path, children)
        entities = model.entities
        chain = path.each_with_index.map do |id, index|
          matches = children.matching(entities, id)
          raise CodedError.new("target.not_found", "No single entity #{id} is at that step.") unless matches.length == 1

          entity = matches.first
          entities = contents(entity) unless index == path.length - 1
          entity
        end
        return chain if chain.last.is_a?(Sketchup::Edge)

        raise CodedError.new("target.wrong_kind", "The path does not end at an Edge.")
      end

      def contents(entity)
        return entity.entities if entity.is_a?(Sketchup::Group)
        return entity.definition.entities if entity.is_a?(Sketchup::ComponentInstance)

        raise CodedError.new("target.wrong_kind", "The path passes through #{entity.typename}, not a container.")
      end

      def hidden?(entity)
        return true if entity.respond_to?(:hidden?) && entity.hidden?

        hidden_tag?(entity.respond_to?(:layer) ? entity.layer : nil)
      end

      # A tag shows only when it and every tag folder holding it are visible.
      def hidden_tag?(tag)
        while tag
          return true if tag.respond_to?(:visible?) && !tag.visible?

          tag = tag.respond_to?(:folder) ? tag.folder : nil
        end
        false
      end

      # Frames by world endpoints, composed from the root, so a context open or not gives the same view.
      def frame(model, chains)
        view = model.respond_to?(:active_view) ? model.active_view : nil
        points = chains.flat_map do |chain|
          transform = chain[0...-1].reduce(Geom::Transformation.new) { |carried, entity|
            carried * entity.transformation
          }
          [chain.last.start, chain.last.end].map { |vertex| vertex.position.transform(transform) }
        end
        ViewFraming.call(view, points, chains.map(&:last))
      end
      private_class_method :along, :contents, :hidden?, :hidden_tag?, :frame
    end
  end
end
