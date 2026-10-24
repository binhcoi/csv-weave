class Column < ApplicationRecord
  belongs_to :file_type
  has_many :validations
  has_many :transformations, foreign_key: :output_column_id, inverse_of: :output_column
  validates :name, presence: true, uniqueness: { scope: :file_type_id }
  validates :position, presence: true, uniqueness: { scope: :file_type_id },
                       numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :file_type_matches_transformations, on: :update

  def get_data(row)
    row[name]
  end

  private

  def file_type_matches_transformations
    return unless will_save_change_to_file_type_id? && file_type
    return unless transformations.joins(:transform_map)
                                 .where.not(transform_maps: { output_file_type_id: file_type_id }).exists?

    errors.add(:file_type, "cannot change while transformations target this column")
  end
end
