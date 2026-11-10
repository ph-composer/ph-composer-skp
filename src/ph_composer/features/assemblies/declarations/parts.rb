# frozen_string_literal: true

require_relative "../refuses"

module PhComposer
  module Assemblies
    # Bounded reads of one record's parts, for a record larger than one reply: an Assembly's Layers and
    # Layer-Segments, and the Assemblies that use a Material. Rows come from the stored record and the
    # owner's own rules (Materials::Schema.membrane_layer?, Thermal.segment_flags, Snapshot.material_uses),
    # never recomputed by a client. Each pages by position (shell/pages.rb) bound to the revision.
    module PartRegistration
      LAYER = Shapes.object({
        "id" => Shapes::TEXT, "index" => { "type" => "integer", "minimum" => 0 },
        "thickness_mm" => { "type" => "number", "x-unit" => "mm" },
        "membrane" => Shapes.described({ "type" => "boolean" },
                                       "Every Layer-Segment's Material is a membrane, so it adds no thickness."),
        "air_barrier" => { "type" => %w[string null],
                           "description" => "The face carrying the air barrier, or null when this Layer does not." },
        "segment_count" => { "type" => "integer", "minimum" => 1 }
      })
      SEGMENT = Shapes.object({
        "layer_id" => Shapes::TEXT, "layer_index" => { "type" => "integer", "minimum" => 0 },
        "index" => { "type" => "integer", "minimum" => 0 },
        "segment" => Shapes.described(Assembly::Schema::SEGMENT, "The Layer-Segment as stored."),
        "material_name" => { "type" => %w[string null],
                             "description" => "Null when none is assigned or found; cut to " \
                                              "#{OccurrencePath::NAME_CHARACTERS} characters, named in truncated." },
        "flags" => Shapes.described(Shapes.list(Shapes::TEXT), "What keeps this Layer-Segment from calculating, " \
                                                               "by code; empty when nothing does."),
        "truncated" => ContextChildren::TRUNCATED
      }, :optional => ["truncated"])
      USE = Shapes.object({ "assembly_id" => Shapes::TEXT, "name" => Shapes::TEXT,
                            "truncated" => ContextChildren::TRUNCATED }, :optional => ["truncated"])
      PAGE = { "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL }.freeze
      ASSEMBLY_ID = Shapes.id("asm", "The Assembly to read.")
      REFUSES = (Refuses::PAGE + %w[record.unreadable target.not_found]).freeze

      module_function

      def install(feature)
        prefix = "#{FEATURE_ID}.assemblies"
        query(feature, "#{prefix}.layers.list", "One bounded page of an Assembly's Layers, outside first as stored.",
              { "assembly_id" => ASSEMBLY_ID }, { "assembly_id" => Shapes::TEXT, "layers" => Shapes.list(LAYER) },
              { "assembly_id" => Shapes::EXAMPLE_ID }) { |request| layers(request) }
        query(feature, "#{prefix}.segments.list",
              "One bounded page of an Assembly's Layer-Segments, by Layer and position, or one Layer's.",
              { "assembly_id" => ASSEMBLY_ID, "layer_id" => Shapes.id("lyr", "Only this Layer's.") },
              { "assembly_id" => Shapes::TEXT, "segments" => Shapes.list(SEGMENT) },
              { "assembly_id" => Shapes::EXAMPLE_ID }, :optional => ["layer_id"]) { |request| segments(request) }
        query(feature, "#{FEATURE_ID}.materials.uses.list",
              "One bounded page of the Assemblies that use a Material, by Assembly id: a Material row's uses.",
              { "material_id" => Shapes.id("mat", "The Material to read.") },
              { "material_id" => Shapes::TEXT, "uses" => Shapes.list(USE),
                "unreadable" => { "type" => "integer", "minimum" => 0,
                                  "description" => "Assemblies that cannot be read, so whether they use it is " \
                                                   "unknown." } },
              { "material_id" => "mat_Ab12Cd34Ef56" }) { |request| material_uses(request) }
      end

      def query(feature, name, description, properties, result, example, optional: [], &read)
        feature.query(name, :description => description, :refuses => REFUSES,
                            :params => Shapes.object(properties.merge("limit" => Pages::LIMIT,
                                                                      "cursor" => Pages::CURSOR),
                                                     :optional => optional + Pages::PAGE_KEYS),
                            :result => Shapes.object(result.merge(PAGE)),
                            :examples => [example, example.merge("limit" => 20)], &read)
      end

      def layers(request)
        id = request.params.fetch("assembly_id")
        record = request.engine.find(ASSEMBLY_KIND, id)
        materials = materials_by_id(request.engine)
        barrier = record["air_barrier"]
        rows = record.fetch("layers").each_with_index.map do |layer, index|
          { "id" => layer.fetch("id"), "index" => index, "thickness_mm" => layer.fetch("thickness_mm"),
            "membrane" => Materials::Schema.membrane_layer?(layer, materials),
            "air_barrier" => barrier && barrier.fetch("layer_id") == layer.fetch("id") ? barrier.fetch("face") : nil,
            "segment_count" => layer.fetch("segments").length }
        end
        result = page(request, "#{FEATURE_ID}.assemblies.layers.list", rows, ->(row) { [row.fetch("index")] })
        { "assembly_id" => id, "layers" => result.fetch("rows") }.merge(result.slice("next_cursor", "total"))
      end

      def segments(request)
        id = request.params.fetch("assembly_id")
        record = request.engine.find(ASSEMBLY_KIND, id)
        layers = record.fetch("layers").each_with_index.to_a
        if (layer_id = request.params["layer_id"])
          layers = layers.select { |layer, _index| layer.fetch("id") == layer_id }
          raise CodedError.new("target.not_found", "Assembly #{id} has no Layer #{layer_id}.") if layers.empty?
        end
        materials = materials_by_id(request.engine)
        rows = layers.flat_map do |layer, layer_index|
          layer.fetch("segments").each_with_index.map do |segment, index|
            material = materials[segment["material_id"]]
            { "layer_id" => layer.fetch("id"), "layer_index" => layer_index, "index" => index,
              "segment" => segment, "flags" => Thermal.segment_flags(segment, materials) }
              .merge(OccurrencePath.bounded_names("material_name" => material && material["name"]))
          end
        end
        result = page(request, "#{FEATURE_ID}.assemblies.segments.list", rows,
                      ->(row) { [row.fetch("layer_index"), row.fetch("index")] })
        { "assembly_id" => id, "segments" => result.fetch("rows") }.merge(result.slice("next_cursor", "total"))
      end

      def material_uses(request)
        id = request.params.fetch("material_id")
        record = request.engine.find(MATERIAL_KIND, id)
        assemblies, unreadable = DefinitionLists.read(request.engine, ASSEMBLY_KIND,
                                                      request.engine.ids(ASSEMBLY_KIND).sort)
        rows = Snapshot.material_uses(record, assemblies).map do |use|
          use.merge(OccurrencePath.bounded_names(use.slice("name")))
        end
        result = page(request, "#{FEATURE_ID}.materials.uses.list", rows, ->(row) { [row.fetch("assembly_id")] })
        { "material_id" => id, "uses" => result.fetch("rows"), "unreadable" => unreadable.length }
          .merge(result.slice("next_cursor", "total"))
      end

      def page(request, query, rows, key)
        page, next_cursor = Pages.bounded(request, query, rows, :key => key)
        { "rows" => page, "next_cursor" => next_cursor, "total" => rows.length }
      end

      def materials_by_id(engine)
        DefinitionLists.read(engine, MATERIAL_KIND, engine.ids(MATERIAL_KIND)).first.to_h do |record|
          [record.fetch("id"), record]
        end
      end
    end
  end
end
