module Transformers
  class BaseTransformer
    def initialize(transformation)
      @transformation = transformation
    end

    def input_columns
      @transformation.transform_map.input_file_type.columns
    end

    def input_json
      @transformation.input_json
    end

    def output_column_name
      @transformation.output_column.name
    end

    # Write to destination and return nil on success or an error message on failure.
    # Expected failures clear the target field and preserve other fields.
    def transform(source, destination)
      raise NotImplementedError, "#{self.class} must implement #transform"
    end

    def source_column_names
      raise NotImplementedError, "#{self.class} must implement #source_column_names"
    end

    def validate_configuration
    end
  end
end
