# frozen_string_literal: true

module PhComposer
  module Zones
    # Current native selection is a read; writes retain explicit occurrence references and values.
    module Selection
      FIELDS = { "name" => "Name", "building_segment" => "Building-Segment", "level" => "Level",
                 "ground_depth_mm" => "Ground depth (mm)" }.freeze

      module_function

      def selected(model)
        entities = model.selection.to_a
        unless !entities.empty? && entities.all? { |entity| entity.is_a?(Sketchup::Group) && ZONE_STORE.read(entity) }
          raise CodedError.new("selection.invalid", "Select one or more Zone Groups. Nothing was written.")
        end

        index = Index.new(model)
        path = Occurrences.active_path(model)
        entities.map do |entity|
          record = Names.read(entity)
          reference = { "zone_id" => record.fetch("id"), "zone_path" => path + [entity.persistent_id] }
          resolve(model, reference, index)
        end
      end

      def resolve(model, reference, index)
        zone = Occurrences.resolve_zone(model, reference, :mutable => true, :index => index)
        parent = model.entities
        zone.path.each do |id|
          entity = Occurrences.unique_entity(parent, id)
          if entity.respond_to?(:locked?) && entity.locked?
            raise CodedError.new("target.locked", "A selected Zone or its parent Group is locked.")
          end

          parent = entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        end
        zone
      end

      def available?(session)
        !selected(session.model).empty?
      rescue UserError
        false
      end

      def read(request)
        { "zones" => selected(request.model).map do |zone|
          { "reference" => zone.reference, "values" => Schema.view(zone.record).fetch("values") }
        end }
      end

      # Sets one `field` to one `value` on every target Zone, each guarded by its expected values.
      def update_field(request, proposal, field:, value:, targets:)
        index = Index.new(request.model)
        if targets.map { |target| target.fetch("reference").fetch("zone_path") }.uniq.length != targets.length
          raise CodedError.new("params.invalid", "A Zone may appear only once in the batch.")
        end

        zone_ids = targets.map do |target|
          zone = resolve(request.model, target.fetch("reference"), index)
          before = Schema.view(zone.record).fetch("values")
          if %w[building_segment level].include?(field) && zone.record.fetch("schema_version") == 2
            key = "#{field}_id"
            values = before.merge(key => (value && Options.existing_name(request.engine, field, value)))
          else
            values = before.merge(field => DeepCopy.call(value))
          end
          Zones.update(request, proposal, :reference => zone.reference, :values => values,
                                          :expected_values => target.fetch("expected_values"))
          zone.record.fetch("id")
        end
        { "zone_ids" => zone_ids }
      end

      def client(session)
        session.feature_state(:zones_selection_menu) { Client.new(session) }
      end

      def install(feature)
        zones_selected = ->(read) { available?(read.session) }
        FIELDS.each do |field, label|
          feature.menu_item("#{FEATURE_ID}.edit_#{field}_menu", :label => "Set #{label}…", :menu => EXTENSION_NAME,
                                                                :available => zones_selected) do |session|
            client(session).edit(field)
          end
        end
        feature.menu_item("#{FEATURE_ID}.solve_selected_menu", :label => "Solve adjacencies for selected Zones",
                                                               :menu => EXTENSION_NAME,
                                                               :available => zones_selected) do |session|
          client(session).solve
        end
      end

      class Client
        # The fields whose value is one of the Model's Zone options rather than free text.
        OPTION_FIELDS = %w[building_segment level].freeze

        def initialize(session)
          @session = session
          @context = API.connect(:session_id => session.id)
          @sequence = 0
        end

        def edit(field)
          read = API.query(:context => @context, :name => "#{FEATURE_ID}.selection")
          return show(read) unless read["status"] == "completed"

          rows = read.fetch("value").fetch("zones")
          # Building-Segment and Level are chosen from the Model's options; the other fields are free.
          options = API.query(:context => @context, :name => "#{Options::PREFIX}.all") if OPTION_FIELDS.include?(field)
          if options && options.dig("value", "adoption", "required")
            return show("status" => "refused",
                        "message" => "Adopt Zone options from the column menu first. Nothing was written.")
          end

          choices = options && option_rows(options, field).map { |choice| choice.dig("values", "name") }.sort
          values = rows.map { |row| current_value(row.fetch("values"), field, options) }.uniq
          defaults = [values.length == 1 ? values.first.to_s : ""]
          entered = choices ? UI.inputbox([FIELDS.fetch(field)], defaults, [choices.join("|")], "Selected Zones") :
                              UI.inputbox([FIELDS.fetch(field)], defaults, "Selected Zones")
          return unless entered

          value = entered.first
          value = Float(value) if field == "ground_depth_mm"
          value = nil if field == "level" && value.to_s.empty?
          params = { "field" => field, "value" => value,
                     "targets" => rows.map { |row|
                                    { "reference" => row.fetch("reference"),
                                      "expected_values" => row.fetch("values") }
                                  } }
          show(invoke("#{FEATURE_ID}.update_field", params, read.fetch("revision")))
        rescue ArgumentError, TypeError
          show("status" => "refused", "message" => "Enter a valid ground depth. Nothing was written.")
        end

        def solve
          read = API.query(:context => @context, :name => "#{FEATURE_ID}.selection")
          return refuse(read) unless read["status"] == "completed"

          result = invoke("#{FEATURE_ID}.solve_adjacency",
                          { "zones" => read.fetch("value").fetch("zones").map { |row| row.fetch("reference") } },
                          read.fetch("revision"))
          return refuse(result) unless result["status"] == "completed"

          HostNotice.show(@session, solved(result), :tone => :success)
          result
        end

        private

        def option_rows(options, field)
          options.dig("value", field == "level" ? "levels" : "building_segments")
        end

        # What one selected Zone shows for `field`: its stored value, or the name of the option it names.
        def current_value(stored, field, options)
          return stored[field] if stored[field] || options.nil?

          chosen = option_rows(options, field).find { |choice| choice.fetch("id") == stored["#{field}_id"] }
          chosen&.dig("values", "name")
        end

        def invoke(name, params, revision)
          unless Sketchup.active_model.equal?(@session.model)
            return { "status" => "refused", "message" => "The active Model changed. Nothing was written." }
          end

          @sequence += 1
          API.invoke(:context => @context, :name => name, :params => params,
                     :request => { "sequence" => @sequence, "expected_revision" => revision })
        end

        def refuse(outcome)
          HostNotice.show(@session, HostNotice.words(outcome), :tone => HostNotice.tone(outcome))
          outcome
        end

        # What Solve changed, for the notification: the panel's own confirmation names only the action.
        def solved(result)
          value = result.fetch("value")
          already = value.fetch("already_paired")
          paired = value.fetch("pair_ids").length - already
          retired = Array(result["affected"]).count { |row| row["change"] == "retired" }
          return "Solve adjacencies: no Faces to pair. Nothing changed." if (paired + already + retired).zero?

          ["Solve adjacencies:", paired.positive? ? "#{paired * 2} Faces paired as Surface." : nil,
           paired.zero? && retired.zero? ? "nothing to change." : nil,
           already.positive? ? "#{already * 2} Faces already paired." : nil,
           retired.positive? ? "#{retired} #{retired == 1 ? 'Face' : 'Faces'} retired from out-of-date pairs." : nil]
            .compact.join(" ")
        end

        def show(result)
          @session.notice(result.fetch("message"), :tone => result["status"] == "completed" ? :success : :warning)
          Sketchup.status_text = result.fetch("message")
          result
        end
      end
    end
  end
end
