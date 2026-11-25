# frozen_string_literal: true

module PhComposer
  module Ducting
    # Ducting's line group (line_groups/spec.rb): the Ducting group and the ducts directly in it. The reference targets,
    # write steps, group and duct operations, walk, selection, schedule paging and runs.locate are the shared layer's,
    # called with this.
    LINE_GROUP = LineGroups::Spec.new(
      :label => "Ducting group", :edge_noun => "duct", :group_kind => GROUP_KIND, :edge_kind => DUCT_KIND,
      :group_store => Group::STORE, :edge_store => Assignment::STORE, :group_record_kind => Group::RECORD_KIND,
      :edge_record_kind => Assignment::RECORD_KIND, :link_key => "ventilator_id",
      :codes => { :outside_group => Codes::OUTSIDE_GROUP, :group_nested => Codes::GROUP_NESTED,
                  :group_in_zone => Codes::GROUP_IN_ZONE, :hidden => Codes::HIDDEN }.freeze,
      :child_lookup => -> { Zones::ChildLookup.new },
      :link_kind => Mechanical::VENTILATOR_KIND, :link_label => "Ventilator",
      :type_kind => DUCT_TYPE_KIND, :type_key => "duct_type_id", :type_label => DuctType::KIND.label,
      :containment => "ph_composer.zones.containment"
    ).freeze
  end
end
