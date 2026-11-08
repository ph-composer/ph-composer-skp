# frozen_string_literal: true

module PhComposer
  # The native commands: the Extensions submenu entry that opens the panel, the Colour by menu built
  # from whatever modes are registered, and the submenus built from whatever menu items are.
  #
  # Nothing here names a feature or carries a feature's words. A feature that wants a native menu
  # declares `menu_item` in its own `install`, and it appears here and in the viewport context menu
  # with no line added below (context/EXTENSIBILITY.md).
  module Commands
    OPEN_PANEL = "Open PH-Composer"
    # SketchUp drops "&" (and "&&") from menu titles, so the menu spells the window's name out.
    HELP = "Help and Diagnostics…"
    COLOUR_BY = "Colour by"
    COLOUR_BY_OFF = "Off"

    class << self
      attr_reader :open_panel, :help, :colour_by_menu, :feature_menus

      def install
        return if @installed

        @open_panel = UI::Command.new(OPEN_PANEL) { Panel.show }
        @open_panel.menu_text = OPEN_PANEL
        @open_panel.tooltip = OPEN_PANEL
        @open_panel.status_bar_text = "Open the PH-Composer panel for the active Model"
        submenu = UI.menu("Extensions").add_submenu(EXTENSION_NAME)
        submenu.add_item(@open_panel)
        install_colour_by(submenu)
        @feature_menus = install_feature_menus(submenu)
        # Needs no Model and no panel, so it is reachable when either is the problem.
        submenu.add_separator
        @help = submenu.add_item(HELP) { SupportDialog.show }
        # The same submenus on a right-click, which is where a modal painting tool is reached from
        # in SketchUp's own grammar. A contextual build asks each item whether it applies to what is
        # there, and a submenu whose items all decline does not appear at all.
        UI.add_context_menu_handler { |menu| install_feature_menus(menu, :contextual => true) }
        @installed = true
      end

      # Built from whatever modes are registered, in registration order, so a feature that declares
      # one reaches this menu without a line here. Turning a mode on writes nothing to the Model, so
      # these are menu items rather than registered actions.
      def install_colour_by(submenu)
        @colour_by_menu = submenu.add_submenu(COLOUR_BY)
        Registry.current.colour_modes.each_value do |mode|
          item = @colour_by_menu.add_item(mode.label) { colour_by { |service| service.activate(mode.name) } }
          @colour_by_menu.set_validation_proc(item) { colour_by_check(mode.name) }
        end
        off = @colour_by_menu.add_item(COLOUR_BY_OFF) { colour_by(&:deactivate) }
        @colour_by_menu.set_validation_proc(off) { colour_by_check(nil) }
        install_readouts
      end

      # Readouts are listed under the modes, each checked while it is on; they are independent of the
      # mode, so choosing one never turns a mode on or off.
      def install_readouts
        readouts = Registry.current.colour_readouts.values
        return if readouts.empty?

        @colour_by_menu.add_separator
        readouts.each do |readout|
          item = @colour_by_menu.add_item(readout.label) do
            colour_by { |service| service.readout(readout.name, :on => !service.readouts_on.include?(readout.name)) }
          end
          @colour_by_menu.set_validation_proc(item) { readout_check(readout.name) }
        end
      end

      # One submenu per declared `menu` name, its items in registration order; a menu named EXTENSION_NAME
      # is no submenu, its items sit directly in the extension's own menu. The right-click menu holds all of
      # it under one PH-Composer submenu, which appears only when something in it applies. The submenu name
      # and every label come from the declaring feature; this groups them and knows nothing else.
      def install_feature_menus(parent, contextual: false)
        session = Sessions.current
        groups = feature_groups(session, contextual)
        return {} if groups.empty?

        root = contextual ? parent.add_submenu(EXTENSION_NAME) : parent
        groups.to_h do |name, entries|
          menu = name == EXTENSION_NAME ? root : root.add_submenu(name)
          add_menu_entries(menu, entries, session)
          [name, menu]
        end
      end

      # Items in the extension's own menu first, then each named submenu, in registration order.
      def feature_groups(session, contextual)
        groups = Registry.current.menu_items.each_value.group_by(&:menu).filter_map do |name, declarations|
          declarations = if contextual
                           declarations.select { |item| available?(item, session) }
                         else
                           declarations.reject(&:entries)
                         end
          entries = declarations.flat_map { |item| menu_entries(item, session) }
          [name, entries] unless entries.empty?
        end
        groups.partition { |name, _entries| name == EXTENSION_NAME }.flatten(1)
      end

      def add_menu_entries(menu, entries, session)
        entries.each do |declaration|
          item = menu.add_item(declaration.label) do
            with_session do |current|
              if declaration.is_a?(Declarations::MenuEntry) && !current.equal?(session)
                raise CodedError.new("session.changed", "The active Model changed. Reopen the context menu.")
              end

              declaration.handler.call(current)
            end
          end
          menu.set_validation_proc(item) { item_check(declaration) } if declaration.state
          menu.add_separator if declaration.separator_after
        end
      end

      # Only the context menu carries entry providers, and it has already tested each one's `available`.
      def menu_entries(item, session)
        return [item] unless item.entries
        return [] unless session

        entries = contributed(item, []) { item.entries.call(read_request(item, session)) }
        unless entries.is_a?(Array) && entries.all? { |entry| valid_menu_entry?(entry) }
          raise InternalError, "#{item.name} returned invalid native menu entries."
        end

        entries
      end

      # A MenuEntry with a label to show, a callable handler, and a callable state when it has one.
      def valid_menu_entry?(entry)
        entry.is_a?(Declarations::MenuEntry) && entry.label.is_a?(String) && !entry.label.strip.empty? &&
          entry.handler.respond_to?(:call) && (entry.state.nil? || entry.state.respond_to?(:call))
      end

      # An item with no `available` is always offered. One that declines is left out of the
      # viewport menu entirely rather than greyed, because a right-click menu is already long.
      def available?(item, session)
        return false unless session
        return true unless item.available

        contributed(item, false) { item.available.call(read_request(item, session)) }
      end

      # A contributor's test or provider that raises costs only its own item: it is logged and left
      # out, so one defect cannot remove every other feature's context menu. The entry shape check
      # above still raises, because an invalid shape is a contract violation the suite must catch.
      def contributed(item, omitted)
        yield
      rescue StandardError => error
        Diagnostics.log("menu_failed", "operation" => item.name, "error_class" => error.class.name)
        omitted
      end

      # Availability tests and entry providers read the Model the way a query handler does, under
      # their owner's declared dependencies, without issuing a caller handle.
      def read_request(item, session)
        HandlerRequest.for(session, :owner => item.owner, :name => item.name)
      end

      def item_check(declaration)
        session = Sessions.current
        session ? declaration.state.call(session) : MF_UNCHECKED
      end

      def with_session
        session = Sessions.current
        return unless session

        yield session
      rescue UserError => error
        session.notice(error.message, :tone => :warning)
      end

      def colour_by
        with_session { |session| yield ColourBy.for(session) }
      end

      def colour_by_check(name)
        session = Sessions.current
        active = session && ColourBy.for(session).mode_name
        active == name ? MF_CHECKED : MF_UNCHECKED
      end

      def readout_check(name)
        session = Sessions.current
        session && ColourBy.for(session).readouts_on.include?(name) ? MF_CHECKED : MF_UNCHECKED
      end

      def reset_for_test
        @installed = false
        @open_panel = nil
        @colour_by_menu = nil
        @feature_menus = nil
      end
    end
  end

  on_reset("commands") { Commands.reset_for_test }
end
