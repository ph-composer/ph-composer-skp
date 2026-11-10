# frozen_string_literal: true

module PhComposer
  module Assemblies
    # The Material wire contract contains semantic authored values only. Mapping admits this
    # allowlist, never source, identity or arbitrary metadata. The coordinator owns attribution and
    # copies only these wire fields (apart from wire id) into its sanitized source snapshot.
    module MaterialsLibrary
      NAME = "#{FEATURE_ID}.library_materials"
      FIELDS = Commands::MATERIAL_EDITABLE
      NUMBERS = %w[conductivity_w_mk density_kg_m3 specific_heat_j_kgk emissivity].freeze

      module_function

      def map(row)
        values = Materials::Schema.defaults(row.slice(*FIELDS)).slice(*FIELDS)
        category = values.fetch("category")
        values["category"] = Materials::Schema::CATEGORIES.key?(category) ? category : ""
        values["color"] = values.fetch("color").downcase
        NUMBERS.each { |key| values[key] = values[key].nil? ? nil : values[key].to_f }
        unless Fields.problems(values).empty?
          raise CodedError.new("library.row_semantic_invalid", "The library row violates the Material value contract.")
        end

        values
      end

      def reverse(record)
        map(record).merge("id" => record.fetch("id"))
      end

      def fingerprint(values)
        normalized = map(values)
        CanonicalJson.digest(FIELDS.map { |field| [field, normalized.fetch(field)] })
      end

      def schema
        Materials::Schema::KIND.values_schema.tap do |shape|
          shape["properties"] = shape.fetch("properties").slice(*FIELDS)
          shape["required"] = FIELDS
        end
      end

      def wire_schema
        shape = schema
        shape["properties"]["category"] = { "type" => "string" }
        shape["properties"]["id"] = { "type" => "string", "minLength" => 1 }
        shape["required"] = %w[id name]
        shape
      end

      def callback(params, result, refuses:, examples: nil, &handler)
        Declarations::LibraryCallback.new(:params => params, :result => result, :refuses => refuses,
                                          :handler => handler, :examples => examples)
      end

      def local_read
        expected = Materials::Schema::KIND.descriptor.patch_schema
        expected["properties"] = expected.fetch("properties").slice(*FIELDS)
        row = Shapes.object({ "id" => Shapes::TEXT, "mapped" => schema, "expected_values" => expected,
                              "source" => Materials::Schema::KIND.values_schema.fetch("properties").fetch("source") },
                            :optional => ["source"])
        callback(Shapes::NONE, Shapes.list(row),
                 :refuses => %w[record.unreadable library.row_semantic_invalid]) do |request, _proposal|
          Definitions.records(request, MATERIAL_KIND).map do |record|
            projection = { "id" => record.fetch("id"), "mapped" => map(record),
                           "expected_values" => DeepCopy.call(record.slice(*FIELDS)) }
            projection["source"] = DeepCopy.call(record["source"]) if record.key?("source")
            projection
          end
        end
      end

      # The ordinary Material create.
      def create
        params = Shapes.create(Materials::Schema::KIND, :labelled => Materials::Schema::LABELLED_FIELDS)
        callback(params, Shapes::RESULT, :refuses => Refuses::CREATE) do |request, proposal|
          Materials::Operations.create(request, proposal, :values => request.params.fetch("values"),
                                                          :user_data => request.params["user_data"])
        end
      end

      def replace
        params = Shapes.update(Materials::Schema::KIND, FIELDS, :labelled => Materials::Schema::LABELLED_FIELDS)
        params.fetch("properties").delete("user_data")
        params.fetch("properties").fetch("values").fetch("properties")["source"] =
          Materials::Schema::KIND.values_schema.fetch("properties").fetch("source")
        # The ordinary Material update, with the copy's provenance passed apart from the edited values.
        callback(params, Shapes::RESULT, :refuses => Refuses::EDIT) do |request, proposal|
          values = request.params.fetch("values")
          Materials::Operations.update(request, proposal, :id => request.params.fetch("id"),
                                                          :values => values.reject { |key, _value| key == "source" },
                                                          :expected_values => request.params.fetch("expected_values"),
                                                          :source => values["source"])
        end
      end

      def install(feature)
        adapter = Declarations::LibraryAdapter.new(
          :wire_kind => "materials", :wire_version => 1, :fingerprint_version => 1, :wire_schema => wire_schema,
          :mapped_schema => schema, :fingerprint_fields => FIELDS, :map => method(:map), :reverse => method(:reverse),
          :fingerprint => method(:fingerprint), :display_label => ->(mapped) { mapped.fetch("name") },
          :local_read => local_read, :create => create, :replace => replace, :assign => assign
        )
        feature.library_kind(NAME, :contract_version => 1, :record_kind => MATERIAL_KIND, :adapter => adapter)
      end

      # The coordinator names only a local identity and an opaque assignment target. Translating
      # that identity into the set_material gesture stays with the owner of the assignment, which
      # calls the same operation its action does.
      def assign
        target = SegmentRegistration.params(SegmentRegistration.material_properties.reject do |key, _schema|
          key == "material_id"
        end)
        params = Shapes.object({ "target" => target, "local_id" => Shapes::TEXT })
        example = { "target" => { "id" => Shapes::EXAMPLE_ID, "expected_values" => {},
                                  "layer_id" => Shapes::EXAMPLE_LAYER, "segment_id" => Shapes::EXAMPLE_SEGMENT },
                    "local_id" => "mat_Ab12Cd34Ef56" }
        callback(params, Shapes::RESULT, :refuses => Refuses::EDIT, :examples => [example]) do |request, proposal|
          gesture = request.params.fetch("target").merge("material_id" => request.params.fetch("local_id"))
          Assembly::Operations.gesture(request, proposal,
                                       :id => gesture.fetch("id"),
                                       :expected_values => gesture.fetch("expected_values")) do |record|
            SegmentRegistration.set_material(record, gesture, request)
          end
        end
      end
    end
  end
end
