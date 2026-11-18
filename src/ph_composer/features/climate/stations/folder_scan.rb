# frozen_string_literal: true

module PhComposer
  module Climate
    module Stations
      # One walk of a climate data folder, subfolders included, read when it is asked for and never kept (a
      # real-size folder of 1,007 station files walks and reads its headers in under 0.1 s in SketchUp's Ruby, so
      # the walk is synchronous and has no cache). A station is a `-mon.txt` file, with a name before the suffix,
      # whose header reads; its state is the name of the folder it sits in and its key its path relative to the
      # climate data folder, which is unique. Everything else is counted as not read, by extension, a `-mon.txt`
      # whose header does not read among them. Hidden files and folders are skipped and links are not followed,
      # so a link cannot loop or leave the folder. The walk is bounded: past MAX_ENTRIES entries or MAX_DEPTH
      # folders down, or at a folder that cannot be listed, it stops there and says the scan is not complete.
      module FolderScan
        MAX_ENTRIES = 20_000
        MAX_DEPTH = 16
        # An extension longer than this is cut, before counting, so one odd file name cannot make a long kind.
        MAX_EXTENSION_LENGTH = 16

        # A station as the walk found it. `path` is the file's absolute path and goes no further than this
        # feature's reads; every public row is built from the other fields.
        Station = Struct.new(:key, :stem, :name, :state, :latitude_deg, :longitude_deg, :elevation_m, :path,
                             :keyword_init => true)
        # What one walk found: the stations in key order, files not read as { extension => count }, and whether
        # the walk read the whole folder.
        Scan = Struct.new(:stations, :not_read, :complete, :keyword_init => true)

        module_function

        # The walk of the folder at `root`, an absolute path to a folder that exists. The bounds are arguments
        # only so a test can reach them with a small folder. A station is listed from its header alone; a file
        # whose header reads and whose series rows do not is listed, and attach refuses it naming the row.
        def call(root, max_entries: MAX_ENTRIES, max_depth: MAX_DEPTH)
          stations = []
          not_read = Hash.new(0)
          complete = true
          entries = 0
          pending = [[root, [], File.basename(root)]]
          until pending.empty?
            folder, segments, state = pending.shift
            children, enumerated = list(folder, max_entries - entries)
            # Every entry read counts, hidden ones and those of a folder that failed part way.
            entries += enumerated
            if children.nil?
              complete = false
              # Past the budget nothing more is read anywhere; a folder that cannot be listed stops only itself.
              break if entries >= max_entries

              next
            end

            children.each do |name|
              path = File.join(folder, name)
              stat = File.lstat(path)
              if stat.directory? && segments.length < max_depth
                pending << [path, segments + [name], name]
              elsif stat.directory?
                complete = false
              elsif stat.file?
                station = station(path, stat, (segments + [name]).join("/"), state)
                station ? stations << station : not_read[extension(name)] += 1
              end
            rescue SystemCallError, IOError, EncodingError, ArgumentError
              complete = false
            end
          end
          Scan.new(:stations => stations.sort_by(&:key), :not_read => not_read, :complete => complete)
        end

        # [the folder's visible children in name order, how many entries were read]. The children are nil when
        # the folder cannot be listed or holds more than `budget` entries, hidden ones included; then the count is
        # the budget, so the walk stops. Names are counted as they are read, so a huge folder is never listed
        # whole.
        def list(folder, budget)
          names = []
          count = 0
          Dir.each_child(folder) do |name|
            count += 1
            return [nil, budget] if count > budget

            names << name unless name.start_with?(".")
          end
          [names.sort, count]
        rescue SystemCallError, IOError
          [nil, count]
        end

        # The station a regular file is, or nil when it is not one.
        def station(path, stat, key, state)
          name = File.basename(path)
          stem = name.delete_suffix(PhiusStationFile::SUFFIX)
          return nil if stem == name || stem.empty? || stat.size > PhiusStationFile::MAX_BYTES

          # At most one byte past the limit, so a file that grew since its size was read is still refused unread.
          header = PhiusStationFile.header(File.binread(path, PhiusStationFile::MAX_BYTES + 1) || "".b)
          Station.new(:key => key, :stem => stem, :name => header.fetch("name"),
                      :state => state, :latitude_deg => header.fetch("latitude_deg"),
                      :longitude_deg => header.fetch("longitude_deg"), :elevation_m => header.fetch("elevation_m"),
                      :path => path)
        rescue PhiusStationFile::Unreadable, SystemCallError, IOError
          nil
        end

        # A file's kind for the counts: its extension in lower case, such as ".xls", or "" for none.
        def extension(name)
          File.extname(name).downcase[0, MAX_EXTENSION_LENGTH]
        end
        private_class_method :list, :station, :extension
      end
    end
  end
end
