module Transformers
  class CopyTransformer < BaseTransformer
    def transform(source, destination)
      column_data(source, @input_json["name"], nil)
    end
  end
end
