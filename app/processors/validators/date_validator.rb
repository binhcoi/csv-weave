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
      sample = Date.new(2000, 2, 29, Date::GREGORIAN).strftime(format)
      unless parse_date(sample, format)
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
      return unless data.is_a?(String)

      parts = Date._strptime(data, date_format)
      return unless parts && complete_date?(parts)

      value = Date.strptime(data, date_format, Date::GREGORIAN)
      value if value.strftime(date_format) == data
    rescue Date::Error
      nil
    end

    def complete_date?(parts)
      (parts[:year] && parts[:mon] && parts[:mday]) ||
        (parts[:year] && parts[:yday]) ||
        (parts[:cwyear] && parts[:cweek] && parts[:cwday])
    end
  end
end
