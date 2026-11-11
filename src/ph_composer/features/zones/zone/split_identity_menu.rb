# frozen_string_literal: true

module PhComposer
  module Zones
    # The native client for split repair. Selection chooses a piece only when the public preview
    # cannot prove the original path. Planning, payload validation and all writes belong to the
    # registered action, just as they do when a script calls it with the panel closed.
    module SplitIdentityMenu
      ACTION = "#{FEATURE_ID}.repair_split_face"
      LABEL = "Repair split Face identities…"

      module_function

      def install(feature)
        feature.menu_item("#{FEATURE_ID}.repair_split_face_menu", :label => LABEL, :menu => "Repair",
                                                                  :available => ->(read) {
                                                                                  available?(read.session)
                                                                                }) do |session|
          session.feature_state(:zones_split_identity_menu) { Client.new(session) }.run
        end
      end

      # One Face selected, outside anything another feature claims: a claimed Face carries no Zone identity.
      def available?(session)
        model = session.model
        model.selection.to_a.grep(Sketchup::Face).length == 1 && !Records::EntityStore.selection_claimed?(model)
      end

      class Client
        def initialize(session)
          @session = session
          @context = API.connect(:session_id => session.id)
          @sequence = 0
        end

        def run
          params, target, names = selected_target
          return unless params

          preview = API.preview(:context => @context, :name => ACTION, :params => params)
          if preview["code"] == "identity.choice_required"
            params["retaining_entity_path"] = target.fetch("reference").fetch("entity_path")
            preview = API.preview(:context => @context, :name => ACTION, :params => params)
          end
          return show(preview) unless preview["status"] == "completed"
          return unless UI.messagebox(review(preview.fetch("value"), names), MB_YESNO) == IDYES
          unless Sketchup.active_model.equal?(@session.model)
            return UI.messagebox("The active Model changed. Start the repair again in its Model.")
          end

          @sequence += 1
          result = API.invoke(:context => @context, :name => ACTION, :params => params,
                              :request => { "sequence" => @sequence, "expected_revision" => preview.fetch("revision"),
                                            "proposal_digest" => preview.fetch("proposal_digest") })
          show(result)
        rescue StandardError => error
          UI.messagebox("Split Face repair could not complete: #{error.message}")
        end

        private

        def selected_target
          selected = @session.model.selection.to_a.grep(Sketchup::Face)
          unless selected.length == 1
            UI.messagebox("Open the Zone and select one of its split Faces first.")
            return []
          end
          result = API.query(:context => @context, :name => "ph_composer.zones.faces.all")
          unless result["status"] == "completed"
            show(result)
            return []
          end

          rows = result.dig("value", "faces")
          path = Array(@session.model.active_path).map(&:persistent_id) + [selected.first.persistent_id]
          target = rows.find do |face|
            reference = face.fetch("reference")
            reference.fetch("zone_path") + reference.fetch("entity_path") == path
          end
          unless target && target.dig("reference", "entity_id")
            UI.messagebox("The selected Face has no recorded Zone identity to repair.")
            return []
          end
          copies = rows.select { |face| face.dig("reference", "entity_id") == target.dig("reference", "entity_id") }
          if copies.length < 2
            UI.messagebox("The selected Face has no duplicated identity. Nothing was changed.")
            return []
          end
          scope = scope_for(copies)
          names = rows.select { |face| scope.include?(zone_reference(face.fetch("reference"))) }
                      .map { |face| face.fetch("zone_name") }.uniq
          [{ "zone" => zone_reference(target.fetch("reference")),
             "face_id" => target.dig("reference", "entity_id"), "zones" => scope }, target, names]
        end

        def scope_for(copies)
          copies.flat_map do |face|
            references = [face.fetch("reference")]
            counterpart = face.dig("values", "adjacency", "counterpart")
            references << counterpart if counterpart
            references.map { |reference| zone_reference(reference) }
          end.uniq
        end

        def zone_reference(reference)
          { "zone_id" => reference.fetch("zone_id"), "zone_path" => reference.fetch("zone_path") }
        end

        def review(value, names)
          fresh = value.fetch("pieces").count { |piece| piece.dig("after", "entity_id") != value.fetch("face_id") }
          keeper = if value.fetch("retention_basis") == "stored_endpoint"
                     "The stored original path identifies the Face that keeps its identity."
                   else
                     "The selected Face will keep the original identity."
                   end
          retired = value.fetch("retired").length
          lines = [keeper, "#{fresh} other split Face(s) will receive new identities."]
          lines << "Invalid Surface links will be cleared on #{retired} Face(s)." if retired.positive?
          lines << "Affected Zones: #{names.join(', ')}."
          lines << "Supported classification and metadata will be preserved."
          lines << "Proceed with repair?"
          lines.join("\n\n")
        end

        def show(result)
          UI.messagebox(result.fetch("message"))
        end
      end
    end
  end
end
