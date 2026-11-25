# frozen_string_literal: true

module PhComposer
  module Piping
    # The schedule a bounded page at a time (LineGroups::SchedulePages), with the Systems and Pipe Types as its detail
    # lists.
    module SchedulePages
      PAGE = "#{FEATURE_ID}.schedule".freeze
      MEMBERS = "#{FEATURE_ID}.runs.members".freeze
      DETAILS = "#{FEATURE_ID}.schedule.details".freeze
      # Each list the details read pages, by the key its rows sort by.
      PARTS = { "systems" => "hot_water_system_id", "types" => "pipe_type_id", "unreadable" => "path" }.freeze
      DETAIL_ROWS = LineGroups::SchedulePages::DETAIL_ROWS
      MAX_MESSAGE = Scan::MAX_MESSAGE
      # The labels in a run row that come from a user's text, cut as every name in a bounded row is.
      NAMES = %w[display_name hot_water_system_name parent_name pipe_type_name].freeze
      PAGES = LineGroups::SchedulePages.new(
        :page => PAGE, :members => MEMBERS, :details => DETAILS, :parts => PARTS,
        :counts => { "systems" => "system_count", "types" => "type_count" }.freeze, :names => NAMES,
        :run_label => "piping run", :schedule => ->(request) { Scan.schedule(request) }
      )
    end
  end
end
