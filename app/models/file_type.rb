class FileType < ApplicationRecord
  has_many :columns, -> { order(position: :asc) }, dependent: :destroy
  has_many :input_maps, class_name: "TransformMap",
                        foreign_key: :input_file_type_id, inverse_of: :input_file_type
  has_many :output_maps, class_name: "TransformMap",
                         foreign_key: :output_file_type_id, inverse_of: :output_file_type

  validates :name, presence: true
end
