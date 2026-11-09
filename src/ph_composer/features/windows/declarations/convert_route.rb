# frozen_string_literal: true

require_relative "../units/convert_route"

module PhComposer
  module Windows
    # Convert to Window Type's native route: the menu item, and the review it hands the panel with the two
    # view commands that open and close it. The review writes nothing; the panel's confirmation is `convert`.
    module ConvertRouteRegistration
      PREFIX = Units::ConvertRoute::PREFIX

      module_function

      def install(feature, review_result, paths_param)
        feature.menu_item("#{FEATURE_ID}.convert_menu", :label => Units::ConvertRoute::LABEL, :menu => EXTENSION_NAME,
                                                        :available => ->(read) {
                                                                        Units::ConvertRoute.available?(read.session)
                                                                      }) do |session|
          Units::ConvertRoute.client(session).run
        end
        dialog = dialog_shape(review_result)
        feature.query("#{PREFIX}.state", :description => "The open Convert to Window Type review, if any.",
                                         :refuses => [], :params => Shapes::NONE, :result => dialog,
                                         :examples => [{}]) do |request|
          Units::ConvertRoute.dialog(request.session).snapshot
        end
        feature.snapshot_section(PREFIX, :query => "#{PREFIX}.state")
        install_view_commands(feature, dialog, paths_param)
      end

      def install_view_commands(feature, dialog, paths_param)
        feature.view_command("#{PREFIX}.open",
                             :description => "Review which drawn rectangles Convert to Window Type would take and " \
                                             "why it leaves each other Face out, for the panel to confirm.",
                             :refuses => Refuses::CONVERT_REVIEW,
                             :params => Shapes.object({ "paths" => paths_param }), :result => dialog,
                             :examples => [{ "paths" => [[1201, 1204]] }]) do |request|
          Units::ConvertRoute.open(request, request.params.fetch("paths"))
        end
        feature.view_command("#{PREFIX}.close",
                             :description => "Close the Convert to Window Type review.",
                             :refuses => [],
                             :params => Shapes.object({
                               "token" => { "type" => "string", "description" => "The token the review opened " \
                                                                                 "with; another leaves it open." }
                             }),
                             :result => dialog, :examples => [{ "token" => "example-review-token" }]) do |request|
          value = Units::ConvertRoute.dialog(request.session).close(request.params.fetch("token"))
          request.session.changed(:windows, :convert_dialog)
          value
        end
      end

      def dialog_shape(review_result)
        properties = review_result.fetch("properties")
        Shapes.object({
          "token" => { "type" => %w[string null], "description" => "One per review opened; null when none is open." },
          "revision" => { "type" => %w[integer null], "description" => "The revision convert must be applied at." },
          "groups" => properties.fetch("groups"), "left_out" => properties.fetch("left_out")
        })
      end
      private_class_method :install_view_commands, :dialog_shape
    end
  end
end
