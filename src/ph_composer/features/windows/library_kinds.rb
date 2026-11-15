# frozen_string_literal: true

require_relative "library_assignment"
require_relative "library_imports"

module PhComposer
  module Windows
    # The three product kinds use their authored SI fields only. Provider transport, metadata and
    # attribution are excluded from semantic mapping; the shared coordinator owns copy provenance.
    module LibraryKinds
      module_function

      def install(feature)
        Products::KINDS.each_key do |collection|
          adapter = ProductAdapter.new(collection)
          feature.library_kind("#{FEATURE_ID}.library_#{collection}",
                               :contract_version => 1,
                               :record_kind => adapter.kind.id, :adapter => adapter.declaration)
        end
      end

      class ProductAdapter
        attr_reader :kind, :fields

        def initialize(collection)
          @collection = collection
          @kind = Products::KINDS.fetch(collection)
          @fields = kind.values_schema.fetch("properties").keys - ["source"]
          @numbers = Products.number_keys(collection)
        end

        def map(row)
          values = Products.defaults(@collection, DeepCopy.call(row.slice(*fields))).slice(*fields)
          @numbers.each { |key| values[key] = values[key].nil? ? nil : values[key].to_f }
          values["color"] = values.fetch("color").downcase if values.key?("color")
          unless Fields.problems(values).empty? && JsonSchema.validate(values, schema).empty?
            raise CodedError.new("library.row_semantic_invalid",
                                 "The library row violates the Window product contract.")
          end
          values
        end

        def reverse(record)
          map(record).merge("id" => record.fetch("id"))
        end

        def fingerprint(values)
          normalized = map(values)
          CanonicalJson.digest(fields.map { |key| [key, normalized.fetch(key)] })
        end

        def schema
          kind.values_schema.tap do |shape|
            shape["properties"] = shape.fetch("properties").slice(*fields)
            shape["required"] = fields
          end
        end

        def wire_schema
          schema.tap do |shape|
            shape.fetch("properties")["id"] = { "type" => "string", "minLength" => 1 }
            shape["required"] = %w[id name]
          end
        end

        def callback(params, result, refuses:, &handler)
          Declarations::LibraryCallback.new(:params => params, :result => result, :refuses => refuses,
                                            :handler => handler)
        end

        def local_read
          expected = kind.descriptor.patch_schema
          expected["properties"] = expected.fetch("properties").slice(*fields)
          row = Shapes.object({ "id" => Shapes::TEXT, "mapped" => schema, "expected_values" => expected,
                                "source" => kind.values_schema.fetch("properties").fetch("source") },
                              :optional => ["source"])
          callback(Shapes::NONE, Shapes.list(row),
                   :refuses => %w[record.unreadable library.row_semantic_invalid]) do |request, _proposal|
            Definitions.records(request, kind).map do |record|
              projection = { "id" => record.fetch("id"), "mapped" => map(record),
                             "expected_values" => DeepCopy.call(record.slice(*fields)) }
              projection["source"] = DeepCopy.call(record["source"]) if record.key?("source")
              projection
            end
          end
        end

        def replace
          params = Shapes.update(kind)
          params.fetch("properties").fetch("values").fetch("properties")["source"] =
            kind.values_schema.fetch("properties").fetch("source")
          callback(params, Shapes::RESULT, :refuses => Refuses::EDIT) do |request, proposal|
            Authoring.update_product(request, proposal, @collection,
                                     :id => request.params.fetch("id"),
                                     :values => request.params.fetch("values"),
                                     :expected_values => request.params.fetch("expected_values"))
          end
        end

        def declaration
          Declarations::LibraryAdapter.new(
            :wire_kind => @collection, :wire_version => 1, :fingerprint_version => 1, :wire_schema => wire_schema,
            :mapped_schema => schema, :fingerprint_fields => fields, :map => method(:map), :reverse => method(:reverse),
            :fingerprint => method(:fingerprint), :display_label => ->(mapped) { mapped.fetch("name") },
            :local_read => local_read,
            :create => callback(Shapes.create(kind), Shapes::RESULT, :refuses => Refuses::WRITE) do |request, proposal|
              Authoring.create_product(request, proposal, @collection, :values => request.params.fetch("values"),
                                                                       :user_data => request.params["user_data"])
            end,
            :replace => replace, :assign => LibraryAssignment.callback(@collection)
          )
        end
      end
    end
  end
end
