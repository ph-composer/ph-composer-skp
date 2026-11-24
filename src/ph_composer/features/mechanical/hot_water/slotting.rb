# frozen_string_literal: true

module PhComposer
  module Mechanical
    module HotWater
      # Which of honeybee-ph's four tank slots each of one System's Tanks fills, by role: storage tanks fill
      # `tank_1` then `tank_2`, a buffer tank `tank_buffer`, a solar tank `tank_solar`. The tanks of a role are taken
      # in name order (ignoring case, as names are unique), then id, so the slot a tank lands in follows its Tag and
      # never the order records were read. A tank its role has no free slot for is unslotted: the export leaves it out
      # with a finding. Pure: the reads, the preflight and the export work every System's slots out with this one
      # function.
      module Slotting
        SLOTS = %w[tank_1 tank_2 tank_buffer tank_solar].freeze
        ROLE_SLOTS = { "storage" => %w[tank_1 tank_2], "buffer" => %w[tank_buffer], "solar" => %w[tank_solar] }.freeze
        # `slots` maps each slot to the tank it holds, nil when empty; `unslotted` lists the rest in order.
        Result = Struct.new(:slots, :unslotted, keyword_init: true) do
          # The slot `tank_id` fills, or nil.
          def slot_of(tank_id)
            slots.find { |_slot, tank| tank && tank.fetch("id") == tank_id }&.first
          end
        end

        module_function

        # `tanks` are one System's Tanks, each with at least its id, name and role.
        def call(tanks)
          slots = SLOTS.to_h { |slot| [slot, nil] }
          unslotted = []
          tanks.sort_by { |tank| [tank.fetch("name").downcase, tank.fetch("name"), tank.fetch("id")] }.each do |tank|
            free = ROLE_SLOTS.fetch(tank.fetch("role")).find { |slot| slots.fetch(slot).nil? }
            free ? slots[free] = tank : unslotted << tank
          end
          Result.new(:slots => slots, :unslotted => unslotted)
        end
      end
    end
  end
end
