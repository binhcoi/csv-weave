module Transformers
  class IntegerParseTransformer < SingleSourceTransformer
    protected

    def transform_value(data, destination)
      if data.blank?
        destination[output_column_name] = nil
        return nil
      end

      value = Integer(data, 10, exception: false)
      destination[output_column_name] = value
      return "source column #{source_column_name.inspect} contains an invalid integer" if value.nil?

      nil
    end
  end
end
