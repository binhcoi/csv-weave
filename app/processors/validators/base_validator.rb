module Validators
  class BaseValidator
    def initialize(validation)
      @validation = validation
    end

    def input_json
      @validation.input_json
    end

    def column
      @validation.column
    end

    def validate(row)
      raise NotImplementedError, "#{self.class} must implement #validate"
    end

    def validate_configuration
    end
  end
end
