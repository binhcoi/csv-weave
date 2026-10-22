class Column < ApplicationRecord
  belongs_to :file_type
  has_many :validations
  has_many :transformations, foreign_key: :output_column_id, inverse_of: :output_column
  validates :name, presence: true, uniqueness: { scope: :file_type_id }
  validates :position, presence: true, uniqueness: { scope: :file_type_id },
                       numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
