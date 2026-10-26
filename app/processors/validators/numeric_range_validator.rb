require "bigdecimal"

module Validators
  class NumericRangeValidator < BaseValidator
    # input_json = { "min" => -10, "max" => 100.5 }
    def validate(row)
      data = column.get_data(row)
      return true if data.blank?

      value = BigDecimal(data.to_s, exception: false)
      return false unless value&.finite?
      return false if min && value < min
      return false if max && value > max

      true
    end

    def min
      value = input_json["min"]
      BigDecimal(value.to_s) unless value.nil?
    end

    def max
      value = input_json["max"]
      BigDecimal(value.to_s) unless value.nil?
    end

    def validate_configuration
      if min.nil? && max.nil?
        @validation.errors.add(:input_json, "must include at least one numeric bound")
      end
      if min && max && min > max
        @validation.errors.add(:input_json, "require min <= max")
      end
    end
  end
end
