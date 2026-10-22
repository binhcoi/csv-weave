class Validation < ApplicationRecord
  belongs_to :column
  belongs_to :column_validator

  validates :input_json, input_json: { catalog: :column_validator }
end
