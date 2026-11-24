# frozen_string_literal: true

module PhComposer
  module Piping
    # runs.locate: select a run's pipes and bring them into view. A run has no stored identity, so the caller passes
    # its Edge paths as the schedule read them. The Piping group holding them opens as the edit context through the
    # foundation's ph_composer.context.open (context/AGENT_INTERFACE.md, "Model context"), so its refusals apply;
    # nothing here navigates on its own.
    module RunLocate
      module_function

      def call(request, edge_paths:)
        model = request.model
        edge_paths = edge_paths.uniq
        containers = edge_paths.map { |path| path[0...-1] }.uniq
        if containers.length > 1
          raise CodedError.new("params.invalid", "Locate one run at a time: these Edges sit in different groups.")
        end

        index = Zones::ChildLookup.new
        chains = edge_paths.map { |path| along(model, path, index) }
        if chains.any? { |chain| chain.any? { |entity| OccurrencePath.hidden?(entity) } }
          raise CodedError.new(Codes::HIDDEN, "A pipe of the run, or a Group holding it, is hidden or on a hidden " \
                                              "tag; show it and locate again. Nothing moved.")
        end

        ContextCommands.move(request.with(:params => {}), containers.first)
        edges = chains.map(&:last)
        model.selection.clear
        model.selection.add(edges)
        frame(model, chains)
        { "path" => EditContext.current_ids(model), "selected" => edges.length }
      end

      # The entities a root-to-Edge path names, root first, ending at a pipe: an Edge carrying a pipe record directly
      # in a Piping group. One lookup serves every path of the call.
      def along(model, path, index)
        chain = Group::Target.along!(model, path, index)
        edge = chain.last
        return chain if edge.is_a?(Sketchup::Edge) && Assignment::STORE.marks?(edge) && Group.piping_group?(chain[-2])

        raise CodedError.new("target.wrong_kind", "The path does not end at a pipe in a Piping group.")
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
      private_class_method :along, :frame
    end
  end
end
