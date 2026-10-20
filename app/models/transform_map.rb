class TransformMap < ApplicationRecord
  belongs_to :input_file_type, class_name: "FileType"
  belongs_to :output_file_type, class_name: "FileType"

  validates :name, presence: true
  validates :input_file_type, presence: true
  validates :output_file_type, presence: true
end
