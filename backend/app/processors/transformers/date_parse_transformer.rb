module Transformers
  class DateParseTransformer < SingleSourceTransformer
    # input_json = {
    #   "source_column" => "joined_on",
    #   "format" => "%d/%m/%Y",
    #   "output_format" => "%Y-%m-%d"
    # }
    def validate_configuration
      super

      format = input_json["format"] if input_json.is_a?(Hash)
      unless StrictDateParser.valid_format?(format)
        @transformation.errors.add(:input_json, "format must describe a complete date")
      end
      unless output_format.is_a?(String) && !output_format.empty?
        @transformation.errors.add(:input_json, "output_format must be a nonempty string")
      end
    end

    protected

    def transform_value(data, destination)
      if data.blank?
        destination[output_column_name] = nil
        return nil
      end

      value = StrictDateParser.parse(data, input_json.fetch("format"))
      destination[output_column_name] = value&.strftime(output_format)
      return "source column #{source_column_name.inspect} contains an invalid date" unless value

      nil
    end

    private

    def output_format
      return "%Y-%m-%d" unless input_json.is_a?(Hash)

      input_json.fetch("output_format", "%Y-%m-%d")
    end
  end
end
