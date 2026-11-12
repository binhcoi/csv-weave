require "bigdecimal"

module Transformers
  class DecimalParseTransformer < SingleSourceTransformer
    protected

    def transform_value(data, destination)
      if data.blank?
        destination[output_column_name] = nil
        return nil
      end

      value = BigDecimal(data, exception: false)
      value = nil unless value&.finite?
      destination[output_column_name] = value
      return "source column #{source_column_name.inspect} contains an invalid decimal" if value.nil?

      nil
    end
  end
end
