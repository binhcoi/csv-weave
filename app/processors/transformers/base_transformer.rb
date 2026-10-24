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

    def transform(source, destination)
      raise NotImplementedError, "#{self.class} must implement #transform"
    end

    def source_column_names
      raise NotImplementedError, "#{self.class} must implement #source_column_names"
    end

    def validate
    end
  end
end
