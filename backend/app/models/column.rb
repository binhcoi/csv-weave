class Column < ApplicationRecord
  belongs_to :file_type
  has_many :validations, -> { order(:id) }, dependent: :destroy
  has_many :transformations, foreign_key: :output_column_id, inverse_of: :output_column
  validates :name, presence: true, uniqueness: { scope: :file_type_id }
  validates :position, presence: true, uniqueness: { scope: :file_type_id },
                       numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :file_type_cannot_change, on: :update
  before_destroy :reject_deletion_if_used_by_transformations, prepend: true
  after_update :rename_transformation_sources, if: :saved_change_to_name?

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
    source_transformations.any? do |transformation|
      processor = transformation.column_transformer.get_transformer(transformation)
      processor.source_column_names.include?(name_in_database)
    end
  end

  def source_transformations
    Transformation.joins(:transform_map)
                  .where(transform_maps: { input_file_type_id: file_type_id_in_database })
                  .includes(:column_transformer).order(:id)
  end

  def rename_transformation_sources
    old_name, new_name = saved_change_to_name
    source_transformations.each do |transformation|
      processor = transformation.column_transformer.get_transformer(transformation)
      next unless processor.source_column_names.include?(old_name)

      transformation.update!(input_json: processor.renamed_source_configuration(old_name, new_name))
    end
  rescue ActiveRecord::RecordInvalid => error
    errors.add(:name, "cannot rename because transformation #{error.record.id} is invalid: #{error.record.errors.full_messages.join(', ')}")
    raise ActiveRecord::RecordInvalid.new(self)
  end

  def file_type_cannot_change
    return unless will_save_change_to_file_type_id?

    errors.add(:file_type, "cannot change after the column is created")
  end
end
