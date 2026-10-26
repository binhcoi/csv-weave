module Transformers
  class CopyTransformer < SingleSourceTransformer
    protected

    def transform_value(data, destination)
      destination[output_column_name] = data
      nil
    end
  end
end
