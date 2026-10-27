require "date"

module Validators
  class DateValidator < BaseValidator
    # input_json = {
    #   "format" => "%d/%m/%Y",
    #   "min" => "2020-01-01",
    #   "max" => "2030-12-31"
    # }
    def validate(row)
      data = column.get_data(row)
      return true if data.blank?

      value = parse_date(data, format)
      return false unless value
      return false if min && value < min
      return false if max && value > max

      true
    end

    def format
      input_json.fetch("format")
    end

    def min
      parse_date(input_json["min"], "%Y-%m-%d")
    end

    def max
      parse_date(input_json["max"], "%Y-%m-%d")
    end

    def validate_configuration
      unless StrictDateParser.valid_format?(format)
        @validation.errors.add(:input_json, "format must describe a complete date")
      end

      ["min", "max"].each do |bound|
        if input_json.key?(bound) && !parse_date(input_json[bound], "%Y-%m-%d")
          @validation.errors.add(:input_json, "#{bound} must be a valid date in YYYY-MM-DD format")
        end
      end
      if min && max && min > max
        @validation.errors.add(:input_json, "require min <= max")
      end
    end

    private

    def parse_date(data, date_format)
      StrictDateParser.parse(data, date_format)
    end
  end
end
