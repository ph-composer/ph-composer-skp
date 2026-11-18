# frozen_string_literal: true

module PhComposer
  module Climate
    module Folders
      # Climate's section of this computer's settings file (ComputerSettings): the climate data folders as rows
      # `{ id, name, location }`, where location is the folder's absolute path, and `last_dataset_id`, the folder
      # the station picker opens on. The section is validated on every read; one that fails reads as unreadable
      # and is never replaced. Only this module and the folder commands' handlers see a location.
      module Store
        SECTION = FEATURE_ID
        ID_PREFIX = "climate_folder"
        MAX_NAME_LENGTH = 120
        MAX_LOCATION_BYTES = 1024
        EMPTY = { "folders" => [], "last_dataset_id" => nil }.freeze
        UNREADABLE = "climate.settings_unreadable"
        UNAVAILABLE = "climate.settings_unavailable"
        SECTION_UNREADABLE = "PH-Composer's climate data settings on this computer could not be read. They were " \
                             "left as stored."

        module_function

        # The section as `{ "folders" => [...], "last_dataset_id" => id or nil }`. Raises CodedError
        # climate.settings_unreadable or climate.settings_unavailable. Never creates the file.
        def read
          valid_section(ComputerSettings.read(SECTION))
        rescue ComputerSettings::Refused => error
          raise coded(error), :cause => nil
        end

        # "readable", "unreadable" or "unavailable", never raising.
        def state
          read
          "readable"
        rescue CodedError => error
          error.code == UNAVAILABLE ? "unavailable" : "unreadable"
        end

        # Changes the section: the block receives the current section, validated, and returns the new one, which
        # is validated before it is written. Answers the new section.
        def update
          written = ComputerSettings.write(SECTION) do |stored|
            section = yield(valid_section(stored))
            unless valid?(section)
              raise InternalError, "A climate data folder change would store an invalid section."
            end

            section
          end
          valid_section(written)
        rescue ComputerSettings::Refused => error
          raise coded(error), :cause => nil
        end

        def mint_id(folders)
          Records::Identity.fresh(ID_PREFIX, folders.map { |row| row.fetch("id") })
        end

        # A last_dataset_id naming no listed folder reads as none: it was removed by an older build or by hand.
        def valid_section(stored)
          section = stored == {} ? EMPTY : stored
          raise CodedError.new(UNREADABLE, SECTION_UNREADABLE) unless valid?(section)

          ids = section.fetch("folders").map { |row| row.fetch("id") }
          last = section.fetch("last_dataset_id")
          { "folders" => section.fetch("folders"), "last_dataset_id" => ids.include?(last) ? last : nil }
        end

        def valid?(section)
          return false unless section.is_a?(Hash) && section.keys.sort == EMPTY.keys.sort

          folders = section.fetch("folders")
          last = section.fetch("last_dataset_id")
          folders.is_a?(Array) && folders.all? { |row| valid_row?(row) } &&
            folders.map { |row| row.fetch("id") }.uniq.length == folders.length && (last.nil? || last.is_a?(String))
        end

        def valid_row?(row)
          return false unless row.is_a?(Hash) && row.keys.sort == %w[id location name]

          id, name, location = row.values_at("id", "name", "location")
          [id, name, location].all? { |value| value.is_a?(String) } &&
            Records::Identity.pattern(ID_PREFIX).match?(id) && valid_name?(name) &&
            location.start_with?("/") && location.bytesize <= MAX_LOCATION_BYTES
        end

        def valid_name?(name)
          name.is_a?(String) && !name.strip.empty? && name.length <= MAX_NAME_LENGTH
        end

        def coded(refused)
          code = %i[unreadable later_version].include?(refused.reason) ? UNREADABLE : UNAVAILABLE
          CodedError.new(code, refused.message)
        end
        private_class_method :valid_section, :valid?, :valid_row?, :coded
      end
    end
  end
end
