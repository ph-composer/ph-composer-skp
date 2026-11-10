# frozen_string_literal: true

module PhComposer
  INCH_TO_M = 0.0254
  SQUARE_INCH_TO_M2 = 0.00064516
  COORDINATE_DECIMALS = 6

  # Display conversions for human-readable reports. html/units.js is the panel's counterpart;
  # tests/support/units_vectors.json keeps the two in step.
  module Units
    # The value from which a formatted number is grouped, unless a caller names another.
    GROUP_FROM = 10_000
    METRES_PER_FOOT = 0.3048
    JOULES_PER_BTU = 1055.05585262
    F_PER_K = 1.8
    FT2_PER_M2 = 1.0 / (METRES_PER_FOOT**2)
    FT3_PER_M3 = FT2_PER_M2 / METRES_PER_FOOT
    BTU_H_PER_W = 3600.0 / JOULES_PER_BTU
    U_FACTOR = BTU_H_PER_W / FT2_PER_M2 / F_PER_K
    LENGTH_METRES = { "mm" => 0.001, "m" => 1.0, "in" => INCH_TO_M, "ft" => METRES_PER_FOOT }.freeze
    CONDUCTIVITY = {
      :si_label => "W/(m K)", :ip_label => "Btu/(h ft °F)", :si_precision => 3, :ip_precision => 3,
      :factor => BTU_H_PER_W * METRES_PER_FOOT / F_PER_K
    }.freeze

    # Lengths convert through LENGTH_METRES, their labels naming the unit; other quantities scale by factor.
    DEFINITIONS = {
      "length" => {
        :length => true, :canonical => "m", :si_label => "m", :ip_label => "ft", :si_precision => 2,
        :ip_precision => 2
      },
      "length_mm" => {
        :length => true, :canonical => "mm", :si_label => "mm", :ip_label => "in", :si_precision => 1,
        :ip_precision => 2
      },
      "area" => {
        :si_label => "m²", :ip_label => "ft²", :si_precision => 2, :ip_precision => 2, :factor => FT2_PER_M2
      },
      "volume" => {
        :si_label => "m³", :ip_label => "ft³", :si_precision => 2, :ip_precision => 2, :factor => FT3_PER_M3
      },
      "u_value" => {
        :si_label => "W/(m² K)", :ip_label => "Btu/(h ft² °F)", :si_precision => 3, :ip_precision => 4,
        :factor => U_FACTOR
      },
      "thermal_resistance" => {
        :si_label => "m² K/W", :ip_label => "h ft² °F/Btu", :si_precision => 2, :ip_precision => 2,
        :factor => 1.0 / U_FACTOR
      },
      "conductivity" => CONDUCTIVITY,
      "linear_psi" => CONDUCTIVITY,
      "heat_loss_rate" => {
        :si_label => "W/K", :ip_label => "Btu/(h °F)", :si_precision => 3, :ip_precision => 3,
        :factor => BTU_H_PER_W / F_PER_K
      },
      "airflow" => {
        :si_label => "m³/h", :ip_label => "cfm", :si_precision => 1, :ip_precision => 1,
        :factor => FT3_PER_M3 / 60
      }
    }.freeze

    module_function

    # `unit` names a length field's canonical unit when it differs from the quantity's (a width stored in metres).
    def to_display(value, quantity:, system:, unit: nil)
      definition = fetch_definition(quantity)
      number = Float(value)
      return (ip?(system) ? number * definition.fetch(:factor) : number) unless definition[:length]

      metres = number * LENGTH_METRES.fetch(unit || definition.fetch(:canonical))
      metres / LENGTH_METRES.fetch(label(:quantity => quantity, :system => system))
    end

    # The inverse of to_display: a number read in the display unit, back in the canonical one. Refuses what
    # Float refuses, so a caller reading typed text handles ArgumentError and TypeError.
    def from_display(value, quantity:, system:, unit: nil)
      definition = fetch_definition(quantity)
      number = Float(value)
      return (ip?(system) ? number / definition.fetch(:factor) : number) unless definition[:length]

      metres = number * LENGTH_METRES.fetch(label(:quantity => quantity, :system => system))
      metres / LENGTH_METRES.fetch(unit || definition.fetch(:canonical))
    end

    def label(quantity:, system:)
      fetch_definition(quantity).fetch(ip?(system) ? :ip_label : :si_label)
    end

    def precision(quantity:, system:)
      fetch_definition(quantity).fetch(ip?(system) ? :ip_precision : :si_precision)
    end

    def format(value, quantity:, system:, unit: nil, precision: nil, show_unit: true, group_from: GROUP_FROM)
      number = to_display(value, :quantity => quantity, :system => system, :unit => unit)
      digits = precision.nil? ? self.precision(:quantity => quantity, :system => system) : Integer(precision)
      text = format_number(number, digits, :group_from => group_from)
      show_unit ? "#{text} #{label(:quantity => quantity, :system => system)}" : text
    end

    # Fixed places with trailing zeros dropped; values of `group_from` or more are grouped, and nil never groups.
    def format_number(value, precision, group_from: GROUP_FROM)
      rounded = Kernel.format("%.#{precision}f", value).sub(/\.0+\z/, "").sub(/(\.\d*?)0+\z/, "\\1")
      integer, fraction = rounded.split(".", 2)
      sign = integer.start_with?("-") ? "-" : ""
      digits = integer.delete_prefix("-")
      digits = digits.reverse.scan(/.{1,3}/).join(",").reverse if group_from && digits.to_i >= group_from
      sign + digits + (fraction ? ".#{fraction}" : "")
    end

    def ip?(system)
      system.to_s.upcase == "IP"
    end
    private_class_method :ip?

    def fetch_definition(quantity)
      DEFINITIONS.fetch(quantity.to_s) { raise ArgumentError, "Unknown quantity: #{quantity}" }
    end
    private_class_method :fetch_definition
  end
end
