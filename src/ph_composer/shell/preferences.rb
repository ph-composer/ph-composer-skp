# frozen_string_literal: true

require "json"
require "open3"

module PhComposer
  # User-wide display preferences: local to this computer, shared by every panel and open Model,
  # restored after restart. They live in SketchUp's own preference store, so choosing one never
  # dirties an SKP, adds an Undo step or advances a session revision.
  #
  # A dimension scope is one editor's remembered length format, such as a graphical builder's. The panel
  # names the scope; a scope is a dotted name under the owning feature's id, like every declared name.
  # A table view is the view a host table last showed (html/table_views.js), keyed the same way by the
  # host's id.
  #
  # A write counts only when the host reports success and reads the value back. A stored map this
  # version cannot read, whether damaged or written by a later version, is refused rather than replaced:
  # the user's other remembered choices are not discarded to record one new one.
  module Preferences
    SECTION = EXTENSION_ID
    UNIT_SYSTEMS = %w[SI IP].freeze
    DEFAULT_UNIT_SYSTEM = "SI"
    DIMENSION_FORMATS = { "SI" => %w[mm cm m].freeze, "IP" => %w[in ft ft-in in-frac].freeze }.freeze
    # Keep in step with `units.dimensionDefaults` in html/units.js: the panel picks a format before the
    # first snapshot arrives, so the two defaults must agree.
    DEFAULT_DIMENSION_FORMAT = { "SI" => "mm", "IP" => "in" }.freeze
    # Remembered scopes are few; the cap stops a misbehaving client from growing the stored map without bound.
    MAX_SCOPES = 32
    MAX_STORED_BYTES = 4096
    # The largest encoded map the readers accept: the JSON's byte cap, as base64 with headroom.
    MAX_ENCODED_BYTES = MAX_STORED_BYTES * 2
    # What `read_default` answers for a key never stored. The host reads a stored value it cannot return,
    # such as a string holding a double quote, as nil, so nil means present but unreadable.
    ABSENT = ""
    UNREADABLE = "Your saved display preferences could not be read, so they were left unchanged."
    # What Reset display preferences returns to its default, in the words its confirmation lists. Libraries,
    # approved locations and agent tokens live in their own stores and are never reset here.
    RESETTABLE = [
      "Display units (back to SI)", "Remembered dimension formats", "Remembered table views",
      "The remembered Colour-by mode"
    ].freeze

    class << self
      def unit_system
        stored = Sketchup.read_default(SECTION, "unit_system", DEFAULT_UNIT_SYSTEM)
        UNIT_SYSTEMS.include?(stored) ? stored : DEFAULT_UNIT_SYSTEM
      end

      # The Colour-by mode the user last turned on, or nil. Colour-by itself is off at rest; only the
      # choice is remembered.
      def colour_by_mode
        stored = Sketchup.read_default(SECTION, "colour_by_mode", nil)
        valid_id?(stored) ? stored : nil
      end

      # The view each host table last showed, by host id; a host never switched is absent and shows its first.
      def table_views
        read_map("table_views") do |host, view|
          valid_id?(host.to_s) && valid_id?(view)
        end
      end

      # Every remembered scope's format per system; a scope never chosen is absent and takes the default.
      def dimension_formats
        raw = Sketchup.read_default(SECTION, "dimension_formats", nil)
        return {} unless raw.is_a?(String) && raw.bytesize <= MAX_ENCODED_BYTES

        sanitize(JSON.parse(raw.unpack1("m0")))
      rescue StandardError
        {}
      end

      # Records one preference or raises UserError with the reason. Writes nothing else.
      def set(key, value, scope: nil, system: nil)
        case key
        when "unit_system"
          raise UserError, "Display units must be SI or IP." unless UNIT_SYSTEMS.include?(value)

          write(:unit_system, value)
          units_changed
        when "dimension_format"
          write_dimension_format(value, scope, system)
        when "table_view"
          write_table_view(value, scope)
        when "colour_by_mode"
          raise UserError, "That Colour-by mode name is not valid." unless valid_id?(value)

          write(:colour_by_mode, value)
        else
          raise UserError, "That display preference is not recognized."
        end
        value
      end

      # Writes every display preference's default and reads each back, including a stored map this version
      # could not read: resetting is the way out of one. Raises UserError when the host refuses a write.
      def reset_display
        write(:unit_system, DEFAULT_UNIT_SYSTEM)
        units_changed
        write_map("dimension_formats", {})
        write_map("table_views", {})
        write(:colour_by_mode, "")
        RESETTABLE
      end

      # Runs `block` after each saved display units write, from the panel or from Reset display preferences,
      # and answers a lambda that unsubscribes it. A viewport that formats quantities as it draws, such as the
      # Colour-by legend, repaints from here; nothing about a Model changes. A subscriber that raises is logged
      # and the change stands.
      def on_units_change(&block)
        raise ArgumentError, "A display units subscriber block is required." unless block

        units_subscribers << block
        -> { units_subscribers.delete(block) }
      end

      def snapshot
        { "unit_system" => unit_system, "dimension_formats" => dimension_formats, "number_format" => number_format,
          "table_views" => table_views }
      end

      def reset_for_test
        @units_subscribers = nil
        @number_format = nil
        @apple_locale_reader = nil
      end

      attr_writer :apple_locale_reader

      private

      def units_subscribers
        @units_subscribers ||= []
      end

      def units_changed
        units_subscribers.dup.each do |subscriber|
          subscriber.call
        rescue StandardError => error
          Diagnostics.exception("preferences_subscriber", error)
        end
      end

      # A dotted lowercase name, as registered names are.
      def valid_id?(value)
        value.is_a?(String) && Registry::ID_PATTERN.match?(value)
      end

      def write_dimension_format(value, scope, system)
        raise UserError, "Choose SI or IP for the dimension format." unless UNIT_SYSTEMS.include?(system)
        raise UserError, "The dimension scope name is not valid." unless valid_id?(scope)
        raise UserError, "Choose a valid #{system} dimension format." unless DIMENSION_FORMATS[system].include?(value)

        formats = stored_map("dimension_formats")
        if !formats.key?(scope) && formats.length >= MAX_SCOPES
          raise UserError, "Too many dimension formats are remembered."
        end

        remembered = formats.fetch(scope, {})
        raise UserError, UNREADABLE unless remembered.is_a?(Hash)

        formats[scope] = DEFAULT_DIMENSION_FORMAT.merge(remembered).merge(system => value)
        write_map("dimension_formats", formats)
      end

      def write_table_view(value, scope)
        raise UserError, "The table name is not valid." unless valid_id?(scope)
        raise UserError, "The view name is not valid." unless valid_id?(value)

        views = stored_map("table_views")
        raise UserError, "Too many table views are remembered." if !views.key?(scope) && views.length >= MAX_SCOPES

        views[scope] = value
        write_map("table_views", views)
      end

      # The map as stored, entries this version does not recognize included, so that changing one entry
      # keeps the rest. Absent is empty; present but unreadable refuses the change.
      def stored_map(key)
        raw = Sketchup.read_default(SECTION, key, ABSENT)
        return {} if raw == ABSENT

        parsed = raw.is_a?(String) && raw.bytesize <= MAX_ENCODED_BYTES ? decode_map(raw) : nil
        return parsed if parsed.is_a?(Hash)

        raise UserError, UNREADABLE
      end

      def decode_map(raw)
        JSON.parse(raw.unpack1("m0"))
      rescue StandardError
        nil
      end

      # SketchUp 26.1 stores a string containing a double quote but reads it back as nil, so the JSON
      # is kept as strict base64 (context/SKETCHUP_HOST_BEHAVIOR.md).
      # A map the readers would refuse or cut short is not written, so a saved choice is always one they show.
      def write_map(key, map)
        encoded = [JSON.generate(map)].pack("m0")
        if map.length > MAX_SCOPES || encoded.bytesize > MAX_ENCODED_BYTES
          raise UserError, "Too many display preferences are remembered."
        end

        write(key, encoded)
      end

      # `write_default` answers false when it did not store the value; reading it back catches the rest.
      def write(key, value)
        key = key.to_s
        return if Sketchup.write_default(SECTION, key, value) && Sketchup.read_default(SECTION, key, nil) == value

        raise UserError, "PH-Composer could not save that display preference."
      end

      # A map stored as strict base64 JSON, keeping only the pairs `keep` accepts, at most MAX_SCOPES.
      def read_map(key, &keep)
        raw = Sketchup.read_default(SECTION, key, nil)
        return {} unless raw.is_a?(String) && raw.bytesize <= MAX_ENCODED_BYTES

        parsed = JSON.parse(raw.unpack1("m0"))
        return {} unless parsed.is_a?(Hash)

        parsed.select(&keep).first(MAX_SCOPES).to_h
      rescue StandardError
        {}
      end

      def sanitize(parsed)
        return {} unless parsed.is_a?(Hash)

        parsed.each_with_object({}) do |(scope, formats), result|
          next unless Registry::ID_PATTERN.match?(scope.to_s) && formats.is_a?(Hash)
          break result if result.length >= MAX_SCOPES

          result[scope] = UNIT_SYSTEMS.to_h do |system|
            stored = formats[system]
            [system, DIMENSION_FORMATS[system].include?(stored) ? stored : DEFAULT_DIMENSION_FORMAT[system]]
          end
        end
      end

      # The computer's regional convention for typed and displayed numbers. Stored values and JSON
      # never use it.
      def number_format
        @number_format ||= {
          "decimal" => Sketchup::RegionalSettings.decimal_separator.to_s,
          "locale" => resolved_locale
        }.freeze
      end

      def resolved_locale
        locale = apple_locale
        locale = Sketchup.get_locale if locale.nil? || locale.empty?
        normalize_locale(locale) || "en-US"
      rescue StandardError
        normalize_locale(Sketchup.get_locale) || "en-US"
      end

      # macOS keeps the region the user chose in AppleLocale; SketchUp's own locale is its UI language.
      # Elsewhere, or when the read fails, SketchUp's locale stands.
      def apple_locale
        return @apple_locale_reader.call if @apple_locale_reader

        output, _error, status = Open3.capture3("/usr/bin/defaults", "read", "-g", "AppleLocale")
        status.success? ? output.to_s.lines.first.to_s.strip : nil
      rescue StandardError
        nil
      end

      def normalize_locale(value)
        raw = value.to_s.strip
        return nil if raw.empty?

        base, modifiers = raw.split("@", 2)
        parts = base.split(".", 2).first.to_s.tr("_", "-").split("-").reject(&:empty?)
        return nil if parts.empty?

        parts[0] = parts[0].downcase
        parts[1..-1] = parts[1..-1].map { |part| normalize_subtag(part) }
        apply_region_override(parts, modifiers).join("-")
      end

      def normalize_subtag(part)
        if part.match?(/\A[A-Za-z]{2}\z/) || part.match?(/\A\d{3}\z/)
          part.upcase
        elsif part.match?(/\A[A-Za-z]{4}\z/)
          part[0].upcase + part[1..-1].downcase
        else
          part
        end
      end

      # macOS writes a separately chosen region as "@rg=dezzzz"; it replaces the language's region.
      def apply_region_override(parts, modifiers)
        override = modifiers.to_s[/\A(?:.*;)?rg=([A-Za-z]{2}|\d{3})[A-Za-z]{4}(?:;.*)?\z/, 1]
        return parts unless override

        region_index = parts.index { |part| part.match?(/\A(?:[A-Z]{2}|\d{3})\z/) }
        if region_index
          parts[region_index] = override.upcase
        else
          parts << override.upcase
        end
        parts
      end
    end
  end

  on_reset("preferences") { Preferences.reset_for_test }
end
