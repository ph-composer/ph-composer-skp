# frozen_string_literal: true

module PhComposer
  module Shading
    # Set as Shading and Clear Shading, directly in the PH-Composer menu. Each item is offered on a right-click
    # when the selection query says its action would change something, and always in Extensions > PH-Composer.
    # The handler is a client of the same actions a script uses: it reads the selection's references and the
    # revision, invokes assign or clear, and reports what changed and what was left out. It writes no record.
    module Menu
      SELECTION = "#{FEATURE_ID}.selection"

      module_function

      def install(feature)
        feature.menu_item("#{FEATURE_ID}.assign_menu", :label => "Set as Shading", :menu => EXTENSION_NAME,
                                                       :available => ->(read) { offered?(read, "assign") }) do |session|
          client(session).assign
        end
        feature.menu_item("#{FEATURE_ID}.clear_menu", :label => "Clear Shading", :menu => EXTENSION_NAME,
                                                      :available => ->(read) { offered?(read, "clear") }) do |session|
          client(session).clear
        end
      end

      # Set as Shading when assign would mark something; Clear Shading when the selection holds a marked entity.
      # A selection over the target limit offers both, so the handler can say why nothing was written rather
      # than the items vanishing.
      def offered?(read, action)
        rows = read.query(SELECTION).fetch("entities")
        return rows.any? { |row| row.fetch("marked") } if action == "clear"

        rows.any? { |row| row.dig("assign", "outcome") == "assigned" }
      rescue CodedError => error
        raise unless error.code == "gesture.too_large"

        true
      end

      def client(session)
        session.feature_state(:shading_menu) { Client.new(session) }
      end

      # One per session: a long-lived API context and its request sequence, as Zones' menu client keeps.
      class Client
        ACTIONS = {
          "assign" => { :done => "assigned", :verb => "Set as Shading", :changed => "Tagged %s as shading.",
                        :unchanged => "%s already shading." },
          "clear" => { :done => "cleared", :verb => "Clear Shading", :changed => "Cleared shading from %s.",
                       :unchanged => "%s not shading." }
        }.freeze

        def initialize(session)
          @session = session
          @context = API.connect(:session_id => session.id)
          @sequence = 0
        end

        def assign
          run("assign")
        end

        def clear
          run("clear")
        end

        private

        def run(action)
          read = API.query(:context => @context, :name => SELECTION, :params => {})
          return show(read.fetch("message"), false, read) unless read["status"] == "completed"

          selection = read.fetch("value")
          rows = selection.fetch("entities")
          if rows.empty?
            message = "Select Faces, Groups or components first. Nothing was written."
            return show(message, false, "status" => "refused", "message" => message)
          end

          @sequence += 1
          result = API.invoke(:context => @context, :name => "#{FEATURE_ID}.#{action}",
                              :params => { "targets" => rows.map { |row| row.fetch("reference") } },
                              :request => { "sequence" => @sequence, "expected_revision" => read.fetch("revision") })
          return show(refusal(action, result, selection), false, result) unless result["status"] == "completed"

          value = result.fetch("value")
          still = action == "clear" ? still_shading(value.fetch("cleared")) : []
          message = [summary(action, value, selection), *still].join(" ")
          show(message, value.fetch("left_out").empty? && still.empty?, result)
        end

        # A cleared entity can still be shading through a marked container above it. Read the selection again,
        # after the clear, and name each such container, as clearing an inherited Face would.
        def still_shading(cleared)
          return [] if cleared.empty?

          read = API.query(:context => @context, :name => SELECTION, :params => {})
          return [] unless read["status"] == "completed"

          references = cleared.map { |row| row.fetch("entity_path") }
          rows = read.dig("value", "entities").select do |row|
            references.include?(row.dig("reference", "entity_path")) && row.dig("clear", "code") == "shading.inherited"
          end
          rows.map { |row| "Still shading: #{row.dig('clear', 'message')}" }.uniq
        end

        # What changed, what was already so, what was left out with its reasons, and what was ignored.
        def summary(action, value, selection)
          words = ACTIONS.fetch(action)
          parts = []
          done = value.fetch(words.fetch(:done)).length
          parts << format(words.fetch(:changed), count(done)) if done.positive?
          unchanged = value.fetch("unchanged").length
          parts << format(words.fetch(:unchanged), "#{count(unchanged)} #{unchanged == 1 ? 'was' : 'were'}") \
            if unchanged.positive?
          left_out = value.fetch("left_out")
          parts << left_out_sentence(left_out) unless left_out.empty?
          parts << ignored_sentence(selection)
          "#{words.fetch(:verb)}: #{parts.compact.join(' ')}"
        end

        # A command refused because every target was left out carries them all in its detail: name each reason.
        # Any other refusal (a stale revision, a moved entity) is the action's own message.
        def refusal(action, result, selection)
          left_out = result.dig("detail", "left_out")
          return [result.fetch("message"), ignored_sentence(selection)].compact.join(" ") unless left_out

          parts = ["Nothing was written.", left_out_sentence(left_out), ignored_sentence(selection)]
          "#{ACTIONS.fetch(action).fetch(:verb)}: #{parts.compact.join(' ')}"
        end

        def ignored_sentence(selection)
          ignored = selection.fetch("ignored_total")
          return nil unless ignored.positive?

          "#{ignored} other selected #{ignored == 1 ? 'entity was' : 'entities were'} ignored."
        end

        # Left out N: every distinct reason once, with how many it covers. A reason that names its container
        # (shading.inherited) is distinct per container. The selection limit bounds the rows.
        def left_out_sentence(rows)
          reasons = rows.group_by { |row| row.fetch("message") }.map do |message, group|
            group.length == 1 ? message : "#{group.length} of them: #{message}"
          end
          "Left out #{count(rows.length)}. #{reasons.join(' ')}"
        end

        def count(number)
          "#{number} #{number == 1 ? 'entity' : 'entities'}"
        end

        # The notice is a success only when everything selected was handled; the result goes back to the caller.
        def show(message, success, result)
          @session.notice(message, :tone => success ? :success : :warning)
          Sketchup.status_text = message
          result
        end
      end
    end
  end
end
