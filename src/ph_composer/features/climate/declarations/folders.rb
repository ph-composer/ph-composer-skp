# frozen_string_literal: true

module PhComposer
  module Climate
    # The climate data folders on this computer: one query and five setup commands under the `setup` grant.
    # None touches a Model, adds an Undo step or advances a session revision. Add and Locate need the user to
    # choose the folder (Declarations::Approval), so a scripted caller without an approved location is refused
    # and the path never travels in params, a result or the log.
    module FoldersRegistration
      PREFIX = "#{FEATURE_ID}.folders".freeze
      STORE_REFUSES = [Folders::Store::UNREADABLE, Folders::Store::UNAVAILABLE].freeze
      ADD = Declarations::Approval.new(:kind => "open_folder", :title => "Add Climate Data Folder").freeze
      LOCATE = Declarations::Approval.new(:kind => "open_folder", :title => "Locate Climate Data Folder").freeze
      NAME = { "type" => "string", "minLength" => 1, "maxLength" => Folders::Store::MAX_NAME_LENGTH,
               "description" => "The dataset name the Model and the Export report show." }.freeze
      FOLDER_ID = Shapes.described(Shapes::ID, "A climate data folder's id, from folders.list.").freeze
      COUNT_OR_NULL = { "type" => %w[integer null], "minimum" => 0,
                        "description" => "Read when the list is; null when the folder is not found." }.freeze
      FOLDER = Shapes.object({
        "id" => Shapes::ID,
        "name" => NAME,
        "display_location" => { "type" => "string",
                                "description" => "Where the folder is, for display: ~/ and the rest under the " \
                                                 "home folder, the volume's name and the rest on another volume. " \
                                                 "Never an absolute path." },
        "found" => { "type" => "boolean",
                     "description" => "false when the folder cannot be found now; the setting is kept." },
        "format" => { "type" => %w[string null], "enum" => [Stations::Operations::FORMAT, nil],
                      "description" => "The format of the stations found; null when there are none or the folder " \
                                       "is not found." },
        "station_count" => COUNT_OR_NULL, "state_count" => COUNT_OR_NULL,
        "files_not_read" => Shapes.list(Shapes.object({
          "extension" => { "type" => "string",
                           "description" => "The file extension in lower case, such as .xls; empty for none." },
          "count" => { "type" => "integer", "minimum" => 1 }
        }), :description => "Files not read as stations, by extension, most first, at most " \
                            "#{Stations::Operations::MAX_KINDS} kinds. A station file that does not read counts " \
                            "under .txt. Null when the folder is not found.").merge("type" => %w[array null]),
        "files_not_read_total" => COUNT_OR_NULL,
        "complete" => { "type" => %w[boolean null],
                        "description" => "false when the folder was too large or deep to read whole, or part of " \
                                         "it could not be listed; null when not found." }
      }).freeze
      LIST = Shapes.object({
        "folders" => Shapes.list(FOLDER, :description => "In the order added."),
        "last_dataset_id" => { "type" => %w[string null],
                               "description" => "The folder the station picker last used; null when none." }
      }).freeze
      BY_ID = Shapes.object({ "id" => FOLDER_ID }).freeze
      EXAMPLE_ID = "climate_folder_AbCdEf123456"

      module_function

      def install(feature)
        feature.query("#{PREFIX}.list",
                      :description => "The climate data folders set up on this computer, with each one's name, " \
                                      "display location, whether it can be found now, and the stations, states " \
                                      "and files not read found in it now.",
                      :refuses => STORE_REFUSES, :params => Shapes::NONE, :result => LIST,
                      :examples => [{}]) { |_request| Folders::Operations.list }
        install_chosen(feature)
        install_by_id(feature)
      end

      # The two commands that take a folder the user chooses.
      def install_chosen(feature)
        feature.setup_command("#{PREFIX}.add",
                              :description => "Add a climate data folder the user chooses in SketchUp, stored " \
                                              "under the folder's own name. Refuses climate.folder_overlaps for a " \
                                              "folder already listed, or inside or around one.",
                              :refuses => STORE_REFUSES + [Folders::Operations::NOT_FOUND,
                                                           Folders::Operations::OVERLAPS],
                              :params => Shapes::NONE, :result => FOLDER, :examples => [{}], :approval => ADD,
                              :precondition => ->(_request) { Folders::Store.read }) do |request|
          Folders::Operations.add(request.approval.path)
        end
        feature.setup_command("#{PREFIX}.locate",
                              :description => "Point a climate data folder's setting at the folder the user " \
                                              "chooses in SketchUp, keeping its id and name.",
                              :refuses => STORE_REFUSES + [Folders::Operations::NOT_FOUND,
                                                           Folders::Operations::OVERLAPS],
                              :params => BY_ID, :result => FOLDER, :examples => [{ "id" => EXAMPLE_ID }],
                              :approval => LOCATE,
                              :precondition => lambda { |request|
                                Folders::Operations.require_folder(request.params.fetch("id"))
                              }) do |request|
          Folders::Operations.locate(request.params.fetch("id"), request.approval.path)
        end
      end

      def install_by_id(feature)
        refuses = STORE_REFUSES + [Folders::Operations::NOT_FOUND]
        feature.setup_command("#{PREFIX}.rename",
                              :description => "Set a climate data folder's dataset name.", :refuses => refuses,
                              :params => Shapes.with(BY_ID, "name" => NAME), :result => FOLDER,
                              :examples => [{ "id" => EXAMPLE_ID, "name" => "Phius 2022" }]) do |request|
          Folders::Operations.rename(request.params.fetch("id"), request.params.fetch("name"))
        end
        feature.setup_command("#{PREFIX}.remove",
                              :description => "Remove a climate data folder's setting. The folder and its files " \
                                              "are not touched. PH-Composer never removes one itself.",
                              :refuses => refuses, :params => BY_ID, :result => LIST,
                              :examples => [{ "id" => EXAMPLE_ID }]) do |request|
          Folders::Operations.remove(request.params.fetch("id"))
        end
        feature.setup_command("#{PREFIX}.remember_dataset",
                              :description => "Remember the folder the station picker opens on next time.",
                              :refuses => refuses, :params => BY_ID, :result => LIST,
                              :examples => [{ "id" => EXAMPLE_ID }]) do |request|
          Folders::Operations.remember_dataset(request.params.fetch("id"))
        end
      end
    end
  end
end
