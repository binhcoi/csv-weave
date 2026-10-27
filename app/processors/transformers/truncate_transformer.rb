module Transformers
  class TruncateTransformer < SingleSourceTransformer
    # input_json = {
    #   "source_column" => "description",
    #   "length" => 20
    # }
    def validate_configuration
      super

      length = input_json["length"] if input_json.is_a?(Hash)
      return if length.is_a?(Integer) && length >= 0

      @transformation.errors.add(:input_json, "length must be a nonnegative integer")
    end

    protected

    def transform_value(data, destination)
      destination[output_column_name] = unless data.nil?
        # Clamp to the available text before passing JSON integers to String#slice.
        data.slice(0, [input_json.fetch("length"), data.length].min)
      end
      nil
    end
  end
end
