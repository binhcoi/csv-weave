module Validators
  class BaseValidator
    def initialize(column, input_json)
      @column = column
      @input_json = input_json
    end

    def validate(row)
      raise NotImplementedError, "#{self.class} must implement #validate"
    end

    def column_data(row)
      # row.get(@column.position) # TODO: placeholder code. get current column data based on position/name

      "test_data"
    end

    def get_column_data(row, position, name)
      # row.get(position) # TODO: placeholder code. get other column data based on position/name

      "test_other_data"
    end
  end
end
