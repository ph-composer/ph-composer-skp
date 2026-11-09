# frozen_string_literal: true

module PhComposer
  module Windows
    module Units
      # Convert to Window Type from SketchUp's menus: offered on any Face selection, it hands the panel a
      # review of what `units.convert_review` takes and leaves out, so a mixed selection reaches the review
      # whole. The panel confirms with `units.convert`; the route itself writes nothing.
      module ConvertRoute
        LABEL = "Convert to Window Type…"
        REVIEW_QUERY = "#{FEATURE_ID}.units.convert_review".freeze
        PREFIX = "#{FEATURE_ID}.convert_dialog".freeze
        NO_FACES = "Select the drawn rectangles as Faces, then choose Convert to Window Type. " \
                   "#{Outcome::NOTHING_WRITTEN}".freeze

        module_function

        # A cheap structural test for the context menu, which asks on every right-click.
        def available?(session)
          session.model.selection.to_a.any? { |entity| entity.is_a?(Sketchup::Face) }
        end

        def dialog(session)
          session.feature_state(:windows_convert_dialog) { Dialog.new }
        end

        def client(session)
          session.feature_state(:windows_convert_menu) { Client.new(session) }
        end

        # A new review replaces one still open, so a review the panel never closed cannot hold the route shut.
        def open(request, paths)
          read = request.query(REVIEW_QUERY, "paths" => paths)
          dialog(request.session).open(read, request.revision)
          request.session.changed(:windows, :convert_dialog)
          dialog(request.session).snapshot
        end

        # The review the panel shows: a token per opening, the revision `convert` must be applied at, and
        # what the review query answered.
        class Dialog
          def initialize
            clear
          end

          def open(read, revision)
            @value = { "token" => SecureRandom.uuid, "revision" => revision,
                       "groups" => DeepCopy.call(read.fetch("groups")),
                       "left_out" => DeepCopy.call(read.fetch("left_out")) }
          end

          def snapshot
            DeepCopy.call(@value)
          end

          def close(token)
            clear if @value.fetch("token") == token
            snapshot
          end

          def clear
            @value = { "token" => nil, "revision" => nil, "groups" => [], "left_out" => [] }
          end

          def detach
            clear
          end
        end

        # The native menu's client: the same public view command a script uses.
        class Client
          def initialize(session)
            @session = session
            @context = API.connect(:session_id => session.id)
          end

          def run
            paths = face_paths
            return announce(NO_FACES) if paths.empty?
            if paths.length > Pages::MAXIMUM_LIMIT
              return announce("Convert to Window Type takes at most #{Pages::MAXIMUM_LIMIT} Faces at once. " \
                              "#{Outcome::NOTHING_WRITTEN}")
            end

            result = API.view(:context => @context, :name => "#{PREFIX}.open", :params => { "paths" => paths })
            return refuse(result) unless result.fetch("status") == "completed"

            Commands.open_panel.proc.call
            result
          end

          private

          # Root-to-Face paths for the selected Faces, which all sit in the open context.
          def face_paths
            active = Array(@session.model.active_path).map(&:persistent_id)
            @session.model.selection.to_a.grep(Sketchup::Face).map { |face| active + [face.persistent_id] }
          end

          def announce(message, tone = :warning)
            HostNotice.show(@session, message, :tone => tone)
            nil
          end

          def refuse(outcome)
            announce(HostNotice.words(outcome), HostNotice.tone(outcome))
          end
        end
      end
    end
  end
end
