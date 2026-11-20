# frozen_string_literal: true

module PhComposer
  module Shading
    # What Shading registers: assign and clear over explicit references, each one native Undo step, and the two
    # reads, list and selection. The panel is not involved: a script and the menu reach the same actions.
    module Registration
      extend SchemaShapes

      PREFIX = FEATURE_ID
      TEXT = { "type" => "string" }.freeze
      REFERENCE = Targets::REFERENCE
      TARGETS = list(REFERENCE).merge(
        "minItems" => 1, "maxItems" => Mark::TARGET_LIMIT,
        "description" => "Faces, Groups and components by root-to-entity path, as #{PREFIX}.selection returns " \
                         "them; at most #{Mark::TARGET_LIMIT} references, a repeated path counting toward the " \
                         "limit and applied once."
      )
      PARAMS = object({ "targets" => TARGETS }).freeze
      # Resolving each path: a step missing or repeated refuses the whole command, as does the Zone read.
      RESOLVE = %w[target.not_found target.ambiguous record.unreadable validation.failed].freeze
      # The codes a left-out target carries, which refuse the command when every target is left out.
      ASSIGN_LEFT_OUT = %w[target.wrong_kind target.locked target.shared_definition shading.cutting_component
                           shading.zone_target shading.face_classified].freeze
      CLEAR_LEFT_OUT = %w[target.wrong_kind target.locked target.shared_definition shading.inherited].freeze
      ASSIGN = (RESOLVE + ASSIGN_LEFT_OUT + %w[target.changed]).freeze
      CLEAR = (RESOLVE + CLEAR_LEFT_OUT + %w[target.changed]).freeze
      LEFT_OUT_ROW = object(REFERENCE.fetch("properties").merge("code" => TEXT, "message" => TEXT))
      REFERENCES = list(REFERENCE)
      PRECONDITIONS = ["Each path still names one Face, Group or component, step by step from the Model root.",
                       "The request carries the revision the references were read at."].freeze
      EXAMPLE = { "targets" => [{ "entity_path" => [4812, 4901] }] }.freeze
      OUTCOME = object({
        "outcome" => TEXT, "code" => { "type" => %w[string null] }, "message" => { "type" => %w[string null] }
      })
      SELECTED_ROW = object({
        "reference" => REFERENCE,
        "kind" => { "type" => "string", "enum" => Mark::KINDS },
        "marked" => { "type" => "boolean", "description" => "The entity carries the mark itself, readable or not." },
        "assign" => described(OUTCOME, "What #{PREFIX}.assign does to it: assigned, unchanged or left_out, with the " \
                                       "code and message when left out."),
        "clear" => described(OUTCOME, "What #{PREFIX}.clear does to it: cleared, unchanged or left_out, with the " \
                                      "code and message when left out.")
      })
      SELECTION = object({
        "entities" => list(SELECTED_ROW),
        "ignored" => list(object({ "persistent_id" => { "type" => "integer" }, "type" => TEXT }))
                     .merge("description" => "Selected entities that are not Faces, Groups or components, the first " \
                                             "#{Selection::IGNORED_ROWS}; never written."),
        "ignored_total" => { "type" => "integer", "minimum" => 0 }
      })
      LIST = object({
        "marked" => list(object({
          "entity_path" => REFERENCE.dig("properties", "entity_path"),
          "kind" => { "type" => "string", "enum" => Mark::KINDS },
          "readable" => { "type" => "boolean", "description" => "False when the stored mark is not a JSON object; " \
                                                                "it still marks the entity, and clear removes it." }
        })).merge("description" => "Every entity carrying the mark, inside cutting components too, in path order."),
        "components" => list(object({
          "display_name" => TEXT, "face_count" => { "type" => "integer", "minimum" => 0 },
          "area_m2" => { "type" => "number", "minimum" => 0, "x-unit" => "m2" }
        })).merge("description" => "Each shading component: the Shading Faces that export under one name, with " \
                                   "their count and world area, by name."),
        "units" => object({ "area_m2" => { "type" => "string", "enum" => ["m2"] } })
      })

      module_function

      def install(feature)
        install_action(feature, "assign", "assigned", ASSIGN, ASSIGN_LEFT_OUT,
                       :description => "Mark explicit Faces, Groups and components as shading. Every target that " \
                                       "can take the mark gets it in one Undo step; one already marked is unchanged; " \
                                       "one that cannot is left out with its code. Refuses only when every target " \
                                       "is left out.",
                       :undo_name => "Set as Shading",
                       :side_effects => "Writes the mark on each assigned entity.") do |request, proposal|
          Operations.assign(request, proposal, :targets => request.params.fetch("targets"))
        end
        install_action(feature, "clear", "cleared", CLEAR, CLEAR_LEFT_OUT,
                       :description => "Remove the shading mark from explicit Faces, Groups and components, in one " \
                                       "Undo step. Only the named entity's own mark goes: one shading through a " \
                                       "marked container above it is left out as shading.inherited.",
                       :undo_name => "Clear Shading",
                       :side_effects => "Removes the mark from each cleared entity.") do |request, proposal|
          Operations.clear(request, proposal, :targets => request.params.fetch("targets"))
        end
        install_reads(feature)
      end

      def install_action(feature, name, done, refuses, left_out, description:, undo_name:, side_effects:, &handler)
        result = object({
          done => described(REFERENCES, "The entities this command changed."),
          "unchanged" => described(REFERENCES, "The entities already as asked; nothing was written to them."),
          "left_out" => described(list(LEFT_OUT_ROW), "The entities this command cannot change, each with its " \
                                                      "code (#{left_out.join(', ')}) and message.")
        })
        feature.action("#{PREFIX}.#{name}", :description => description, :refuses => refuses, :params => PARAMS,
                                            :result => result, :undo_name => undo_name,
                                            :preconditions => PRECONDITIONS, :side_effects => side_effects,
                                            :examples => [EXAMPLE], &handler)
      end

      def install_reads(feature)
        feature.query("#{PREFIX}.list",
                      :description => "Every entity carrying the shading mark and every shading component: the " \
                                      "Shading Faces grouped by the name they export under, with Face count and " \
                                      "world area. Reads Zones' occurrences, then walks the Model once.",
                      :refuses => %w[geometry.invalid record.unreadable validation.failed], :params => object({}),
                      :result => LIST,
                      :examples => [{}]) { |request| Inventory.list(request) }
        feature.query("#{PREFIX}.selection",
                      :description => "The selected Faces, Groups and components under the active path as " \
                                      "references, each with what #{PREFIX}.assign and #{PREFIX}.clear would do " \
                                      "to it; anything else selected is ignored.",
                      :refuses => (RESOLVE + %w[gesture.too_large]).freeze, :params => object({}),
                      :result => SELECTION, :examples => [{}]) { |request| Selection.read(request) }
      end
    end
  end
end
