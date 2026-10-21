class Column < ApplicationRecord
  belongs_to :file_type
  validates :name, presence: true, uniqueness: { scope: :file_type_id }
  validates :position, presence: true, uniqueness: { scope: :file_type_id },
                       numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
