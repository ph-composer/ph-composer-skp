# frozen_string_literal: true

module PhComposer
  module Piping
    # The pipe tool's public face: its state, read by the Piping pill's assign bar, the two view commands that arm and
    # stop it, and their native menu items. Neither command changes a record, so neither is an action; each gesture
    # the tool completes is one `pipes.assign`, the route's explicit-reference equivalent.
    module PipeToolRegistration
      PREFIX = "#{FEATURE_ID}.pipe_tool".freeze
      MENU = "Hot water piping"
      ARM_LABEL = "Assign pipes by clicking"
      STOP_LABEL = "Stop assigning pipes by clicking"
      CHOOSE_REFUSES = %w[record.unreadable target.not_found validation.failed].freeze
      ROLE_KEYS = Assignment::ROLE_SCHEMAS.keys.freeze
      STATE = Shapes.object({
        "active" => { "type" => "boolean", "description" => "Whether the pipe tool has the viewport." },
        "pipe_type_id" => { "type" => %w[string null],
                            "description" => "The Pipe Type the tool assigns, or null before one is chosen." },
        "role" => { "type" => "string", "enum" => Assignment::ROLES, "description" => "The role it assigns." },
        "values" => Shapes.described(Shapes::OBJECT, "The role's values it sets; one not given keeps an Edge's own " \
                                                     "or takes its default, as pipes.assign does."),
        "gesture_limit" => { "type" => "integer", "minimum" => 0,
                             "description" => "The most Edges one gesture may assign." }
      }).freeze
      CHOOSE_PARAMS = Shapes.object({
        "pipe_type_id" => Shapes.id(PipeType::KIND.id_prefix, "The Pipe Type to assign by clicking."),
        "role" => { "type" => "string", "enum" => Assignment::ROLES,
                    "description" => "trunk, branch, twig or recirculation; values of another role refuse as " \
                                     "params.invalid." }
      }.merge(Assignment::ROLE_SCHEMAS), :optional => ROLE_KEYS).freeze

      module_function

      def install(feature)
        feature.query("#{PREFIX}.state",
                      :description => "The pipe tool: whether it has the viewport, and the type, role and values it " \
                                      "assigns.",
                      :refuses => [], :params => Shapes::NONE, :result => STATE, :examples => [{}]) do |request|
          state(request.session)
        end
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.state")
        install_commands(feature)
        install_menus(feature)
      end

      def install_commands(feature)
        feature.view_command("#{PREFIX}.choose",
                             :description => "Arm the pipe tool with a Pipe Type, a role and the role's values and " \
                                             "give it the viewport: each click or drag across lines in a Piping " \
                                             "group is one pipes.assign.",
                             :refuses => CHOOSE_REFUSES, :params => CHOOSE_PARAMS, :result => STATE,
                             :preconditions => ["The Pipe Type exists and is readable."],
                             :side_effects => "Gives the viewport to the pipe tool and turns on Colour by pipe role " \
                                              "until it stops; a choice while it runs re-arms it for the next gesture.",
                             :examples => [{ "pipe_type_id" => Shapes.example_id(PipeType::KIND), "role" => "branch" },
                                           { "pipe_type_id" => Shapes.example_id(PipeType::KIND), "role" => "trunk",
                                             "multiplier" => 12 }]) do |request|
          choose(request)
        end
        feature.view_command("#{PREFIX}.stop",
                             :description => "Give the viewport back to whatever tool the user had.",
                             :refuses => [], :params => Shapes::NONE, :result => STATE,
                             :side_effects => "Abandons a pending gesture and puts back the Colour-by mode from " \
                                              "before the tool, unless another was chosen meanwhile.",
                             :examples => [{}]) do |request|
          Piping.pipe_tool(request.session).stop
          state(request.session)
        end
      end

      def choose(request)
        params = request.params
        role = params.fetch("role")
        values = params.slice(*ROLE_KEYS)
        extra = values.keys - Assignment::ROLE_VALUES.fetch(role).keys
        raise CodedError.new("params.invalid", "A #{role} pipe does not take #{extra.join(', ')}.") unless extra.empty?

        id = params.fetch("pipe_type_id")
        request.engine.find(PIPE_TYPE_KIND, id)
        Piping.pipe_tool(request.session).choose(id, role, values)
        state(request.session)
      end

      # Under the extension's menu and the right-click "Hot water piping" submenu: arming again with the type, role
      # and values the bar last armed it with, while it is stopped, and Stop while it runs.
      def install_menus(feature)
        feature.menu_item("#{PREFIX}.arm_menu", :label => ARM_LABEL, :menu => MENU,
                                                :available => ->(read) { armed_stopped?(read.session) }) do |session|
          rearm(session)
        end
        active = ->(read) { Piping.pipe_tool(read.session).active? }
        feature.menu_item("#{PREFIX}.stop_menu", :label => STOP_LABEL, :menu => MENU, :available => active) do |session|
          Piping.pipe_tool(session).stop
        end
      end

      def armed_stopped?(session)
        tool = Piping.pipe_tool(session)
        !tool.active? && !tool.pipe_type_id.nil?
      end

      # A menu handler is a client: it arms the tool through one long-lived context per session, and shows a refusal
      # (the type deleted since) rather than doing nothing.
      def rearm(session)
        tool = Piping.pipe_tool(session)
        params = { "pipe_type_id" => tool.pipe_type_id, "role" => tool.role }.merge(tool.values)
        result = API.view(:context => context(session), :name => "#{PREFIX}.choose", :params => params)
        return result if result.fetch("status") == "completed"

        Sketchup.status_text = result.fetch("message")
        session.notice(result.fetch("message"), :tone => :warning)
        result
      end

      def state(session)
        Piping.pipe_tool(session).state.merge("gesture_limit" => Assignment.gesture_edge_limit)
      end

      def context(session)
        session.feature_state(:piping_menu_context) { API.connect(:session_id => session.id) }
      end
    end
  end
end
