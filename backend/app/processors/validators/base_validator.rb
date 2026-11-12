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

    # Describe a failed check without keeping mutable per-row error state.
    def failure_message
      raise NotImplementedError, "#{self.class} must implement #failure_message"
    end

    def validate_configuration
    end
  end
end
