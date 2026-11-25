# frozen_string_literal: true

module PhComposer
  module Piping
    # Piping's line group (line_groups/spec.rb): the Piping group and the pipes directly in it. The reference targets,
    # write steps, group and pipe operations, walk, selection, schedule paging and runs.locate are the shared layer's,
    # called with this.
    LINE_GROUP = LineGroups::Spec.new(
      :label => "Piping group", :edge_noun => "pipe", :group_kind => GROUP_KIND, :edge_kind => PIPE_KIND,
      :group_store => Group::STORE, :edge_store => Assignment::STORE, :group_record_kind => Group::RECORD_KIND,
      :edge_record_kind => Assignment::RECORD_KIND, :link_key => "hot_water_system_id",
      :codes => { :outside_group => Codes::OUTSIDE_GROUP, :group_nested => Codes::GROUP_NESTED,
                  :group_in_zone => Codes::GROUP_IN_ZONE, :hidden => Codes::HIDDEN }.freeze,
      :child_lookup => -> { Zones::ChildLookup.new },
      :link_kind => Mechanical::HOT_WATER_SYSTEM_KIND, :link_label => "Hot Water System",
      :type_kind => PIPE_TYPE_KIND, :type_key => "pipe_type_id", :type_label => PipeType::KIND.label,
      :containment => "ph_composer.zones.containment"
    ).freeze
  end
end
