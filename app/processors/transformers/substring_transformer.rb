module Transformers
  class SubstringTransformer < SingleSourceTransformer
    # input_json = {
    #   "source_column" => "product_code",
    #   "start" => 2,
    #   "length" => 4
    # }
    def validate_configuration
      super

      ["start", "length"].each do |setting|
        value = input_json[setting] if input_json.is_a?(Hash)
        next if value.is_a?(Integer) && value >= 0

        @transformation.errors.add(:input_json, "#{setting} must be a nonnegative integer")
      end
    end

    protected

    def transform_value(data, destination)
      destination[output_column_name] = if data.nil?
        nil
      elsif input_json.fetch("start") >= data.length
        ""
      else
        # Clamp to the available text before passing JSON integers to String#slice.
        length = [input_json.fetch("length"), data.length - input_json.fetch("start")].min
        data.slice(input_json.fetch("start"), length)
      end
      nil
    end
  end
end
