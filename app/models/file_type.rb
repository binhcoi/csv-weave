class FileType < ApplicationRecord
  has_many :data_files
  has_many :columns, -> { order(position: :asc) }, dependent: :destroy
  has_many :input_maps, class_name: "TransformMap",
                        foreign_key: :input_file_type_id, inverse_of: :input_file_type
  has_many :output_maps, class_name: "TransformMap",
                         foreign_key: :output_file_type_id, inverse_of: :output_file_type

  validates :name, presence: true
  before_destroy :reject_deletion_if_used_by_maps, prepend: true
  before_destroy :reject_deletion_if_used_by_data_files, prepend: true

  private

  def reject_deletion_if_used_by_data_files
    return unless data_files.exists?

    errors.add(:base, "cannot delete a file type used by a data file")
    throw :abort
  end

  def reject_deletion_if_used_by_maps
    return unless input_maps.exists? || output_maps.exists?

    errors.add(:base, "cannot delete a file type used by a transform map")
    throw :abort
  end
end
