# frozen_string_literal: true

module PhComposer
  module Spaces
    # Set Weighting Factor from SketchUp's context menu, on Floor Segment Faces in an open Volume, on Volumes and on
    # Spaces: a Face sets its own Floor Segment, a Volume each Floor Segment in it, and a Space each Floor Segment in
    # its Volumes. One `floors.mark` writes them all, so the change is one Undo step. The submenu offers 1, then every
    # other factor the Model uses, then Other… for a typed one. A factor is checked only when every Floor Segment the
    # choice would set already has it.
    module WeightingFactorMenu
      MENU = "Set Weighting Factor"
      OTHER = "Other…"
      MARK = "#{FEATURE_ID}.floors.mark"
      # Places a factor shows in its label and in Other…'s field; trailing zeros are dropped.
      DIGITS = 6
      PROMPT = "Weighting factor (0 to 1)"
      SELECT = "Select Floor Segment Faces in an open Volume, or Volumes, or Spaces, then choose Set Weighting " \
               "Factor. #{Outcome::NOTHING_WRITTEN}".freeze
      NO_SEGMENTS = "The selection holds no Floor Segment to set. #{Outcome::NOTHING_WRITTEN}".freeze
      INVALID = "Enter a weighting factor from 0 to 1. #{Outcome::NOTHING_WRITTEN}".freeze

      module_function

      def install(feature)
        feature.menu_entries("#{FEATURE_ID}.weighting_factor_menu", :menu => MENU,
                                                                    :available => ->(read) {
                                                                      !target_paths(read.model).nil?
                                                                    }) do |read|
          entries(read.session)
        end
      end

      # The root-to-entity paths of the selected Spaces, Volumes and Floor Segment Faces, or nil when the selection
      # holds none of them or anything else but Edges. A marked Face is directly inside its Volume, so a selected one
      # is in an open Volume.
      def target_paths(model)
        chosen = model.selection.to_a.reject { |entity| entity.is_a?(Sketchup::Edge) }
        return if chosen.empty? || !chosen.all? { |entity| target?(entity) }

        open = Array(model.active_path).map(&:persistent_id)
        chosen.map { |entity| open + [entity.persistent_id] }
      end

      def target?(entity)
        return FLOOR_SEGMENT_STORE.marks?(entity) if entity.is_a?(Sketchup::Face)

        Protection.volume?(entity) || Navigation.space?(entity)
      end

      # The Floor Segment occurrences at or below the target paths: the ones a choice sets.
      def affected(scan, paths)
        scan.segments.select { |segment| paths.any? { |path| segment.path[0, path.length] == path } }
      end

      # The weighting factors `segments` hold, each once.
      def factors(segments)
        segments.map { |segment| Float(segment.record.fetch("weighting_factor")) }.uniq
      end

      def label(factor)
        Units.format_number(factor, DIGITS, :group_from => nil)
      end

      # 1, every other factor the Model uses from the largest down, then Other…. A record that does not read is
      # left out here; the action refuses it with its reason.
      def entries(session)
        scan = Occurrences.scan(session.model, :strict => false)
        current = factors(affected(scan, target_paths(session.model) || []))
        # Factors that show the same label are one choice.
        choices = ([1.0] + (factors(scan.segments) - [1.0]).sort.reverse).uniq { |factor| label(factor) }
        listed = choices.map do |factor|
          checked = current == [factor] ? MF_CHECKED : MF_UNCHECKED
          Declarations::MenuEntry.new(:label => label(factor), :state => ->(_session) { checked },
                                      :handler => ->(chosen) { client(chosen).apply(factor) })
        end
        listed.last.separator_after = true
        listed << Declarations::MenuEntry.new(:label => OTHER, :handler => ->(chosen) { client(chosen).other })
      end

      def client(session)
        session.feature_state(:spaces_weighting_factor_menu) { Client.new(session) }
      end

      # The native menu's client: the same public action Mark floor and a script use, under its own caller handle.
      class Client
        def initialize(session)
          @session = session
          @context = API.connect(:session_id => session.id)
          @sequence = 0
        end

        def apply(factor)
          segments = selected_segments
          return announce(segments) if segments.is_a?(String)

          invoke(segments, factor, @session.revision)
        end

        # Asks for a factor, showing the one every affected Floor Segment shares. Accepting the shown value unchanged
        # writes nothing, so its rounding never replaces the stored factor.
        def other
          segments = selected_segments
          return announce(segments) if segments.is_a?(String)

          shared = WeightingFactorMenu.factors(segments)
          shown = shared.length == 1 ? WeightingFactorMenu.label(shared.first) : ""
          revision = @session.revision
          entered = UI.inputbox([PROMPT], [shown], MENU)
          return if entered.nil? || HostPrompt.unchanged?(entered.first, shown)

          factor = typed_factor(entered.first)
          return announce(INVALID) unless factor

          invoke(segments, factor, revision)
        end

        private

        # The typed factor, or nil when it is not a number from 0 to 1.
        def typed_factor(text)
          factor = Float(text.to_s.strip, :exception => false)
          factor.zero? ? 0.0 : factor if factor&.between?(0, 1)
        end

        # The Floor Segments the selection names, or the sentence saying why there are none to set.
        def selected_segments
          paths = WeightingFactorMenu.target_paths(@session.model)
          return SELECT unless paths

          # As the menu read them; `floors.mark` refuses a record that does not read, with its reason.
          segments = WeightingFactorMenu.affected(Occurrences.scan(@session.model, :strict => false), paths)
          return NO_SEGMENTS if segments.empty?

          limit = Spaces.floor_gesture_limit
          return segments if segments.length <= limit

          "Set Weighting Factor sets at most #{limit} Floor Segments at once; the selection holds " \
            "#{segments.length}. #{Outcome::NOTHING_WRITTEN}"
        rescue CodedError => error
          error.message
        end

        def invoke(segments, factor, revision)
          @sequence += 1
          outcome = API.invoke(:context => @context, :name => MARK,
                               :params => { "faces" => segments.map(&:path), "weighting_factor" => factor },
                               :request => { "sequence" => @sequence, "expected_revision" => revision })
          if outcome.fetch("status") == "completed"
            announce(set(segments.length, WeightingFactorMenu.label(factor), outcome["effect"] == "none"), :success)
          else
            announce(HostNotice.words(outcome), HostNotice.tone(outcome))
          end
          outcome
        end

        # What a completed choice says; one that matched every stored factor changed nothing.
        def set(count, shown, unchanged)
          segments = count == 1 ? "Floor Segment" : "Floor Segments"
          return "The #{segments} already had weighting factor #{shown}. Nothing changed." if unchanged

          "Set the weighting factor of #{count} #{segments} to #{shown}."
        end

        def announce(message, tone = :warning)
          HostNotice.show(@session, message, :tone => tone)
          nil
        end
      end
    end
  end
end
