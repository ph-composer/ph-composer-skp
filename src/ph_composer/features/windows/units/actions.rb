# frozen_string_literal: true

require_relative "identity_step"
require_relative "place_step"
require_relative "read_context"

module PhComposer
  module Windows
    module Units
      module Actions
        module_function

        # `offsets` place the anchor on the host Face, in metres along its plane axes.
        def place(request, proposal, host:, type_id:, offsets:, anchor:, user_data: {})
          identity = Records::Identity.allocator(request, "host" => host, "type_id" => type_id,
                                                          "offsets" => offsets, "anchor" => anchor)
          Mutation.prepare(request, proposal, :identity => identity)
          reads = ReadContext.new(request)
          host = reads.host_reference(host)
          type = request.engine.find(TYPE_KIND, type_id)
          point = Placement::Offsets.point(host.geometry, :x_m => offsets.fetch("x_m"), :y_m => offsets.fetch("y_m"))
          record = { "id" => identity.call("wun"), "schema_version" => 1,
                     "window_type_id" => type.fetch("id"), "anchor" => anchor,
                     "user_data" => DeepCopy.call(user_data), "extension_data" => {} }
          step = PlaceStep.new(:model => request.model, :host => host, :type => type, :record => record,
                               :point_m => point, :existing_polygons_m => reads.other_polygons)
          proposal.add_step(step, :scopes => [MutationScope.new(:definition_ids => step.definition_ids),
                                              PhComposer::Operations::EntityScope.new(host.parent_path)])
          { "unit_id" => record.fetch("id") }
        end

        def list(request, paged: true)
          reads = ReadContext.new(request)
          id_counts = reads.occurrences.group_by { |item| item.record.fetch("id") }.transform_values(&:length)
          polygons = reads.occurrences.filter_map do |item|
            polygon = reads.read_polygon(item)
            [item.path, polygon] if polygon
          end.to_h
          items = reads.occurrences.sort_by(&:path)
          if request.params.key?("ids")
            items = items.select { |item| request.params.fetch("ids").include?(item.record.fetch("id")) }
          end
          total = items.length
          items, cursor = Pages.slice(request, "#{FEATURE_ID}.units.list", items, :key => :path.to_proc) if paged
          rows = items.map { |item| unit_row(request, reads, item, polygons, id_counts) }
          result = { "units" => rows }
          result.merge!("next_cursor" => cursor, "total" => total) if paged
          result
        end

        # One Unit occurrence as the list shows it, with the findings its Type, host and neighbours raise.
        def unit_row(request, reads, item, polygons, id_counts)
          host = reads.host(item, :writable => false)
          canonical = primary(request.model, item.record.fetch("window_type_id"))
          others = polygons.reject { |path, _polygon| path == item.path }.values
          findings = State.findings(item, :type => reads.type(item), :canonical_definition => canonical,
                                          :host_geometry => host&.geometry, :existing_polygons_m => others,
                                          :host_values => host ? host.values : {},
                                          :host_state => host ? host.zone_state : nil,
                                          :shared_id => id_counts.fetch(item.record.fetch("id")) > 1)
          { "reference" => item.reference, "id" => item.record.fetch("id"), "schema_version" => 1,
            "name" => item.entity.name, "values" => RECORD_KIND.values(item.record),
            "user_data" => item.record.fetch("user_data", {}),
            "extension_data" => item.record.fetch("extension_data", {}),
            "extension_status" => Records::Metadata.status_map(item.record, request.registry.catalog),
            "host" => host&.reference,
            "findings" => findings }
        end

        def primary(model, type_id)
          DefinitionIndex.resolve(model, type_id)
        rescue CodedError => error
          raise unless error.code == "window.definition_missing"

          nil
        end

        private_class_method :primary, :unit_row
      end
    end
  end
end
