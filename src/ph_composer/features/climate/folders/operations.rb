# frozen_string_literal: true

module PhComposer
  module Climate
    module Folders
      # The climate data folders on this computer: list, add, rename, locate, remove and the dataset the picker
      # last used, each a change to Climate's section of the settings file and never to a Model. A folder the
      # user chose arrives as a path from the folder chooser and goes no further than the section: every
      # answer carries the display location instead. A folder that cannot be found keeps its row; only the
      # user removes it, since it may be on a drive that is not connected.
      module Operations
        NOT_FOUND = "climate.folder_not_found"
        OVERLAPS = "climate.folder_overlaps"
        UNKNOWN = "No climate data folder with that id is set up on this computer. Nothing was written."
        DEFAULT_NAME = "Climate data"

        module_function

        # Every folder as the public row, in the order added, and the dataset the picker last used.
        def list
          section = Store.read
          { "folders" => section.fetch("folders").map { |row| public_row(row) },
            "last_dataset_id" => section.fetch("last_dataset_id") }
        end

        # Stores the folder the user chose under its own name and answers the new row. The panel then opens
        # the name for editing.
        def add(path)
          location = chosen_folder(path)
          section = Store.update do |current|
            refuse_overlap(current.fetch("folders"), location)
            row = { "id" => Store.mint_id(current.fetch("folders")), "name" => default_name(location),
                    "location" => location }
            current.merge("folders" => current.fetch("folders") + [row])
          end
          public_row(section.fetch("folders").last)
        end

        def rename(id, name)
          name = name.to_s.strip
          unless Store.valid_name?(name)
            raise CodedError.new("params.invalid", "A dataset name is 1 to #{Store::MAX_NAME_LENGTH} characters. " \
                                                   "Nothing was written.")
          end

          change_row(id) { |row| row.merge("name" => name) }
        end

        # Points an existing setting at the folder the user chose, keeping its id and name.
        def locate(id, path)
          location = chosen_folder(path)
          change_row(id) do |row, folders|
            refuse_overlap(folders.reject { |other| other.fetch("id") == id }, location)
            row.merge("location" => location)
          end
        end

        def remove(id)
          section = Store.update do |current|
            folders = current.fetch("folders")
            find!(folders, id)
            last = current.fetch("last_dataset_id")
            { "folders" => folders.reject { |row| row.fetch("id") == id },
              "last_dataset_id" => last == id ? nil : last }
          end
          listed(section)
        end

        def remember_dataset(id)
          section = Store.update do |current|
            find!(current.fetch("folders"), id)
            current.merge("last_dataset_id" => id)
          end
          listed(section)
        end

        # Refuses climate.folder_not_found unless a folder with `id` is set up. A command's precondition, so
        # Locate's chooser never opens for a setting that is not there.
        def require_folder(id)
          find!(Store.read.fetch("folders"), id)
          nil
        end

        # The stored row `{ id, name, location }` of a folder that is set up and found now, for the station reads,
        # which keep its location to themselves. Refuses climate.folder_not_found otherwise.
        def folder(id)
          row = find!(Store.read.fetch("folders"), id)
          return row if File.directory?(row.fetch("location"))

          raise CodedError.new(NOT_FOUND, "That climate data folder cannot be found on this computer now; locate " \
                                          "it or remove it. Nothing was read or written.")
        end

        # Every stored row whose folder is found now, in the order added.
        def found_folders
          Store.read.fetch("folders").select { |row| File.directory?(row.fetch("location")) }
        end

        # The Setup view's line: how many folders and stations, or why there are none to count.
        def setup_summary
          case Store.state
          when "unavailable" then "Not available on this computer yet"
          when "unreadable" then "The climate data settings cannot be read"
          else
            count = Store.read.fetch("folders").length
            return "No climate data folder" if count.zero?

            stations = found_folders.sum { |row| Stations::FolderScan.call(row.fetch("location")).stations.length }
            "#{count} folder#{'s' unless count == 1}, #{delimited(stations)} station#{'s' unless stations == 1}"
          end
        end

        # Where a folder is, for display, never as an absolute path: under the home folder `~/` and the rest,
        # on another volume the volume's name and the rest, anywhere else the last two names after `…/`.
        def display_location(location, home = Dir.home)
          home = home.to_s.chomp("/")
          return "~" if !home.empty? && location == home
          return "~/#{location.delete_prefix("#{home}/")}" if !home.empty? && location.start_with?("#{home}/")

          volume = %r{\A/Volumes/([^/]+)(?:/(.+))?\z}.match(location)
          return [volume[1], volume[2]].compact.join("/") if volume

          tail = location.split("/").reject(&:empty?).last(2)
          tail.empty? ? "…" : "…/#{tail.join('/')}"
        end

        # The public row: no location, and the folder's counts as one walk finds them now (Stations::Operations).
        def public_row(row)
          location = row.fetch("location")
          { "id" => row.fetch("id"), "name" => row.fetch("name"),
            "display_location" => display_location(location, home), "found" => File.directory?(location) }
            .merge(Stations::Operations.counts(location))
        end

        def delimited(count)
          count.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
        end

        def listed(section)
          { "folders" => section.fetch("folders").map { |row| public_row(row) },
            "last_dataset_id" => section.fetch("last_dataset_id") }
        end

        # The chosen folder's absolute path, or climate.folder_not_found when it is not a folder now or its path
        # is longer than a stored location may be.
        def chosen_folder(path)
          location = File.expand_path(path.to_s)
          return location if location.bytesize <= Store::MAX_LOCATION_BYTES && File.directory?(location)

          raise CodedError.new(NOT_FOUND, "The chosen folder could not be found. Nothing was written.")
        rescue ArgumentError, EncodingError, SystemCallError
          raise CodedError.new(NOT_FOUND, "The chosen folder could not be found. Nothing was written."), :cause => nil
        end

        def change_row(id)
          section = Store.update do |current|
            folders = current.fetch("folders")
            changed = yield(find!(folders, id), folders)
            current.merge("folders" => folders.map { |row| row.fetch("id") == id ? changed : row })
          end
          public_row(section.fetch("folders").find { |row| row.fetch("id") == id })
        end

        def find!(folders, id)
          folders.find { |row| row.fetch("id") == id } || raise(CodedError.new(NOT_FOUND, UNKNOWN))
        end

        # A folder already listed, or inside or around one, would list its stations twice.
        def refuse_overlap(folders, location)
          chosen = comparable(location)
          overlapping = folders.find do |row|
            listed = comparable(row.fetch("location"))
            [[chosen, listed], [listed, chosen]].any? do |inner, outer|
              inner == outer || inner.start_with?("#{outer}/")
            end
          end
          return unless overlapping

          raise CodedError.new(OVERLAPS, "That folder is, holds or sits inside the climate data folder " \
                                         "#{overlapping.fetch('name').inspect}, so its stations would be listed " \
                                         "twice. Nothing was written.")
        end

        # The folder's real path, so a link and its target compare equal (on macOS the real path also takes the
        # case the disk holds). A folder that is not there now resolves its nearest existing parent and keeps
        # the rest, so it still compares with folders under the same linked parent. No trailing separator: the
        # root becomes empty, so it holds every folder.
        def comparable(location)
          existing = location
          rest = []
          until existing == "/" || File.exist?(existing)
            rest.unshift(File.basename(existing))
            existing = File.dirname(existing)
          end
          real = begin
            File.realpath(existing)
          rescue SystemCallError
            existing
          end
          File.join(real, *rest).chomp("/")
        end

        def default_name(location)
          name = File.basename(location).strip
          name = DEFAULT_NAME if name.empty? || name == "/"
          name[0, Store::MAX_NAME_LENGTH]
        end

        def home
          Dir.home
        rescue ArgumentError
          ""
        end
        private_class_method :public_row, :delimited, :listed, :chosen_folder, :change_row, :find!, :refuse_overlap,
                             :comparable, :default_name, :home
      end
    end
  end
end
