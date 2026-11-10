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

        LIST = "#{FEATURE_ID}.units.list"
        DETAIL = "#{FEATURE_ID}.units.detail"
        # The parts of a Unit's row units.detail reaches; reference, id and schema_version are in every row.
        DETAIL_PARTS = %w[name values user_data extension_data extension_status host findings].freeze

        # Paged: one page cut by size (Pages.bounded) whose rows are built only for that page, projected by
        # `fields` and, with `metadata` "summary", without the metadata maps (RecordQueries.summarize) and
        # with the native name cut as every name in a bounded row is.
        def list(request, paged: true)
          params = request.params
          check_fields!(params["fields"])
          reads = ReadContext.new(request)
          id_counts = reads.occurrences.group_by { |item| item.record.fetch("id") }.transform_values(&:length)
          polygons = polygons(reads)
          items = reads.occurrences.sort_by(&:path)
          items = items.select { |item| params.fetch("ids").include?(item.record.fetch("id")) } if params.key?("ids")
          build = ->(item) { unit_row(request, reads, item, polygons, id_counts) }
          return { "units" => items.map(&build) } unless paged

          summary = params["metadata"] == "summary"
          prepare = ->(page) { page.map { |item| project(build.call(item), params["fields"], summary) } }
          rows, cursor = Pages.bounded(request, LIST, items, :key => :path.to_proc, :prepare => prepare)
          { "units" => rows, "next_cursor" => cursor, "total" => items.length }
        end

        # One part of one Unit's row, exactly, in fragments (shell/fragments.rb). The reference resolves as
        # every Unit action resolves it, so a moved, copied or re-identified Unit refuses rather than
        # answering another occurrence's data.
        def detail(request)
          reference = request.params.fetch("unit")
          item = Occurrences.resolve(request.model, reference)
          reads = ReadContext.new(request)
          id_counts = reads.occurrences.count { |other| other.record.fetch("id") == item.record.fetch("id") }
          row = unit_row(request, reads, item, polygons(reads), item.record.fetch("id") => id_counts)
          { "unit_id" => reference.fetch("unit_id") }
            .merge(Fragments.detail(request, DETAIL, row, request.params.fetch("path"), :parts => DETAIL_PARTS))
        end

        def check_fields!(fields)
          unknown = Array(fields) - RECORD_KIND.fields.map(&:key)
          raise CodedError.new("params.invalid", "A Window unit has no field #{unknown.first}.") unless unknown.empty?
        end

        def polygons(reads)
          reads.occurrences.filter_map do |item|
            polygon = reads.read_polygon(item)
            [item.path, polygon] if polygon
          end.to_h
        end

        def project(row, fields, summary)
          values = row.fetch("values")
          row["values"] = values.slice(*fields) if fields
          return row unless summary

          RecordQueries.summarize(row, values).merge(OccurrencePath.bounded_names(row.slice("name")))
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

        private_class_method :primary, :unit_row, :check_fields!, :polygons, :project
      end
    end
  end
end
