# frozen_string_literal: true

module PhComposer
  module Climate
    module Stations
      # The reads and writes over the station files in the climate data folders: one folder's counts, its station
      # list against the Model's site, attaching or replacing the Model's climate from a station file, and where
      # the attached station's file is now. The station's values go from the file to the Model inside Ruby: no
      # call takes one in its params, and no read answers a monthly value or a path.
      module Operations
        QUERY = "#{FEATURE_ID}.stations.list".freeze
        SITE_NOT_SET = "climate.site_not_set"
        STATION_NOT_FOUND = "climate.station_not_found"
        UNREADABLE = "climate.station_unreadable"
        FORMAT = "phius_station_file"
        # At most this many kinds of file not read are listed; files_not_read_total counts every one.
        MAX_KINDS = 20
        NEAREST_FIRST = ->(row) { [row.dig("limit_check", "distance_km"), row.fetch("key")] }

        module_function

        # What folders.list adds for a folder: the format found, the station and state counts and the files not
        # read by kind. All null for a folder that cannot be found now.
        def counts(location)
          unless File.directory?(location)
            return { "format" => nil, "station_count" => nil, "state_count" => nil, "files_not_read" => nil,
                     "files_not_read_total" => nil, "complete" => nil }
          end

          scan = FolderScan.call(location)
          kinds = scan.not_read.sort_by { |extension, count| [-count, extension] }.first(MAX_KINDS)
          { "format" => scan.stations.empty? ? nil : FORMAT, "station_count" => scan.stations.length,
            "state_count" => scan.stations.map(&:state).uniq.length,
            "files_not_read" => kinds.map { |extension, count| kind_row(extension, count) },
            "files_not_read_total" => scan.not_read.values.sum, "complete" => scan.complete }
        end

        # stations.list: one folder's stations, nearest first, each with its limit check against the Model's
        # site, in pages bounded for one reply. A page's cursor is bound to the Model's revision, so a site change
        # between pages refuses it rather than mixing two orders.
        def list(request, folder_id)
          whole = all(request, folder_id)
          page, next_cursor = Pages.bounded(request, QUERY, whole.fetch("stations"), :key => NEAREST_FIRST)
          whole.merge("next_cursor" => next_cursor, "stations" => page)
        end

        # stations.all: the same rows in one read, unbounded, for the station picker, which shows every station.
        def all(request, folder_id)
          site = site!(request.model)
          folder = Folders::Operations.folder(folder_id)
          scan = FolderScan.call(folder.fetch("location"))
          rows = scan.stations.map { |station| row(station, site) }.sort_by(&NEAREST_FIRST)
          { "folder_id" => folder_id, "dataset_name" => folder.fetch("name"), "complete" => scan.complete,
            "total" => rows.length, "stations" => rows }
        end

        # climate.attach_station: a new climate from a station file. Refuses target.changed when the Model holds
        # one already; replace_station replaces it.
        def attach(request, proposal, folder_id:, station_key:)
          Climate::Operations.refusing(proposal) do
            unless Climate::Operations.stored(request.engine).nil?
              Climate::Operations.refuse("target.changed", "The Model already holds a climate; replace it with " \
                                                           "replace_station")
            end

            after = station_record(request, folder_id, station_key)
            Climate::Operations.stage(request, proposal, nil, after)
          end
        end

        # climate.replace_station: the Model's climate replaced by a station file, which is also Update from File
        # with the station source_status matched. The record keeps its user_data. The result names what was
        # replaced and how many edited values that loses, for the picker's notice.
        def replace(request, proposal, folder_id:, station_key:)
          Climate::Operations.refusing(proposal) do
            before = Climate::Operations.stored(request.engine)
            Climate::Operations.refuse(Climate::Operations::NOT_FOUND, "The Model holds no climate") if before.nil?

            after = before.merge(station_record(request, folder_id, station_key))
            replaced = Schema::KIND.values(before)
            Climate::Operations.stage(request, proposal, before, after).merge(
              "replaced" => { "name" => replaced.fetch("name"), "origin" => replaced.fetch("origin"),
                              "lost_edited_cells" => Edits.cells(replaced).length }
            )
          end
        end

        # climate.source_status: the attached station's file looked for by its station name and state in every
        # climate data folder found on this computer, whatever the folder is named. found when one has the
        # same SHA-256, changed when one has another, not_on_this_computer when none matches, and not_applicable
        # for a climate entered by hand or no climate at all.
        def source_status(request)
          record = Climate::Operations.stored(request.engine)
          values = record && Schema::KIND.values(record)
          return status("not_applicable") unless values && values.fetch("origin") == "station"

          provenance = values.fetch("provenance")
          changed = nil
          Folders::Operations.found_folders.each do |folder|
            scan = FolderScan.call(folder.fetch("location"))
            # A source whose header no longer reads is still the same file name in the same state: changed.
            (scan.stations + scan.unreadable).each do |station|
              next unless station.stem == provenance.fetch("station_name") && station.state == provenance.fetch("state")

              match = status("found", folder, station)
              return match if file_checksum(station) == provenance.fetch("source_checksum")

              changed ||= status("changed", folder, station)
            end
          end
          changed || status("not_on_this_computer")
        end

        def kind_row(extension, count)
          { "extension" => extension, "count" => count }
        end

        # The station's public row: its key, name, state, coordinates and elevation, with the limit check.
        def row(station, site)
          { "key" => station.key, "name" => station.name, "state" => station.state,
            "latitude_deg" => station.latitude_deg, "longitude_deg" => station.longitude_deg,
            "elevation_m" => station.elevation_m,
            "limit_check" => LimitCheck.call(site, "station_latitude_deg" => station.latitude_deg,
                                                   "station_longitude_deg" => station.longitude_deg,
                                                   "station_elevation_m" => station.elevation_m) }
        end

        # The climate record's values read from the station `station_key` names in the folder: only a key the walk
        # lists is read, so a key is never joined onto the folder's path.
        def station_record(request, folder_id, station_key)
          site!(request.model)
          folder = Folders::Operations.folder(folder_id)
          station = FolderScan.call(folder.fetch("location")).stations.find { |found| found.key == station_key }
          if station.nil?
            Climate::Operations.refuse(STATION_NOT_FOUND, "No station file with that key is in the climate data " \
                                                          "folder now")
          end

          bytes = read(station)
          source = { "dataset_name" => folder.fetch("name"), "station_name" => station.stem,
                     "state" => station.state, "checksum" => PhiusStationFile.checksum(bytes) }
          { "id" => Schema::RECORD_ID, "schema_version" => Schema::KIND.schema_version }
            .merge(Record.from_station(PhiusStationFile.parse(bytes), source))
        rescue PhiusStationFile::Unreadable => error
          raise CodedError.new(UNREADABLE, "The station file could not be read (#{error.message}). Nothing was " \
                                           "written."), :cause => nil
        end

        def read(station)
          bytes = File.binread(station.path, PhiusStationFile::MAX_BYTES + 1)
          bytes || "".b
        rescue SystemCallError, IOError
          raise CodedError.new(STATION_NOT_FOUND, "The station file could not be opened. Nothing was written."),
                :cause => nil
        end

        def file_checksum(station)
          PhiusStationFile.checksum(read(station))
        rescue CodedError
          nil
        end

        def site!(model)
          site = Settings.site(model)
          return site if site.fetch("state") == "set"

          raise CodedError.new(SITE_NOT_SET, "Set the site's latitude, longitude and elevation first: the station " \
                                             "list and its limit check need them. Nothing was read or written.")
        end

        def status(name, folder = nil, station = nil)
          { "status" => name, "folder_id" => folder&.fetch("id"), "station_key" => station&.key }
        end
        private_class_method :kind_row, :row, :station_record, :read, :file_checksum, :site!, :status
      end
    end
  end
end
