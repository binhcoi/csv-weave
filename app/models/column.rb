class Column < ApplicationRecord
  belongs_to :file_type
  has_many :validations, -> { order(:id) }, dependent: :destroy
  has_many :transformations, foreign_key: :output_column_id, inverse_of: :output_column
  validates :name, presence: true, uniqueness: { scope: :file_type_id }
  validates :position, presence: true, uniqueness: { scope: :file_type_id },
                       numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :file_type_matches_transformations, on: :update
  before_destroy :reject_deletion_if_used_by_transformations, prepend: true

  def get_data(row)
    row[name]
  end

  private

  def reject_deletion_if_used_by_transformations
    return unless transformations.exists? || used_as_source?

    errors.add(:base, "cannot delete a column used by a transformation")
    throw :abort
  end

  def used_as_source?
    source_transformations = Transformation.joins(:transform_map)
                                          .where(transform_maps: { input_file_type_id: file_type_id })
                                          .includes(:column_transformer)

    source_transformations.any? do |transformation|
      processor = transformation.column_transformer.get_transformer(transformation)
      processor.source_column_names.include?(name)
    end
  end

  def file_type_matches_transformations
    return unless will_save_change_to_file_type_id? && file_type
    return unless transformations.joins(:transform_map)
                                 .where.not(transform_maps: { output_file_type_id: file_type_id }).exists?

    errors.add(:file_type, "cannot change while transformations target this column")
  end
end
