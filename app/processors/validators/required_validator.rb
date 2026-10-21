module Validators
  class RequiredValidator < BaseValidator
    def validate(row)
      return true if column_data(row).present?
      false
    end
  end
end
