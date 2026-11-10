# frozen_string_literal: true

module PhComposer
  # Prompts for SketchUp's `UI.inputbox`, shared by every native route that asks for a value.
  module HostPrompt
    # Widens a prompt whose last word must show: UI.inputbox on macOS otherwise wraps it out of sight
    # (context/SKETCHUP_HOST_BEHAVIOR.md, "Saving, dialogs and the panel").
    PADDING = " " * 16

    module_function

    # A measured value's prompt: its label and the display unit it is entered in, as "Supply (cfm)".
    def measured(label, quantity:, system:)
      "#{label} (#{Units.label(:quantity => quantity, :system => system)})#{PADDING}"
    end

    # Whether a field's text, stripped, is what the dialog showed, or the same number written another way ("35.30"
    # for "35.3"). A shown number is rounded, so a field left as shown must write nothing back.
    def unchanged?(text, shown)
      entered = text.to_s.strip
      return true if entered == shown

      number = Float(entered, :exception => false)
      !number.nil? && number == Float(shown, :exception => false)
    end
  end
end
