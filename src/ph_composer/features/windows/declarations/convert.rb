# frozen_string_literal: true

require_relative "../units/convert_review"
require_relative "../units/convert"
require_relative "../units/candidates"
require_relative "convert_route"

module PhComposer
  module Windows
    # Convert to Window Type's public surface: the review of a selection of drawn rectangles.
    module ConvertRegistration
      PATH = { "type" => "array", "minItems" => 1, "items" => { "type" => "integer", "minimum" => 1 } }.freeze
      METRES = { "type" => "number", "x-unit" => "m" }.freeze
      SPAN = Types::SPAN
      EXAMPLE_SOURCE = { "path" => [1201, 1204], "digest" => "sha256:0a1b" }.freeze

      module_function

      def install(feature, registry)
        face = DeepCopy.call(registry.record_descriptor("ph_composer.zones.faces.face").occurrence_schema)
        review_result = Shapes.object({ "groups" => Shapes.list(group_shape(face)),
                                        "left_out" => Shapes.list(left_out_shape) })
        feature.query("#{FEATURE_ID}.units.convert_review",
                      :description => "Which drawn rectangles Convert to Window Type would take, grouped by shared " \
                                      "Edges into Window Type layouts, and why it leaves each other Face out. Writes " \
                                      "nothing. Sizes are the frame outer size.",
                      :refuses => Refuses::CONVERT_REVIEW,
                      :params => Shapes.object({ "paths" => paths_param }),
                      :result => review_result,
                      :examples => [{ "paths" => [[1201, 1204]] }]) do |request|
          Units::ConvertReview.read(request, request.params.fetch("paths"))
        end
        feature.action("#{FEATURE_ID}.units.convert",
                       :description => "Replace reviewed drawn rectangles with placed Windows, one per group: a new " \
                                       "Window Type sized from the geometry or a Type of that size. Sizes are the " \
                                       "frame outer size.",
                       :refuses => Refuses::CONVERT,
                       :params => Shapes.object({ "groups" => groups_param }),
                       :result => Shapes.object({ "units" => Shapes.list(Shapes.object({ "unit_id" => Shapes::TEXT,
                                                                                         "type_id" => Shapes::TEXT })),
                                                  "created_type_ids" => Shapes.list(Shapes::TEXT) }),
                       :undo_name => "Convert to Window Type",
                       :side_effects => Shapes.side_effects(
                         "Erases the rectangles and the Edges only they use, healing the host Face, writes the new " \
                         "Window Types, and places one Unit per group, in one Undo step."
                       ),
                       :examples => [{ "groups" => [{ "sources" => [EXAMPLE_SOURCE] }] }]) do |request, proposal|
          Units::Convert.run(request, proposal, :groups => request.params.fetch("groups"))
        end
        ConvertRouteRegistration.install(feature, review_result, paths_param)
        install_candidates(feature)
      end

      def install_candidates(feature)
        point = { "type" => "array", "items" => METRES, "minItems" => 3, "maxItems" => 3 }
        row = Shapes.object({
          "path" => PATH,
          "outline_m" => Shapes.list(point, :description => "The rectangle's four corners in world metres."),
          "hidden" => { "type" => "boolean", "description" => "Hidden itself, or on a hidden tag or tag folder." },
          "refusal" => Shapes.object({ "code" => Shapes::TEXT, "message" => Shapes::TEXT })
                             .merge("type" => %w[object null],
                                    "description" => "What Convert's source read refuses for this Face alone, " \
                                                     "such as locked or shared storage; null when it reads.")
        })
        feature.query(Units::Candidates::CONVERT,
                      :description => "One bounded page of the rectangles loose in one container, the root when " \
                                      "path is absent: Faces with four square corners and no hole, the shapes " \
                                      "Convert to Window Type takes. Pass their paths to units.convert_review, " \
                                      "which groups them and finds each group's host. Needs no selection.",
                      :refuses => %w[geometry.invalid query.cursor_expired query.limit_invalid target.not_found
                                     target.wrong_kind],
                      :params => Shapes.object({ "path" => container_path, "limit" => Pages::LIMIT,
                                                 "cursor" => Pages::CURSOR }, :optional => %w[path limit cursor]),
                      :result => Shapes.object({ "candidates" => Shapes.list(row), "next_cursor" => Pages::NEXT_CURSOR,
                                                 "total" => Pages::TOTAL }),
                      :examples => [{ "path" => [1201] }]) { |request| Units::Candidates.convert(request) }
      end

      def container_path
        { "type" => "array", "items" => { "type" => "integer" },
          "description" => "The root-to-container path, such as a Zone's; [] or absent for the Model root." }
      end

      def groups_param
        digest = Shapes.described(Shapes::TEXT, "The Face's geometry digest from the review.")
        source = Shapes.object({ "path" => PATH, "digest" => digest })
        type_id = Shapes.id("wnt", "A Window Type of this size; a new one when absent.")
        name = Shapes.described(Shapes::TEXT, "The new Type's name. Default: its size in display units, with " \
                                              "\" (2)\" added when taken.")
        copy_from = Shapes.id("wnt", "Copies this Type's first glazed element's glazing, frames and operation " \
                                     "into every element of the new Type, and its installs onto the sides on " \
                                     "the Type's perimeter. Default: blank elements.")
        sources = Shapes.list(source).merge("minItems" => 1, "maxItems" => Pages::MAXIMUM_LIMIT)
        group = Shapes.object({ "sources" => sources, "type_id" => type_id, "name" => name,
                                "copy_from_type_id" => copy_from },
                              :optional => %w[type_id name copy_from_type_id])
        Shapes.list(group).merge("minItems" => 1, "maxItems" => Pages::MAXIMUM_LIMIT,
                                 "description" => "Each group a review listed, with its rectangles and digests.")
      end

      def paths_param
        Shapes.list(PATH).merge("minItems" => 1, "maxItems" => Pages::MAXIMUM_LIMIT,
                                "description" => "Each candidate Face's entity path from the Model root.")
      end

      def group_shape(face)
        bands = Shapes.list(METRES)
        Shapes.object({
          "host" => Shapes.described(face, "The Zone Face the group lies on."),
          "columns_m" => Shapes.described(bands, "Column widths, left to right as seen from outside."),
          "rows_m" => Shapes.described(bands, "Row heights, top down."),
          "layout_index" => { "type" => "integer", "minimum" => 0,
                              "description" => "The index in `groups` of the first group of this size and layout. " \
                                               "Groups with one index share one new Window Type." },
          "matching_types" => Shapes.list(Shapes.object({ "id" => Shapes::TEXT, "name" => Shapes::TEXT }),
                                          :description => "Window Types of this size and layout within 1 mm, " \
                                                          "alphabetical. New Type is always offered besides these."),
          "preselected_type_id" => { "type" => %w[string null],
                                     "description" => "The first matching Type, or null when none matches." },
          "default_name" => Shapes.described(Shapes::TEXT, "The name a new Type of this size takes unless given one."),
          "sources" => Shapes.list(source_shape, :description => "The rectangles, one per Window Type element.")
        })
      end

      def source_shape
        point = { "type" => "array", "items" => METRES, "minItems" => 3, "maxItems" => 3 }
        Shapes.object({
          "path" => PATH, "row_span" => SPAN, "column_span" => SPAN,
          "digest" => Shapes.described(Shapes::TEXT, "The Face's geometry digest as this review read it."),
          "outline_m" => Shapes.list(point, :description => "The rectangle's four corners in world metres.")
        })
      end

      def left_out_shape
        Shapes.object({ "paths" => Shapes.list(PATH, :description => "The Faces this row leaves out; a group " \
                                                                     "that cannot convert is one row."),
                        "code" => Shapes.described(Shapes::TEXT, "Why, as a published code."),
                        "message" => Shapes::TEXT })
      end
      private_class_method :groups_param, :paths_param, :container_path, :install_candidates, :group_shape,
                           :source_shape, :left_out_shape
    end
  end
end
