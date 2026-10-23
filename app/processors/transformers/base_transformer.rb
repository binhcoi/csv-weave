module Transformers
  class BaseTransformer
    def initialize(transformation)
      @transformation = transformation
    end

    def transform(source, destination)
      raise NotImplementedError, "#{self.class} must implement #transform"
    end

    def column_data(row, name, position)
      # TODO: implement source-column selection when row processing is defined.
      raise NotImplementedError, "Transformer row access is not implemented"
    end

    def validate
    end
  end
end
