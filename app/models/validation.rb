class Validation < ApplicationRecord
  belongs_to :column
  belongs_to :column_validator
end
