module Validators
  class RequiredValidator < BaseValidator
    def validate(row)
      return true if column.get_data(row).present?
      false
    end
  end
end
