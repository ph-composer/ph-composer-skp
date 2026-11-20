# frozen_string_literal: true

module PhComposer
  module Zones
    module SelectionRegistration
      TARGET = Shapes.object({ "reference" => ZONE_REFERENCE, "expected_values" => INPUT_VALUES }).freeze
      ROW = Shapes.object({ "reference" => ZONE_REFERENCE, "values" => INPUT_VALUES }).freeze
      UPDATE = Shapes.object({
        "targets" => Shapes.list(TARGET).merge("minItems" => 1, "description" => "Each Zone occurrence to change, " \
                                                                                 "with the values last read; a " \
                                                                                 "change refuses."),
        "field" => { "type" => "string", "enum" => Selection::FIELDS.keys, "description" => "The Zone value to set." },
        "value" => { "type" => %w[string number null],
                     "description" => "The new value: text for name, building_segment and level (null clears " \
                                      "level, and moves the Zone to No Building Segment for building_segment), " \
                                      "a number in mm for ground_depth_mm." }
      }).freeze
      ASSIGNMENT = Shapes.object({ "token" => { "type" => %w[string null] },
                                   "revision" => { "type" => %w[integer null] },
                                   "faces" => Shapes.list(Faces::FACE_REFERENCE) }).freeze

      module_function

      def install(feature)
        feature.query("#{FEATURE_ID}.selection",
                      :description => "Valid selected Zone occurrences and current values.",
                      :refuses => Refuses::ZONE_TARGET + %w[selection.invalid],
                      :params => Shapes::NONE, :result => Shapes.object({ "zones" => Shapes.list(ROW) }),
                      :examples => [{}]) { |request| Selection.read(request) }
        feature.action("#{FEATURE_ID}.update_field",
                       :description => "Set one attribute on explicit Zone occurrences.",
                       :refuses => Options::Registration::REFUSALS,
                       :params => UPDATE, :result => Shapes.object({ "zone_ids" => Shapes.list(Shapes::ID) }),
                       :undo_name => "Edit Selected Zones",
                       :side_effects => "Updates each Zone and its membership stamps.",
                       :examples => [{ "targets" => [{ "reference" => ZoneRegistration::EXAMPLE_REFERENCE,
                                                       "expected_values" => ZoneRegistration::EXAMPLE_VALUES }],
                                       "field" => "level", "value" => "L1" }]) do |request, proposal|
          Selection.update_field(request, proposal,
                                 :field => request.params.fetch("field"),
                                 :value => request.params.fetch("value"), :targets => request.params.fetch("targets"))
        end
        Selection.install(feature)
        install_faces(feature)
      end

      def install_faces(feature)
        prefix = Faces::PREFIX
        feature.query("#{prefix}.selection",
                      :description => "Validated selected Face occurrence references.",
                      :refuses => Refuses::FACE_TARGET + %w[gesture.too_large selection.invalid],
                      :params => Shapes::NONE,
                      :result => Shapes.object({ "faces" => Shapes.list(Faces::FACE_REFERENCE),
                                                 "targets" => Shapes.list(Faces::AssemblyRegistration::TARGET) }),
                      :examples => [{}]) { |request| Faces::Selection.read(request) }
        feature.snapshot_section("#{prefix}.selected", :query => "#{prefix}.selection")
        # Never refuses, so a selection with no Faces in it still reports that the selection changed.
        feature.query("#{prefix}.selection_generation",
                      :description => "How many times SketchUp's selection has changed in this session.",
                      :refuses => [], :params => Shapes::NONE,
                      :result => Shapes.object({ "generation" => Shapes::COUNT.merge(
                        "description" => "Advances on every native selection change, whatever it selects."
                      ) }),
                      :examples => [{}]) do |request|
          { "generation" => Faces::Selection.generation(request.session).value }
        end
        feature.snapshot_section("#{prefix}.selection_change", :query => "#{prefix}.selection_generation")
        feature.on_host_event(:selection_changed) { |session| Faces::Selection.generation(session).advance }
        install_attached_assignment(feature, prefix)
      end

      # The native handoff that reviews a new Attached zone for the Faces chosen in the viewport.
      def install_attached_assignment(feature, prefix)
        feature.query("#{prefix}.attached_assignment",
                      :description => "The pending native Face assignment handoff.",
                      :refuses => [],
                      :params => Shapes::NONE, :result => ASSIGNMENT,
                      :examples => [{}]) { |request| Faces::Selection.handoff(request.session).snapshot }
        feature.snapshot_section("#{prefix}.selection_assignment", :query => "#{prefix}.attached_assignment")
        feature.view_command("#{prefix}.open_attached_assignment",
                             :description => "Review a new Attached zone assignment for explicit Faces.",
                             :refuses => Refuses::FACE_TARGET + %w[assignment.pending gesture.too_large revision.stale],
                             :params => Shapes.object({
                               "faces" => Faces::Registration::FACES.merge("description" => "The Faces the new " \
                                                                                            "Attached zone would be " \
                                                                                            "assigned to."),
                               "revision" => { "type" => "integer", "description" => "The revision the Faces were " \
                                                                                     "read at; a later one refuses." }
                             }),
                             :result => ASSIGNMENT,
                             :examples => [{ "faces" => [Faces::Registration::EXAMPLE_FACE],
                                             "revision" => 1 }]) do |request|
          Faces::Selection.open_assignment(request, :revision => request.params.fetch("revision"),
                                                    :faces => request.params.fetch("faces"))
        end
        feature.view_command("#{prefix}.close_attached_assignment",
                             :description => "Close the native assignment handoff.",
                             :refuses => [],
                             :params => Shapes.object({
                               "token" => { "type" => "string", "description" => "The token open_attached_" \
                                                                                 "assignment returned; another one " \
                                                                                 "leaves the handoff open." }
                             }),
                             :result => ASSIGNMENT,
                             :examples => [{ "token" => "example-review-token" }]) do |request|
          value = Faces::Selection.handoff(request.session).close(request.params.fetch("token"))
          request.session.changed(:zones, :attached_assignment)
          value
        end
      end
    end
  end
end
