# frozen_string_literal: true

module PhComposer
  module Shading
    # What assign and clear do to one resolved target, as pure functions over its detached facts: the target
    # rules of context/CONTRACTS.md, "The shading mark", in their order. The selection read and both actions
    # call the same functions, so what a read says an action would do is what the action does at the same
    # revision.
    module Eligibility
      # The facts about one target. `kind` is a Mark kind or nil for an entity the mark never sits on.
      # `containers` are the Reads::Container rows above it, outermost first. `locked`: the target or a
      # container above it is locked. `shared`: a container above it is storage another placement shares, so a
      # write would reach that placement too. `cutting`: the target is, or sits inside, a cutting component.
      # `owned`: the target or a container above it is another feature's object. `classified`: a Face in a Zone
      # with a Face record, whatever its values.
      # `zone`: the target is a Zone Group. `zone_target`: a container that is a Zone or holds one.
      # `holds_owned`: a container holding another feature's object. `classified_inside`: for a container inside a
      # Zone, how many classified Zone Faces the mark would reach.
      Facts = Struct.new(:path, :kind, :marked, :containers, :locked, :shared, :cutting, :owned, :classified,
                         :zone, :zone_target, :holds_owned, :classified_inside, keyword_init: true)

      SHARED = "The %s is in storage another placement shares (a Component placed more than once, or a copied " \
               "Group not yet made unique), so the mark would reach every placement. Tag the Component or Group " \
               "instead, or make it unique first."

      module_function

      # `[outcome, refusal]`: "assigned" or "unchanged" with nil, or "left_out" with `{code, message}`.
      def assign(facts)
        refusal = assign_refusal(facts)
        return ["left_out", refusal] if refusal

        [facts.marked ? "unchanged" : "assigned", nil]
      end

      # `[outcome, refusal]`: "cleared" or "unchanged" with nil, or "left_out" with `{code, message}`. Clear
      # only removes a mark, so a target's nature never refuses it; its path's lock and sharing do.
      def clear(facts)
        return ["left_out", wrong_kind] unless facts.kind

        unless facts.marked
          through = inherits?(facts) && Reads.inherited_from(facts.containers)
          return ["left_out", inherited(through)] if through

          return ["unchanged", nil]
        end
        refusal = write_refusal(facts)
        refusal ? ["left_out", refusal] : ["cleared", nil]
      end

      def assign_refusal(facts)
        return wrong_kind unless facts.kind
        return refusal("target.wrong_kind", "Another feature owns this #{noun(facts)}.") if facts.owned
        return refusal("shading.cutting_component", "The #{noun(facts)} is a cutting component or inside one; " \
                                                    "export does not read its Faces.") if facts.cutting
        if facts.zone_target
          return refusal("shading.zone_target", "The #{noun(facts)} is a Zone or holds one. A whole Zone as " \
                                                "shading is not supported.")
        end
        if facts.holds_owned
          return refusal("target.wrong_kind", "The #{noun(facts)} holds an object another feature owns, such as a " \
                                              "Space.")
        end
        if facts.classified
          return refusal("shading.face_classified", "The Face is a classified Zone Face. Clear its classification " \
                                                    "first (ph_composer.zones.faces.clear_classification).")
        end
        if !facts.marked && facts.classified_inside.to_i.positive?
          return refusal("shading.face_classified", "The #{noun(facts)} holds #{facts.classified_inside} classified " \
                                                    "Zone Face(s). Clear their classification first " \
                                                    "(ph_composer.zones.faces.clear_classification).")
        end
        write_refusal(facts)
      end

      # What the target's path refuses to any write: storage another placement shares, then a lock.
      def write_refusal(facts)
        return refusal("target.shared_definition", format(SHARED, noun(facts))) if facts.shared
        return refusal("target.locked", "The #{noun(facts)} or a Group above it is locked.") if facts.locked

        nil
      end

      # Whether a mark above can reach the target at all: never a cutting component or anything inside one, a
      # Zone Group, another feature's object, or a classified Zone Face, which stays envelope.
      def inherits?(facts)
        !(facts.cutting || facts.zone || facts.owned || facts.classified)
      end

      def inherited(container)
        name = Reads.named?(container.name) ? "\"#{container.name}\"" : "an unnamed Group or component"
        refusal("shading.inherited", "The entity is shading through #{name} at path #{container.path.inspect}, " \
                                     "which carries the mark. Clear that one instead.")
      end

      def wrong_kind
        refusal("target.wrong_kind", "Only Faces, Groups and components take the shading mark.")
      end

      def noun(facts)
        { "face" => "Face", "group" => "Group", "component_instance" => "component" }.fetch(facts.kind)
      end

      def refusal(code, message)
        { "code" => code, "message" => message }
      end
    end
  end
end
