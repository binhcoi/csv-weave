require "bigdecimal"

module Validators
  class NumericComparisonValidator < ColumnComparisonValidator
    protected

    def comparison_value(data)
      value = BigDecimal((data.presence || 0).to_s, exception: false)
      value if value&.finite?
    end
  end
end
