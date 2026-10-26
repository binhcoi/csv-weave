module Validators
  class StringComparisonValidator < ColumnComparisonValidator
    protected

    def comparison_value(data)
      data.presence.to_s
    end
  end
end
