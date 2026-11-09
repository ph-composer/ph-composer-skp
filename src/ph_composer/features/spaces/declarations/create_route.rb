# frozen_string_literal: true

module PhComposer
  module Spaces
    # Create Space's native route: the context-menu item, and the review it hands the panel with the two
    # view commands that open and close it. The review writes nothing; the panel's confirmation is `create`.
    module CreateRouteRegistration
      ZONE_CHOICE = Shapes.object({ "zone_id" => Shapes::TEXT, "zone_path" => Shapes::ZONE_PATH,
                                    "name" => Shapes::TEXT }).freeze
      REVIEW = Shapes.object({
        "token" => { "type" => %w[string null], "description" => "One per review opened; null when none is open." },
        "revision" => { "type" => %w[integer null], "description" => "The revision create must be applied at." },
        "zone" => OperationRegistration::OPTIONAL_ZONE.merge("description" => "The Zone preselected; null for none."),
        "zones" => Shapes.list(ZONE_CHOICE),
        "accepted" => Shapes.list(PATH),
        "left_out" => Shapes.list(OperationRegistration::LEFT_OUT),
        "height_m" => { "type" => %w[number null], "x-unit" => "m",
                        "description" => "The height the new Space takes." },
        "height_source" => { "type" => %w[string null], "enum" => [nil, "last_height", "default"],
                             "description" => "Where the height comes from." }
      }).freeze
      OPEN_PARAMS = Shapes.object({
        "faces" => OperationRegistration::PATHS,
        "revision" => { "type" => "integer", "description" => "The revision the Faces were read at; a later one " \
                                                              "refuses." }
      }).freeze

      module_function

      def install(feature)
        feature.menu_item("#{FEATURE_ID}.create_menu", :label => CreateRoute::LABEL, :menu => EXTENSION_NAME,
                                                       :available => ->(read) {
                                                                       CreateRoute.available?(read.session)
                                                                     }) do |session|
          CreateRoute.client(session).run
        end
        feature.query("#{FEATURE_ID}.create_review.state",
                      :description => "The open Create Space review, if any.",
                      :refuses => [], :params => Shapes::NONE, :result => REVIEW, :examples => [{}]) do |request|
          CreateRoute.review(request.session).snapshot
        end
        feature.snapshot_section("#{FEATURE_ID}.create_review", :query => "#{FEATURE_ID}.create_review.state")
        feature.view_command("#{FEATURE_ID}.create_review.open",
                             :description => "Review which explicit Faces Create Space would take into a new Space, " \
                                             "why it leaves each other one out, and which Zone hosts it, for the " \
                                             "panel to confirm.",
                             :refuses => (OperationRegistration::ZONE_TARGET +
                                          %w[geometry.invalid revision.stale]).uniq,
                             :params => OPEN_PARAMS, :result => REVIEW,
                             :examples => [{ "faces" => [[1202]], "revision" => 1 }]) do |request|
          CreateRoute.open(request, :faces => request.params.fetch("faces"),
                                    :revision => request.params.fetch("revision"))
        end
        feature.view_command("#{FEATURE_ID}.create_review.close",
                             :description => "Close the Create Space review.",
                             :refuses => [],
                             :params => Shapes.object({
                               "token" => { "type" => "string", "description" => "The token the review opened " \
                                                                                 "with; another leaves it open." }
                             }),
                             :result => REVIEW, :examples => [{ "token" => "example-review-token" }]) do |request|
          value = CreateRoute.review(request.session).close(request.params.fetch("token"))
          request.session.changed(:spaces, :create_review)
          value
        end
      end
    end
  end
end
