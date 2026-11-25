# frozen_string_literal: true

module PhComposer
  module Ducting
    # Ducting's line group (line_groups/spec.rb): the Ducting group and the ducts directly in it. The reference targets,
    # write steps, walk and selection are the shared layer's, called with this.
    LINE_GROUP = LineGroups::Spec.new(
      :label => "Ducting group", :edge_noun => "duct", :group_kind => GROUP_KIND, :edge_kind => DUCT_KIND,
      :group_store => Group::STORE, :edge_store => Assignment::STORE, :group_record_kind => Group::RECORD_KIND,
      :edge_record_kind => Assignment::RECORD_KIND, :link_key => "ventilator_id",
      :codes => { :outside_group => Codes::OUTSIDE_GROUP, :group_nested => Codes::GROUP_NESTED,
                  :group_in_zone => Codes::GROUP_IN_ZONE }.freeze,
      :child_lookup => -> { Zones::ChildLookup.new }
    ).freeze
  end
end
