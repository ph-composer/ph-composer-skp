# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      module AssemblyRegistration
        TARGET = Shapes.object({ "reference" => FACE_REFERENCE, "expected_values" => FACE_VALUES }).freeze
        PARAMS = Shapes.object({
          "targets" => Shapes.list(TARGET).merge("minItems" => 1, "description" => "Each Face occurrence to " \
                                                                                   "change, with the values last " \
                                                                                   "read; a change refuses."),
          "assembly_id" => { "type" => %w[string null], "description" => "The Assembly to assign, or null to clear " \
                                                                         "it." }
        }).freeze
        USAGE_ROW = Shapes.object({ "assembly_id" => Shapes::ID, "face_count" => Shapes::COUNT,
                                    "gross_area_m2" => { "type" => "number", "x-unit" => "m2" },
                                    "faces" => Shapes.list(FACE_REFERENCE) }).freeze
        USAGE = Shapes.list(USAGE_ROW).freeze
        FINDINGS = Shapes.list(Shapes.object({ "code" => Shapes::ID, "message" => Shapes::ID,
                                               "assembly_id" => { "type" => %w[string null] } })).freeze
        CHOICE = Shapes.object({ "id" => Shapes::ID, "name" => Shapes::ID,
                                 "type" => { "type" => %w[string null] }, "color" => Shapes::ID }).freeze
        CHOICES = Shapes.object({ "assemblies" => Shapes.list(CHOICE) }).freeze

        USAGE_LIST = "#{PREFIX}.assembly_usage.list"
        USAGE_FACES = "#{PREFIX}.assembly_usage.faces"
        USAGE_SUMMARY = USAGE_ROW.merge(
          "required" => USAGE_ROW.fetch("required") - ["faces"],
          "properties" => USAGE_ROW.fetch("properties").reject { |key, _value| key == "faces" }
        ).freeze

        module_function

        # assembly_usage a bounded page at a time: the Assemblies' counts and areas, then one Assembly's Faces.
        # Both come from the same Face table assembly_usage reads, so nothing is recalculated by a caller.
        def install_usage_pages(feature)
          page = { "next_cursor" => Pages::NEXT_CURSOR, "total" => Pages::TOTAL }
          paging = { "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR }
          refuses = Refuses::READ + %w[geometry.invalid] + Refuses::PAGE
          feature.query(USAGE_LIST,
                        :description => "One bounded page of assembly_usage's rows by Assembly id, each its Face " \
                                        "count and gross area without the Faces; #{USAGE_FACES} pages those.",
                        :refuses => refuses,
                        :params => Shapes.object(paging, :optional => Pages::PAGE_KEYS),
                        :result => Shapes.object({ "assemblies" => Shapes.list(USAGE_SUMMARY) }.merge(page)),
                        :examples => [{}]) do |request|
            rows = usage(request, USAGE_LIST).map { |row| row.reject { |key, _value| key == "faces" } }
            found, next_cursor = Pages.bounded(request, USAGE_LIST, rows, :key => ->(row) { row.fetch("assembly_id") })
            { "assemblies" => found, "next_cursor" => next_cursor, "total" => rows.length }
          end
          feature.query(USAGE_FACES,
                        :description => "One bounded page of the Face occurrences one Assembly is assigned to, in " \
                                        "assembly_usage's order, beside its Face count and gross area.",
                        :refuses => (refuses + %w[target.not_found]).uniq,
                        :params => Shapes.object({ "assembly_id" => Shapes.described(Shapes::ID, "The Assembly " \
                                                                                                 "to read.") }
                                                   .merge(paging), :optional => Pages::PAGE_KEYS),
                        :result => Shapes.object(USAGE_ROW.fetch("properties").merge(page)),
                        :examples => [{ "assembly_id" => "asm_Ab12Cd34Ef56" }]) { |request| usage_faces(request) }
        end

        def usage_faces(request)
          id = request.params.fetch("assembly_id")
          row = usage(request, USAGE_FACES).find { |usage| usage.fetch("assembly_id") == id }
          unless row || request.engine.ids(AssemblyAssignment::KIND).include?(id)
            raise CodedError.new("target.not_found", "No Assembly #{id} exists or is assigned to a Face.")
          end

          row ||= { "assembly_id" => id, "face_count" => 0, "gross_area_m2" => 0.0, "faces" => [] }
          faces = row.fetch("faces").each_with_index.map { |face, index| [index, face] }
          page, next_cursor = Pages.bounded(request, USAGE_FACES, faces, :key => ->(face) { [face.first] })
          row.merge("faces" => page.map(&:last), "next_cursor" => next_cursor, "total" => faces.length)
        end

        # The whole usage, as assembly_usage answers it; a bad limit or cursor refuses before the walk.
        def usage(request, query)
          Pages.limit(request.params)
          Pages.position(request, query)
          Faces.all(request).fetch("assembly_usage")
        end
        private_class_method :usage_faces, :usage

        def install(feature)
          feature.action("#{PREFIX}.assign_assembly",
                         :description => "Set or clear only the Assembly of explicit Faces.",
                         :refuses => Refuses::FACE_TARGET + %w[gesture.too_large reference.invalid],
                         :params => PARAMS, :result => Registration::FACE_IDS_RESULT,
                         :undo_name => "Assign Assembly", :side_effects => "Changes only assembly_id on all targets.",
                         :examples => [{ "targets" => [{ "reference" => Registration::EXAMPLE_FACE,
                                                         "expected_values" => {} }],
                                         "assembly_id" => "asm_Ab12Cd34Ef56" }]) do |request, proposal|
            AssemblyAssignment.assign(request, proposal, :assembly_id => request.params.fetch("assembly_id"),
                                                         :targets => request.params.fetch("targets"))
          end
          feature.reference_retargeter("#{PREFIX}.retarget_assembly",
                                       :target_kind => AssemblyAssignment::KIND) do |request, proposal, from:, to:|
            AssemblyAssignment.retarget(request, proposal, :from => from, :to => to)
          end
          feature.query("#{PREFIX}.assembly_usage",
                        :description => "Face counts and gross areas by Assembly.",
                        :refuses => Refuses::READ + %w[geometry.invalid],
                        :params => Shapes::NONE, :result => Shapes.object({ "assemblies" => USAGE }),
                        :examples => [{}]) { |request| { "assemblies" => Faces.all(request).fetch("assembly_usage") } }
          install_usage_pages(feature)
          # Identical snapshot queries are memoized for this build by the shared shell. Usage and the
          # Face table therefore share one walk, without retaining an Index after the read phase.
          feature.snapshot_section("#{PREFIX}.usage", :query => "#{PREFIX}.all")
          feature.query("#{PREFIX}.assembly_choices",
                        :description => "Current Assembly names, hints and colours.",
                        :refuses => [],
                        :params => Shapes::NONE, :result => CHOICES, :examples => [{}]) do |request|
            { "assemblies" => AssemblyAssignment.catalog(request).fetch(:records).values.map do |row|
              { "id" => row.fetch("id"), "name" => row.fetch("values").fetch("name"),
                "type" => row.fetch("values")["type"], "color" => row.fetch("display").fetch("color") }
            end }
          end
          feature.snapshot_section("#{PREFIX}.assemblies", :query => "#{PREFIX}.assembly_choices")
        end
      end
    end
  end
end
