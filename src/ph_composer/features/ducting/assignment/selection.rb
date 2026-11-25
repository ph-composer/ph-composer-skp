# frozen_string_literal: true

module PhComposer
  module Ducting
    module Assignment
      # The native selection as duct references, over the shared line-group layer (LineGroups::Selection). A read:
      # writes take the references it returns, with the values as read, through ducts.assign and ducts.clear.
      module Selection
        PAGED = "#{FEATURE_ID}.ducts.selection".freeze

        module_function

        def all(request)
          LineGroups::Selection.all(LINE_GROUP, request, **reads(request))
        end

        def page(request)
          LineGroups::Selection.page(LINE_GROUP, request, PAGED, **reads(request))
        end

        # The gesture limit and Zones' containment the rows read.
        def reads(request)
          { :limit => Assignment.gesture_edge_limit,
            :contained => ->(paths) { Group::Operations.contained(request, paths) } }
        end
        private_class_method :reads
      end
    end
  end
end
