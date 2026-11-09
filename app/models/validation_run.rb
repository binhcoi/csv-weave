class ValidationRun < ApplicationRecord
  include ProcessingRun

  belongs_to :data_file
  belongs_to :file_type

  # A run always validates against the file type the data file was uploaded as.
  before_validation :assign_file_type_from_data_file, on: :create
  validate :file_type_matches_data_file, on: :create

  def self.job_class = ValidationRunJob

  # Return the existing run for this data file and its current configuration, or create and
  # enqueue a new one. Returns [run, created]. Failed runs are never reused.
  def self.start!(data_file)
    digest = FileTypeConfigurationDigest.for(data_file.file_type_id)
    find_or_start!({ data_file: data_file, configuration_digest: digest })
  end

  private

  def assign_file_type_from_data_file
    self.file_type_id ||= data_file&.file_type_id
  end

  def file_type_matches_data_file
    return unless data_file && file_type_id

    errors.add(:file_type, "must match the data file's file type") if file_type_id != data_file.file_type_id
  end
end
