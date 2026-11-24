# frozen_string_literal: true

# One feature owns hot water piping: the Pipe Type catalog now, and later the Piping groups that hold drawn pipes,
# the assignment on each pipe, the tree they form and their export into the Hot Water System. It requires Mechanical,
# which owns the Hot Water System and its export, and Zones; no file of theirs, nor any other feature's, names it
# (context/EXTENSIBILITY.md, "Organization and dependencies").
#
#   type/           the Pipe Type kind, its operations and reads; names no Edge, group or run
#   codes.rb        the `piping` noun's codes
#   declarations/   what the feature registers
module PhComposer
  module Piping
    FEATURE_ID = "ph_composer.piping"
  end
end

require_relative "codes"
require_relative "type/schema"
require_relative "type/operations"
require_relative "type/reads"
require_relative "declarations/shapes"
require_relative "declarations/pipe_types"

module PhComposer
  module Piping
    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1,
                                             :requires => %w[ph_composer.mechanical ph_composer.zones])
      PipeTypeRegistration.install(feature)
      Codes.install(feature)
    end
  end
end
