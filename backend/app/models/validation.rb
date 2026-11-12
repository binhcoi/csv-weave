class Validation < ApplicationRecord
  belongs_to :column
  belongs_to :column_validator

  validates :input_json, input_json: { catalog: :column_validator }
  validate :processor_configuration_is_valid

  private

  def processor_configuration_is_valid
    return if errors.any?

    column_validator.get_validator(self).validate_configuration
  end
end
