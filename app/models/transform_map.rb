class TransformMap < ApplicationRecord
  belongs_to :input_file_type, class_name: "FileType"
  belongs_to :output_file_type, class_name: "FileType"
  has_many :transformations, -> { order(:id) }, dependent: :destroy

  validates :name, presence: true
  validates :input_file_type, presence: true
  validates :output_file_type, presence: true
  validate :output_file_type_matches_transformations, on: :update

  private

  def output_file_type_matches_transformations
    return unless will_save_change_to_output_file_type_id? && output_file_type
    return unless transformations.joins(:output_column)
                                 .where.not(columns: { file_type_id: output_file_type_id }).exists?

    errors.add(:output_file_type, "cannot change while transformations target a different file type")
  end
end
