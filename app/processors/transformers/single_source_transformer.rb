module Transformers
  class SingleSourceTransformer < BaseTransformer
    # input_json = {
    #   "source_column" => "source_column_name"
    # }
    def transform(source, destination)
      input_column = input_columns.find { |column| column.name == source_column_name }
      unless input_column
        destination[output_column_name] = nil
        return "source column #{source_column_name.inspect} does not exist in the map's input file type"
      end

      transform_value(input_column.get_data(source), destination)
    end

    def validate_configuration
      return if input_columns.any? { |column| column.name == source_column_name }

      @transformation.errors
        .add(:input_json, "source column #{source_column_name.inspect} does not exist in the map's input file type")
    end

    def source_column_name
      return "" unless input_json.is_a?(Hash)

      input_json["source_column"]
    end

    def source_column_names
      [source_column_name]
    end

    protected

    def transform_value(data, destination)
      raise NotImplementedError, "#{self.class} must implement #transform_value"
    end
  end
end
