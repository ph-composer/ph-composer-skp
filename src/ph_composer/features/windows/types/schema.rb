# frozen_string_literal: true

module PhComposer
  module Windows
    # Inclusive bands describe one rectangular, fully covered layout; dimensions may be missing in
    # an incomplete saved type. Geometry and placement depend on these definitions, never vice versa.
    # Elements are the kind's part (Records::Part): each may carry its own `user_data`, which a kind change,
    # flip, installs save, Duplicate and the flipped Type keep, split copies into every piece and merge keeps
    # only on the top-left survivor (GridOperations.merge); a new element starts without a map.
    module Types
      # Edge order everywhere a Type lists its sides: top and bottom at even indexes, right and left at odd.
      SIDES = %w[top right bottom left].freeze
      # A new Type's width and height when the caller supplies none. A client that wants another start,
      # such as the panel's round imperial size, passes `columns_m` and `rows_m`.
      DEFAULT_SIZE_M = [1.0, 1.5].freeze
      ID = { "type" => %w[string null] }.freeze
      SPAN = { "type" => "array", "minItems" => 2, "maxItems" => 2,
               "items" => { "type" => "integer", "minimum" => 0 } }.freeze
      SIDE_SCHEMA = SchemaShapes.object(SIDES.to_h { |side| [side, ID] }).freeze
      DIRECTIONS = { "type" => "array", "items" => { "type" => "string", "enum" => %w[left right up down] } }.freeze
      OPERATION = SchemaShapes.object({ "type" => { "type" => "string", "enum" => %w[fixed swing slide] },
                                        "directions" => DIRECTIONS })
                              .merge("type" => %w[object null]).freeze
      ELEMENT = SchemaShapes.object({
        "id" => { "type" => "string" }, "name" => { "type" => "string" },
        "kind" => { "type" => "string", "enum" => %w[glazed empty] },
        "row_span" => SPAN, "column_span" => SPAN, "glazing_id" => ID,
        "frames" => SIDE_SCHEMA, "installs" => SIDE_SCHEMA, "operation" => OPERATION,
        "user_data" => SchemaShapes::PART_USER_DATA
      }, :optional => ["user_data"]).freeze
      BANDS = { "type" => "array", "minItems" => 1, "maxItems" => 40,
                "items" => { "type" => %w[number null], "exclusiveMinimum" => 0, "x-unit" => "m" } }.freeze

      module_function

      def blank(row = 0, column = 0, identity: ->(prefix) { Records::Identity.mint(prefix) })
        { "id" => identity.call("wel"), "name" => "Element", "kind" => "glazed",
          "row_span" => [row, row], "column_span" => [column, column], "glazing_id" => nil,
          "frames" => SIDES.to_h { |side| [side, nil] }, "installs" => SIDES.to_h { |side| [side, nil] },
          "operation" => nil }
      end

      def defaults(values, identity: ->(prefix) { Records::Identity.mint(prefix) })
        width, height = DEFAULT_SIZE_M
        { "rows_m" => [height], "columns_m" => [width], "elements" => [blank(:identity => identity)],
          "product_photos" => [] }.merge(Fields.defaults(values))
      end

      # Whether the elements tile the grid exactly once, with valid ids, spans and operations. The kind
      # refuses repeated element ids, as it does for every part.
      def layout_problems(values)
        found = []
        coverage = {}
        values.fetch("elements").each do |element|
          found << "Element id is invalid." unless Records::Identity.pattern("wel").match?(element.fetch("id"))
          spans = %w[row_span column_span].map.with_index do |key, axis|
            span = element.fetch(key)
            count = values.fetch(axis.zero? ? "rows_m" : "columns_m").length
            unless span.first <= span.last && span.last < count
              found << "Element spans must stay inside the grid."
              next nil
            end
            span
          end
          found.concat(cover(coverage, *spans)) if spans.none?(&:nil?)
          found.concat(element_problems(element))
        end
        if coverage.length != values.fetch("rows_m").length * values.fetch("columns_m").length
          found << "Every grid cell must be covered."
        end
        found.uniq
      end

      # Marks every grid cell inside the spans as covered; a cell already covered is an overlap.
      def cover(coverage, row_span, column_span)
        overlaps = []
        (row_span.first..row_span.last).each do |row|
          (column_span.first..column_span.last).each do |column|
            overlaps << "Elements overlap." if coverage[[row, column]]
            coverage[[row, column]] = true
          end
        end
        overlaps
      end

      def element_problems(element)
        found = []
        operation = element["operation"]
        if operation && operation.fetch("directions").uniq != operation.fetch("directions")
          found << "Operation directions must be unique."
        end
        if operation && operation.fetch("type") == "fixed" && !operation.fetch("directions").empty?
          found << "Fixed elements carry no operation directions."
        end
        if element.fetch("kind") == "empty" && (operation || carries_products?(element))
          found << "Empty elements cannot carry products or operation."
        end
        found
      end

      def carries_products?(element)
        element["glazing_id"] || (element.fetch("frames").values + element.fetch("installs").values).any?
      end

      FIELDS = Fields.with_source_snapshot(Fields.common + [
        Fields.field("rows_m", BANDS, :required => true), Fields.field("columns_m", BANDS, :required => true),
        Fields.field("elements", { "type" => "array", "minItems" => 1, "items" => ELEMENT }, :required => true),
        Fields.field("install_depth_m", { "type" => "number", "minimum" => 0, "x-unit" => "m" }),
        Fields.field("product_photos", { "type" => "array", "items" => { "type" => "string" } })
      ])
      SNAPSHOT_SCHEMA = Fields.source_snapshot_schema(FIELDS)
      REFERENCES = [Records::Reference.new(:key => "elements[].glazing_id", :target_kind => GLAZING_KIND,
                                           :cardinality => "one")] +
                   { "frames" => FRAME_KIND, "installs" => PSI_INSTALL_KIND }.flat_map do |field, target|
                     SIDES.map do |side|
                       Records::Reference.new(:key => "elements[].#{field}.#{side}", :target_kind => target,
                                              :cardinality => "one")
                     end
                   end

      def record_problems(values)
        Fields.problems(values) + Fields.source_problems(values["source"], SNAPSHOT_SCHEMA) + layout_problems(values)
      end

      PARTS = [Records::Part.new(:label => "Element", :path => "elements[]")].freeze

      KIND = Records::RecordKind.new(:id => TYPE_KIND, :label => "Window Type", :schema_version => 1,
                                     :id_prefix => "wnt", :fields => FIELDS, :references => REFERENCES,
                                     :parts => PARTS, :validate => method(:record_problems))

      def references(record)
        KIND.references.flat_map { |reference| reference.ids(record).map { |id| [reference.target_kind, id] } }.uniq
      end
    end
  end
end
