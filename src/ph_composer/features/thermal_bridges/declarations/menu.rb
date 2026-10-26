# frozen_string_literal: true

module PhComposer
  module ThermalBridges
    # The right-click route: "Thermal bridge" on a selection holding an Edge a write can reach, with one item
    # per Thermal Bridge Type and, when a selected Edge has an assignment (an invalid one included), Clear. Each
    # item reads the selection again through the selection client, so a selection changed since the menu
    # opened refuses rather than writing.
    module MenuRegistration
      MENU = "Thermal bridge"
      CLEAR = "Clear thermal bridge"

      module_function

      def install(feature)
        feature.menu_entries("#{FEATURE_ID}.assign_menu", :menu => MENU,
                                                          :available => ->(read) { !assignable(read).empty? }) do |read|
          entries(read)
        end
      end

      def entries(read)
        types = read.query("#{TypeRegistration::PREFIX}.all").fetch("records")
                    .sort_by { |row| [row.dig("values", "name").downcase, row.fetch("id")] }
        items = types.map do |row|
          id = row.fetch("id")
          Declarations::MenuEntry.new(:label => row.dig("values", "name"),
                                      :handler => ->(session) { Assignment::Selection.client(session).assign(id) })
        end
        return items unless assignable(read).any? { |row| assigned?(row) }

        items.last.separator_after = true unless items.empty?
        items << Declarations::MenuEntry.new(:label => CLEAR,
                                             :handler => ->(session) { Assignment::Selection.client(session).clear })
      end

      # An invalid assignment reads with empty values and its problem; Clear is how it goes.
      def assigned?(row)
        !row.fetch("values").empty? || !row["record_problem"].nil?
      end

      # The selected Edges a write can reach. More Edges than one gesture takes offers no menu; the panel's
      # assign bar says why. Any other refusal raises, so the shell logs it and leaves the menu out.
      def assignable(read)
        read.query("#{AssignmentRegistration::PREFIX}.selection_all").fetch("edges")
            .select { |row| Assignment::Selection.assignable?(row) }
      rescue CodedError => error
        raise unless error.code == "gesture.too_large"

        []
      end
    end
  end
end
