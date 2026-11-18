# frozen_string_literal: true

module PhComposer
  module Climate
    # The station reads and the two writes that take a station file: stations.list, stations.all,
    # climate.attach_station, climate.replace_station and climate.source_status. The reads are under the `read`
    # grant: they answer a station's name, state, coordinates and elevation, never a monthly value or a path
    # (context/CONTRACTS.md, "The Phius station reader"). Attaching and replacing are separate actions so that each
    # carries its own Undo name; both take a folder id and a station key, and Ruby reads the file.
    module StationsRegistration
      STATIONS_PREFIX = "#{FEATURE_ID}.stations".freeze
      CLIMATE_PREFIX = ClimateRegistration::PREFIX
      FOLDER_REFUSES = FoldersRegistration::STORE_REFUSES + [Folders::Operations::NOT_FOUND]
      STATION_KEY = { "type" => "string", "minLength" => 1, "maxLength" => 1024,
                      "description" => "The station's key from stations.list: its file's path inside the climate " \
                                       "data folder, such as NY/STATION-mon.txt." }.freeze
      STATION = Shapes.object({
        "key" => STATION_KEY,
        "name" => { "type" => "string", "description" => "The station's name as its file's header gives it." },
        "state" => { "type" => "string", "description" => "The name of the folder the file sits in." },
        "latitude_deg" => { "type" => "number", "x-unit" => "deg" },
        "longitude_deg" => { "type" => "number", "x-unit" => "deg" },
        "elevation_m" => { "type" => "number", "x-unit" => "m", "description" => "Height above sea level." },
        "limit_check" => Shapes::LIMIT_CHECK
      }).freeze
      LIST = Shapes.object({
        "folder_id" => FoldersRegistration::FOLDER_ID,
        "dataset_name" => FoldersRegistration::NAME,
        "complete" => { "type" => "boolean",
                        "description" => "false when the folder was too large or deep to read whole, or part of " \
                                         "it could not be listed." },
        "total" => Pages::TOTAL,
        "next_cursor" => Pages::NEXT_CURSOR,
        "stations" => Shapes.list(STATION, :description => "Nearest first, then by key.")
      }).freeze
      BY_FOLDER = Shapes.object({ "folder_id" => FoldersRegistration::FOLDER_ID }).freeze
      ALL = Shapes.object(LIST.fetch("properties").reject { |key, _| key == "next_cursor" }).freeze
      BY_STATION = Shapes.object({ "folder_id" => FoldersRegistration::FOLDER_ID, "station_key" => STATION_KEY }).freeze
      REPLACED = Shapes.with(ClimateRegistration::WRITTEN, "replaced" => Shapes.object({
        "name" => { "type" => "string", "description" => "The replaced climate's name." },
        "origin" => { "type" => "string", "enum" => %w[station hand] },
        "lost_edited_cells" => { "type" => "integer", "minimum" => 0,
                                 "description" => "How many of its values differed from its station file; " \
                                                  "wind speed is never an edit, and a climate entered by hand " \
                                                  "has none." }
      })).freeze
      STATUS = Shapes.object({
        "status" => { "type" => "string", "enum" => %w[found changed not_on_this_computer not_applicable],
                      "description" => "found when a file of the same station name and state has the same SHA-256, " \
                                       "changed when it has another; not_applicable for a climate entered by hand " \
                                       "or none." },
        "folder_id" => { "type" => %w[string null],
                         "description" => "The folder holding the matched file, when found or changed." },
        "station_key" => { "type" => %w[string null],
                           "description" => "Its key, for replace_station (Update from File)." }
      }).freeze
      WRITE_REFUSES = (FOLDER_REFUSES + ClimateRegistration::REFUSES +
                       [Stations::Operations::SITE_NOT_SET, Stations::Operations::STATION_NOT_FOUND,
                        Stations::Operations::UNREADABLE]).freeze
      EXAMPLE = { "folder_id" => FoldersRegistration::EXAMPLE_ID, "station_key" => "XA/STATION-mon.txt" }.freeze

      module_function

      def install(feature)
        feature.query("#{STATIONS_PREFIX}.list",
                      :description => "One climate data folder's Phius stations, nearest the Model's site first, " \
                                      "each with its distance, elevation difference and Phius verdict. Paged; " \
                                      "refuses climate.site_not_set with no site.",
                      :refuses => FOLDER_REFUSES + [Stations::Operations::SITE_NOT_SET, "query.limit_invalid",
                                                    "query.cursor_expired"],
                      :params => Shapes.object({ "folder_id" => FoldersRegistration::FOLDER_ID,
                                                 "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR },
                                               :optional => %w[limit cursor]),
                      :result => LIST,
                      :examples => [{ "folder_id" => FoldersRegistration::EXAMPLE_ID },
                                    { "folder_id" => FoldersRegistration::EXAMPLE_ID, "limit" => 20 }]) do |request|
          Stations::Operations.list(request, request.params.fetch("folder_id"))
        end
        feature.query("#{STATIONS_PREFIX}.all",
                      :description => "Every station of one climate data folder in one read, nearest first, for " \
                                      "the station picker. Scripts page #{STATIONS_PREFIX}.list instead.",
                      :response => { "bounded" => false, "prefer" => "#{STATIONS_PREFIX}.list" },
                      :refuses => FOLDER_REFUSES + [Stations::Operations::SITE_NOT_SET],
                      :params => BY_FOLDER, :result => ALL,
                      :examples => [{ "folder_id" => FoldersRegistration::EXAMPLE_ID }]) do |request|
          Stations::Operations.all(request, request.params.fetch("folder_id"))
        end
        feature.query("#{CLIMATE_PREFIX}.source_status",
                      :description => "Whether the attached station's file is on this computer: looked for by " \
                                      "station name and state in every climate data folder, then compared by " \
                                      "SHA-256.",
                      :refuses => FoldersRegistration::STORE_REFUSES + %w[record.unreadable],
                      :params => Shapes::NONE, :result => STATUS,
                      :examples => [{}]) { |request| Stations::Operations.source_status(request) }
        install_writes(feature)
      end

      def install_writes(feature)
        feature.action("#{CLIMATE_PREFIX}.attach_station",
                       :description => "Attach a station from a climate data folder: Ruby reads its file and the " \
                                       "Model keeps a copy of its values, with the as-read copy, the source and the " \
                                       "wind speed prefilled from January and July. Needs the site set; refuses " \
                                       "target.changed when the Model already holds a climate.",
                       :refuses => WRITE_REFUSES, :params => BY_STATION, :result => ClimateRegistration::WRITTEN,
                       :undo_name => "Attach Climate Station", :side_effects => "Stores the climate in this SKP.",
                       :examples => [EXAMPLE]) do |request, proposal|
          Stations::Operations.attach(request, proposal, :folder_id => request.params.fetch("folder_id"),
                                                         :station_key => request.params.fetch("station_key"))
        end
        feature.action("#{CLIMATE_PREFIX}.replace_station",
                       :description => "Replace the Model's climate with a station from a climate data folder, " \
                                       "losing any edited values; with the station source_status matched it is " \
                                       "Update from File. Needs the site set; refuses climate.not_found with no " \
                                       "climate.",
                       :refuses => WRITE_REFUSES + [Climate::Operations::NOT_FOUND], :params => BY_STATION,
                       :result => REPLACED, :undo_name => "Replace Climate Station",
                       :side_effects => "Stores the climate in this SKP.",
                       :examples => [EXAMPLE]) do |request, proposal|
          Stations::Operations.replace(request, proposal, :folder_id => request.params.fetch("folder_id"),
                                                          :station_key => request.params.fetch("station_key"))
        end
      end
    end
  end
end
