class Transformation < ApplicationRecord
  belongs_to :transform_map
  belongs_to :output_column, class_name: "Column"
  belongs_to :column_transformer

  validates :output_column_id, uniqueness: { scope: :transform_map_id }
  validates :input_json, input_json: { catalog: :column_transformer }
  validate :output_column_belongs_to_map
  validate :processor_configuration_is_valid

  private

  def processor_configuration_is_valid
    return if errors.any?

    column_transformer.get_transformer(self).validate_configuration
  end

  def output_column_belongs_to_map
    return unless transform_map && output_column
    return if output_column.file_type_id == transform_map.output_file_type_id

    errors.add(:output_column, "must belong to the map's output file type")
  end
end
