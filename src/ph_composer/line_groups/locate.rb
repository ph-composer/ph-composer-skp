# frozen_string_literal: true

module PhComposer
  module LineGroups
    # Select a run's Edges, by the paths its schedule read, and frame them. Their line group opens through the
    # foundation's ph_composer.context.open (context/AGENT_INTERFACE.md, "Model context"), so its refusals apply.
    module Locate
      module_function

      def call(spec, request, edge_paths:)
        model = request.model
        edge_paths = edge_paths.uniq
        containers = edge_paths.map { |path| path[0...-1] }.uniq
        if containers.length > 1
          raise CodedError.new("params.invalid", "Locate one run at a time: these Edges sit in different groups.")
        end

        index = spec.child_lookup.call
        chains = edge_paths.map { |path| along(spec, model, path, index) }
        if chains.any? { |chain| chain.any? { |entity| OccurrencePath.hidden?(entity) } }
          raise CodedError.new(spec.code(:hidden), "A #{spec.edge_noun} of the run, or a Group holding it, is hidden " \
                                                   "or on a hidden tag; show it and locate again. Nothing moved.")
        end

        ContextCommands.move(request.with(:params => {}), containers.first)
        edges = chains.map(&:last)
        model.selection.clear
        model.selection.add(edges)
        frame(model, chains)
        { "path" => EditContext.current_ids(model), "selected" => edges.length }
      end

      # The entities a root-to-Edge path names, root first, ending at an assigned Edge directly in a line group. One
      # lookup serves every path of the call.
      def along(spec, model, path, index)
        chain = GroupTarget.along!(model, path, index)
        return chain if spec.edge?(chain.last) && spec.group?(chain[-2])

        raise CodedError.new("target.wrong_kind",
                             "The path does not end at a #{spec.edge_noun} in a #{spec.label}.")
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
