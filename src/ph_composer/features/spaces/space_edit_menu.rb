# frozen_string_literal: true

module PhComposer
  module Spaces
    # A selected Space's common edits from SketchUp's context menu, each through the public action a script uses:
    # Move to Zone and Set Number… on one Space, Set Name… and Set Airflows… on one or several. They are offered
    # only on the right-click, where a selection of nothing but Spaces says which Spaces they edit. A dialog
    # accepted unchanged writes nothing, and a field left as shown writes nothing, so a rounded or blank default
    # never replaces a stored value.
    module SpaceEditMenu
      MOVE_MENU = "Move to Zone"
      NUMBER = "Set Number…"
      NAME = "Set Name…"
      AIRFLOWS_LABEL = "Set Airflows…"
      ZONES_READ = "ph_composer.zones.all"
      AIRFLOW_PROMPTS = { "v_sup_m3h" => "Supply", "v_eta_m3h" => "Extract", "v_tran_m3h" => "Transfer" }.freeze
      SELECT_SPACES = "Select one or more Spaces. #{Outcome::NOTHING_WRITTEN}".freeze
      SELECT_ONE = "Select one Space. #{Outcome::NOTHING_WRITTEN}".freeze
      INVALID_AIRFLOW = "Enter each airflow as a number of 0 or more, or leave it blank to remove it. " \
                        "#{Outcome::NOTHING_WRITTEN}".freeze

      # One selected Space: the reference an action takes and the record as it was read.
      Selected = Struct.new(:reference, :record, keyword_init: true)

      module_function

      def install(feature)
        feature.menu_entries("#{FEATURE_ID}.move_to_zone_menu", :menu => MOVE_MENU,
                                                                :available => ->(read) { movable?(read) }) do |read|
          zone_entries(read)
        end
        single(feature, "set_number", NUMBER, ->(read) { selected(read.model).length == 1 }) do |session|
          client(session).number
        end
        any = ->(read) { !selected(read.model).empty? }
        single(feature, "set_name", NAME, any) { |session| client(session).name }
        single(feature, "set_airflows", AIRFLOWS_LABEL, any) { |session| client(session).airflows }
      end

      # One right-click item in the extension's own menu. A provider rather than a `menu_item`, so the item stays
      # off the Extensions menu, where Zones' Set Name… already stands and no selection says which it edits.
      def single(feature, key, label, available, &handler)
        feature.menu_entries("#{FEATURE_ID}.#{key}_menu", :menu => EXTENSION_NAME, :available => available) do |_read|
          [Declarations::MenuEntry.new(:label => label, :handler => handler)]
        end
      end

      # The selected Spaces, or none unless the selection holds nothing else.
      def selected(model)
        chosen = model.selection.to_a
        return [] unless chosen.all? { |entity| Navigation.space?(entity) }

        open = Array(model.active_path).map(&:persistent_id)
        chosen.map do |entity|
          record = SPACE_STORE.read(entity)
          reference = { "space_id" => record.fetch("id"), "entity_path" => open + [entity.persistent_id] }
          Selected.new(:reference => reference, :record => record)
        end
      end

      # One Space selected and a Zone in the Model to host it.
      def movable?(read)
        selected(read.model).length == 1 && !read.query(ZONES_READ).fetch("zones").empty?
      end

      # The Model's Zones in the order Zones lists them, the Space's own checked.
      def zone_entries(read)
        space = selected(read.model).first
        return [] unless space

        read.query(ZONES_READ).fetch("zones").map do |zone|
          reference = zone.fetch("reference")
          name = zone.dig("values", "name").to_s
          checked = reference.fetch("zone_id") == space.record["zone_id"] ? MF_CHECKED : MF_UNCHECKED
          Declarations::MenuEntry.new(:label => name.strip.empty? ? "Zone" : name,
                                      :state => ->(_session) { checked },
                                      :handler => ->(session) { client(session).move(reference) })
        end
      end

      def client(session)
        session.feature_state(:spaces_edit_menu) { Client.new(session) }
      end

      class Client
        def initialize(session)
          @session = session
          @context = API.connect(:session_id => session.id)
          @sequence = 0
        end

        # Hosts the one selected Space in `zone`; its own Zone, the checked one, changes nothing.
        def move(zone)
          spaces = SpaceEditMenu.selected(@session.model)
          return announce(SELECT_ONE) unless spaces.length == 1
          return if spaces.first.record["zone_id"] == zone.fetch("zone_id")

          report(invoke("#{FEATURE_ID}.move_to_zone", { "space" => spaces.first.reference, "zone" => zone },
                        @session.revision))
        end

        # One Space only: Spaces sharing a number raise the duplicate warning.
        def number
          spaces = SpaceEditMenu.selected(@session.model)
          return announce(SELECT_ONE) unless spaces.length == 1

          edit_text(spaces, "number", "Number")
        end

        def name
          spaces = SpaceEditMenu.selected(@session.model)
          return announce(SELECT_SPACES) if spaces.empty?

          edit_text(spaces, "name", "Name")
        end

        # Supply, Extract and Transfer in the display unit. A field shows the value every selected Space shares and
        # is blank otherwise. A field left as shown writes nothing; one emptied removes the value; with all three
        # removed a Space takes its Zone's ventilation load again.
        def airflows
          spaces = SpaceEditMenu.selected(@session.model)
          return announce(SELECT_SPACES) if spaces.empty?

          system = Preferences.unit_system
          defaults = AIRFLOWS.map { |key| shown_airflow(shared(spaces, key), system) }
          prompts = AIRFLOWS.map do |key|
            HostPrompt.measured(AIRFLOW_PROMPTS.fetch(key), :quantity => "airflow", :system => system)
          end
          revision = @session.revision
          entered = UI.inputbox(prompts, defaults, title(spaces))
          return unless entered

          changes = airflow_changes(entered, defaults, system)
          return announce(INVALID_AIRFLOW) unless changes

          submit(spaces, changes, revision) unless changes.empty?
        end

        private

        def edit_text(spaces, field, prompt)
          value = shared(spaces, field)
          defaults = [value.to_s]
          revision = @session.revision
          entered = UI.inputbox([prompt], defaults, title(spaces))
          return if entered.nil? || entered == defaults

          submit(spaces, { field => entered.first }, revision)
        end

        # The value every Space holds for `key`, or nil when they differ or none holds one. 60 and 60.0 are one value.
        def shared(spaces, key)
          values = spaces.map { |space| space.record[key] }.uniq { |value| value.is_a?(Numeric) ? value.to_f : value }
          values.first if values.length == 1
        end

        # Never grouped: the dialog hands this text back to be read as a number.
        def shown_airflow(value, system)
          return "" unless value

          Units.format(value, :quantity => "airflow", :system => system, :show_unit => false, :group_from => nil)
        end

        # Only the fields that changed: an emptied one is nil, which removes the value; a typed one in m3/h. Nil when
        # a typed one is not an airflow.
        def airflow_changes(entered, defaults, system)
          changes = {}
          AIRFLOWS.each_with_index do |key, index|
            text = entered[index].to_s.strip
            next if HostPrompt.unchanged?(text, defaults[index])

            value = text.empty? ? nil : airflow_m3h(text, system)
            return nil if value.nil? && !text.empty?

            changes[key] = value
          end
          changes
        end

        # The typed airflow in m3/h, or nil when it is not a finite number of 0 or more.
        def airflow_m3h(text, system)
          number = Float(text, :exception => false)
          return unless number&.finite? && number >= 0

          number.zero? ? 0.0 : Units.from_display(number, :quantity => "airflow", :system => system)
        end

        # The same `values` on every Space, each guarded by its own current values: one Space through `update`, more
        # through `batch_update`, either way one Undo step.
        def submit(spaces, values, revision)
          edits = spaces.map do |space|
            { "reference" => space.reference, "values" => values,
              "expected_values" => values.keys.to_h { |key| [key, space.record[key]] } }
          end
          outcome = if edits.length == 1
                      invoke("#{FEATURE_ID}.update", edits.first, revision)
                    else
                      invoke("#{FEATURE_ID}.batch_update", { "edits" => edits }, revision)
                    end
          report(outcome)
        end

        def title(spaces)
          spaces.length == 1 ? "Selected Space" : "Selected Spaces"
        end

        def invoke(name, params, revision)
          @sequence += 1
          API.invoke(:context => @context, :name => name, :params => params,
                     :request => { "sequence" => @sequence, "expected_revision" => revision })
        end

        def report(outcome)
          if outcome.fetch("status") == "completed"
            @session.notice(outcome.fetch("message"), :tone => :success)
            Sketchup.status_text = outcome.fetch("message")
          else
            HostNotice.show(@session, HostNotice.words(outcome), :tone => HostNotice.tone(outcome))
          end
          outcome
        end

        def announce(message)
          HostNotice.show(@session, message, :tone => :warning)
          nil
        end
      end
    end
  end
end
