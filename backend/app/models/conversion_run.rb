class ConversionRun < ApplicationRecord
  include ProcessingRun

  FILE_TYPE_MISMATCH = "data file's file type does not match the transform map's input file type".freeze

  belongs_to :data_file
  belongs_to :transform_map
  has_one_attached :output

  def self.job_class = ConversionRunJob

  # Return the existing run for this data file, map, and current configuration, or create one.
  # Returns [run, created]. A data file whose file type is not the map's input type gets a run that
  # is rejected immediately and never enqueued. Failed runs are never reused.
  def self.start!(data_file, transform_map)
    digest = ConversionConfigurationDigest.for(transform_map.id)
    key = { data_file: data_file, transform_map: transform_map, configuration_digest: digest }
    if data_file.file_type_id == transform_map.input_file_type_id
      find_or_start!(key)
    else
      find_or_start!(key, status: "rejected", failure_reason: FILE_TYPE_MISMATCH, finished_at: Time.current)
    end
  end

  def file_type_mismatch?
    rejected? && failure_reason == FILE_TYPE_MISMATCH
  end
end
