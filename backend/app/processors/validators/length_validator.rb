module Validators
  class LengthValidator < BaseValidator
    # input_json = {
    #   "min" => 50,
    #   "max" => 100
    # }
    def validate(row)
      data = column.get_data(row)
      return false if !min.nil? && (data&.length || 0) < min
      return false if !max.nil? && (data&.length || 0) > max
      true
    end

    def min
      input_json.fetch("min", nil)
    end

    def failure_message
      bounds = []
      bounds << ">= #{min}" if min
      bounds << "<= #{max}" if max
      "length must be #{bounds.join(' and ')}"
    end

    def max
      input_json.fetch("max", nil)
    end

    def validate_configuration
      if min.nil? && max.nil?
        @validation.errors.add(:input_json, "must include at least upper or lower length limit")
      end
      if min && max && min > max
        @validation.errors.add(:input_json, "require min <= max")
      end
    end
  end
end
