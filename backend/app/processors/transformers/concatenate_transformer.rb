module Transformers
  class ConcatenateTransformer < BaseTransformer
    # input_json = {
    #   "source_columns" => ["given_name", "family_name"],
    #   "separator" => " "
    # }
    def transform(source, destination)
      if source_column_names.empty?
        destination[output_column_name] = nil
        return "must include at least one source column"
      end

      columns = input_columns.index_by(&:name)
      values = []
      source_column_names.each do |name|
        input_column = columns[name]
        unless input_column
          destination[output_column_name] = nil
          return "source column #{name.inspect} does not exist in the map's input file type"
        end

        values << input_column.get_data(source)
      end

      destination[output_column_name] = values.reject(&:blank?).join(separator)
      nil
    end

    def source_column_names
      return [] unless input_json.is_a?(Hash)

      names = input_json["source_columns"]
      names.is_a?(Array) ? names : []
    end

    def separator
      input_json.fetch("separator", "")
    end

    def validate_configuration
      if source_column_names.empty?
        @transformation.errors.add(:input_json, "must include at least one source column")
        return
      end

      columns = input_columns.index_by(&:name)
      source_column_names.uniq.each do |name|
        next if columns.key?(name)

        @transformation.errors
          .add(:input_json, "source column #{name.inspect} does not exist in the map's input file type")
      end
    end
  end
end
