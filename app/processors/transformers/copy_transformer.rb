module Transformers
  class CopyTransformer < BaseTransformer
    # input_json = {
    #   "name" => "source_column_name"
    # }
    def transform(source, destination)
      input_column = input_columns.find { |column| column.name == source_column_name }
      destination[output_column_name] = input_column.get_data(source)
    end

    def validate
      return if input_columns.any? { |column| column.name == source_column_name }

      @transformation.errors.add(:input_json, "source column #{source_column_name.inspect} does not exist in the map's input file type")
    end

    def source_column_name
      return "" unless input_json.is_a?(Hash)
      input_json["name"]
    end

    def source_column_names
      [source_column_name]
    end
  end
end
