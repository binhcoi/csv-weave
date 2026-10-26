module Validators
  class ColumnComparisonValidator < BaseValidator
    OPERATORS = ["==", "!=", "<", "<=", ">", ">="].freeze

    # input_json = {
    #   "other_column" => "maximum_amount",
    #   "operator" => "<="
    # }
    def validate(row)
      other = other_column
      return false unless other && OPERATORS.include?(operator)

      left = comparison_value(column.get_data(row))
      right = comparison_value(other.get_data(row))
      return false if left.nil? || right.nil?

      left.public_send(operator, right)
    end

    def other_column_name
      return "" unless input_json.is_a?(Hash)

      input_json["other_column"]
    end

    def other_column
      column.file_type.columns.find { |candidate| candidate.name == other_column_name }
    end

    def operator
      input_json.fetch("operator")
    end

    def validate_configuration
      return if other_column

      @validation.errors.add(:input_json, "other column #{other_column_name.inspect} does not exist in the column's file type")
    end

    protected

    def comparison_value(data)
      raise NotImplementedError, "#{self.class} must implement #comparison_value"
    end
  end
end
