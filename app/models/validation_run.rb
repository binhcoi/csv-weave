class ValidationRun < ApplicationRecord
  belongs_to :data_file
  belongs_to :file_type
  has_one_attached :error_report

  enum :status, { queued: "queued", running: "running", succeeded: "succeeded",
                  rejected: "rejected", failed: "failed" }, validate: true

  FINISHED_STATUSES = %w[succeeded rejected failed].freeze
  # A running job refreshes heartbeat_at this often; a running run is stale after STALE_AFTER without one.
  HEARTBEAT_INTERVAL = 30.seconds
  STALE_AFTER = 15.minutes
  # A queued run whose job has not started within this time is assumed lost.
  QUEUED_STALE_AFTER = 24.hours

  # A run always validates against the file type the data file was uploaded as.
  before_validation :assign_file_type_from_data_file, on: :create
  validates :configuration_digest, presence: true
  validate :file_type_matches_data_file, on: :create

  scope :reusable, -> { where.not(status: "failed") }

  # Return the existing run for this data file and its current configuration, or create and
  # enqueue a new one. Returns [run, created]. Failed runs are never reused.
  def self.start!(data_file)
    digest = FileTypeConfigurationDigest.for(data_file.file_type_id)
    existing = reusable.find_by(data_file: data_file, configuration_digest: digest)
    return [existing, false] if existing

    # Savepoint: a unique violation must not abort a surrounding transaction before the lookup below.
    run = transaction(requires_new: true) { create!(data_file: data_file, configuration_digest: digest) }
    run.enqueue_job
    [run, true]
  rescue ActiveRecord::RecordNotUnique
    # A concurrent request created the same run first.
    [reusable.find_by!(data_file: data_file, configuration_digest: digest), false]
  end

  # Mark stale runs as failed so they stop blocking new requests. Returns the number recovered.
  # Each UPDATE re-checks the status, so a run a job claims or finishes concurrently is left alone.
  def self.recover_stale!(now: Time.current)
    running = where(status: "running").where(heartbeat_at: ...(now - STALE_AFTER))
      .update_all(status: "failed", failure_reason: "worker stopped responding", finished_at: now, updated_at: now)
    queued = where(status: "queued").where(created_at: ...(now - QUEUED_STALE_AFTER))
      .update_all(status: "failed", failure_reason: "job did not start within 24 hours", finished_at: now, updated_at: now)
    running + queued
  end

  def enqueue_job
    ValidationRunJob.perform_later(self)
  rescue StandardError => error
    # Without a job the run would stay queued forever and block new requests.
    Rails.logger.error("ValidationRun #{id} could not be enqueued: #{error.class}: #{error.message}")
    update_columns(status: "failed", failure_reason: "could not enqueue job (#{error.class})",
                   finished_at: Time.current, updated_at: Time.current)
  end

  def finished?
    FINISHED_STATUSES.include?(status)
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
