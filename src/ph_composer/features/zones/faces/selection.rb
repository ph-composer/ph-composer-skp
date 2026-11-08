# frozen_string_literal: true

module PhComposer
  module Zones
    module Faces
      module Selection
        module_function

        def selected(model, index: nil)
          entities = model.selection.to_a
          unless !entities.empty? && entities.all? { |entity| entity.is_a?(Sketchup::Face) }
            raise CodedError.new("selection.invalid", "Select Faces inside authored Zones. Nothing was written.")
          end

          if entities.length > Faces.gesture_face_limit
            raise CodedError.new("gesture.too_large", "Select at most #{Faces.gesture_face_limit} Faces. " \
                                                      "Nothing was written.")
          end
          index ||= Zones::Index.new(model)
          parent = Array(model.active_path)
          entities.map do |entity|
            picked = Zones::Occurrences.occurrence_for_path(parent + [entity])
            unless picked
              raise CodedError.new("target.wrong_zone", "A selected Face is outside an authored Zone.")
            end

            record = FACE_STORE.read(entity)
            Schema.validate!(record) if record
            reference = picked.reference(record && record.fetch("id"))
            resolved = Zones::Occurrences.resolve_face(model, reference,
                                                       :mutable => true,
                                                       :allow_unassigned => record.nil?, :index => index)
            Zones::Selection.resolve(model, resolved.zone.reference, index)
            reference
          end
        end

        def read(request)
          index = Zones::Index.new(request.model)
          references = selected(request.model, :index => index)
          targets = references.map do |reference|
            face = Zones::Occurrences.resolve_face(request.model, reference,
                                                   :index => index,
                                                   :allow_unassigned => reference["entity_id"].nil?)
            record = FACE_STORE.read(face.entity)
            { "reference" => reference, "expected_values" => record ? Schema.values(record) : {} }
          end
          { "faces" => references, "targets" => targets }
        end

        def available?(session)
          !selected(session.model).empty?
        rescue UserError
          false
        end

        # How many times SketchUp's selection has changed in this session. The panel's checked set follows
        # the selection one way, and the Faces a selection holds cannot tell a change from no change: a
        # Group selected and then nothing reads as no Faces both times. The count can.
        class Generation
          attr_reader :value

          def initialize
            @value = 0
          end

          def advance
            @value += 1
          end
        end

        def generation(session)
          session.feature_state(:faces_selection_generation) { Generation.new }
        end

        def handoff(session)
          session.feature_state(:faces_selection_assignment) { AssignmentState.new }
        end

        # `revision` is the one the caller read `faces` at; a later Model refuses.
        def open_assignment(request, revision:, faces:)
          if revision != request.revision
            raise CodedError.new("revision.stale", "The Model changed after the selected Faces were read.")
          end

          references = faces
          index = Zones::Index.new(request.model)
          if references.length > Faces.gesture_face_limit
            raise CodedError.new("gesture.too_large", "Choose at most #{Faces.gesture_face_limit} Faces.")
          end

          references.each do |reference|
            face = Zones::Occurrences.resolve_face(request.model, reference,
                                                   :mutable => true,
                                                   :allow_unassigned => reference["entity_id"].nil?, :index => index)
            Zones::Selection.resolve(request.model, face.zone.reference, index)
          end
          state = handoff(request.session)
          if state.snapshot.fetch("token")
            raise CodedError.new("assignment.pending", "Finish the open Attached zone assignment first.")
          end

          state.open(references, request.revision)
          request.session.changed(:zones, :attached_assignment)
          state.snapshot
        end

        def client(session)
          session.feature_state(:faces_selection_menu) { Client.new(session) }
        end

        class AssignmentState
          def initialize
            clear
          end

          def open(faces, revision)
            @value = { "token" => SecureRandom.uuid, "revision" => revision, "faces" => DeepCopy.call(faces) }
          end

          def snapshot
            DeepCopy.call(@value)
          end

          def close(token)
            clear if @value.fetch("token") == token
            snapshot
          end

          def clear
            @value = { "token" => nil, "revision" => nil, "faces" => [] }
          end

          def detach
            clear
          end
        end

        class Client
          def initialize(session)
            @session = session
            @context = API.connect(:session_id => session.id)
            @sequence = 0
          end

          def classify(field, value)
            if @session.model.selection.to_a.empty? && field != "attached_zone_id"
              return show(API.view(:context => @context, :name => "#{PREFIX}.choose",
                                   :params => { "field" => field, "value" => value }))
            end
            read = API.query(:context => @context, :name => "#{PREFIX}.selection")
            return show(read) unless read["status"] == "completed"

            intent = { field => { "mode" => "set", "value" => value } }
            if field == "attached_zone_id"
              intent["boundary_condition"] = { "mode" => "set", "value" => "AttachedZone" }
            end
            @sequence += 1
            show(API.invoke(:context => @context, :name => "#{PREFIX}.classify",
                            :params => { "faces" => read.fetch("value").fetch("faces"), "intent" => intent },
                            :request => { "sequence" => @sequence, "expected_revision" => read.fetch("revision") }))
          end

          def assembly(id)
            if @session.model.selection.to_a.empty?
              return show(API.view(:context => @context, :name => "#{PREFIX}.choose",
                                   :params => { "field" => "assembly_id", "value" => id }))
            end
            read = API.query(:context => @context, :name => "#{PREFIX}.selection")
            return show(read) unless read["status"] == "completed"

            @sequence += 1
            show(API.invoke(:context => @context, :name => "#{PREFIX}.assign_assembly",
                            :params => { "targets" => read.fetch("value").fetch("targets"), "assembly_id" => id },
                            :request => { "sequence" => @sequence, "expected_revision" => read.fetch("revision") }))
          end

          # MF_CHECKED when every selected Face holds `value` for `field`; a mixed selection marks nothing, so
          # a check mark always means the whole selection has that value.
          def check(field, value)
            shared.fetch(field, :none) == value ? MF_CHECKED : MF_UNCHECKED
          end

          # Solve adjacencies alone sets Surface, so it is no choice here; a selection that holds it still
          # gets its mark, greyed, rather than reading as mixed.
          def surface_entries
            return [] unless shared["boundary_condition"] == "Surface"

            [Declarations::MenuEntry.new(:label => "Surface (set by Solve adjacencies)", :handler => ->(_session) {},
                                         :state => ->(_session) { MF_CHECKED | MF_GRAYED })]
          end

          def assembly_entries
            read = API.query(:context => @context, :name => "#{PREFIX}.assembly_choices")
            return [] unless read["status"] == "completed"

            selection = API.query(:context => @context, :name => "#{PREFIX}.selection")
            types = Array(selection.dig("value", "targets")).map { |target| target.dig("expected_values", "face_type") }
            records = read.fetch("value").fetch("assemblies").sort_by do |row|
              [types.include?(row["type"]) && row["type"] ? 0 : 1, row.fetch("name").downcase, row.fetch("id")]
            end
            entries = records.map do |row|
              id = row.fetch("id")
              Declarations::MenuEntry.new(:label => row.fetch("name"),
                                          :handler => ->(session) { Selection.client(session).assembly(id) },
                                          :state => ->(session) { Selection.client(session).check("assembly_id", id) })
            end
            entries << Declarations::MenuEntry.new(:label => "Clear assembly",
                                                   :handler => ->(session) { Selection.client(session).assembly(nil) },
                                                   :state => ->(session) do
                                                     Selection.client(session).check("assembly_id", nil)
                                                   end)
            entries
          end

          def open_assignment
            read = API.query(:context => @context, :name => "#{PREFIX}.selection")
            return show(read) unless read["status"] == "completed"

            result = API.view(:context => @context, :name => "#{PREFIX}.open_attached_assignment",
                              :params => { "faces" => read.fetch("value").fetch("faces"),
                                           "revision" => read.fetch("revision") })
            return show(result) unless result["status"] == "completed"

            Commands.open_panel.proc.call
            result
          end

          # All existing records are current at menu construction, including pages beyond the first.
          def attached_entries
            records = []
            cursor = nil
            loop do
              params = { "kind" => AttachedZone::KIND_ID, "fields" => ["name"], "limit" => Pages::MAXIMUM_LIMIT }
              params["cursor"] = cursor if cursor
              read = API.query(:context => @context, :name => RecordQueries::LIST, :params => params)
              return [] unless read["status"] == "completed"

              records.concat(read.fetch("value").fetch("records"))
              cursor = read.fetch("value").fetch("next_cursor")
              break unless cursor
            end
            records.map do |record|
              id = record.fetch("id")
              Declarations::MenuEntry.new(:label => "Attached zone: #{record.fetch('values').fetch('name')}",
                                          :handler => ->(session) do
                                            Selection.client(session).classify("attached_zone_id", id)
                                          end,
                                          :state => ->(session) do
                                            Selection.client(session).check("attached_zone_id", id)
                                          end)
            end
          end

          private

          # The value each field holds on every selected Face, read once per selection and revision: SketchUp
          # asks each menu item in turn, and a read walks the Zones.
          def shared
            key = [@session.revision, Selection.generation(@session).value, @session.model.selection.length]
            return @shared if @shared_key == key

            @shared_key = key
            read = API.query(:context => @context, :name => "#{PREFIX}.selection")
            rows = Array(read.dig("value", "targets")).map { |row| row.fetch("expected_values") }
            # `assembly_id` is listed even when no record has one, so "none assigned" is a shared value too.
            fields = rows.flat_map(&:keys) | %w[assembly_id]
            @shared = fields.select { |field| rows.map { |row| row[field] }.uniq.length == 1 }
                            .to_h { |field| [field, rows.first[field]] }
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
end
