class Transformation < ApplicationRecord
  belongs_to :transform_map
  belongs_to :output_column, class_name: "Column"
  belongs_to :column_transformer

  validates :output_column_id, uniqueness: { scope: :transform_map_id }
  validates :input_json, input_json: { catalog: :column_transformer }
end
