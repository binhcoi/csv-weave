module Transformers
  class CopyTransformer < BaseTransformer
    # input_json = {
    #   "name" => "source_column_name"
    # }
    def transform(source, destination)
      column_data(source, @transformation.input_json["name"], nil)
    end

    def validate
      input_json = @transformation.input_json
      source_name = input_json["name"] if input_json.is_a?(Hash)
      input_columns = @transformation.transform_map.input_file_type.columns
      return if input_columns.any? { |column| column.name == source_name }

      @transformation.errors.add(:input_json, "source column #{source_name.inspect} does not exist in the map's input file type")
    end
  end
end
