# Shared lifecycle for ValidationRun and ConversionRun:
#   queued -> running -> succeeded | rejected | failed
# Runs are never retried. Failed runs are not reused, so a new request starts a fresh run.
module ProcessingRun
  extend ActiveSupport::Concern

  FINISHED_STATUSES = %w[succeeded rejected failed].freeze
  # A running job refreshes heartbeat_at this often; a running run is stale after STALE_AFTER without one.
  HEARTBEAT_INTERVAL = 30.seconds
  STALE_AFTER = 15.minutes
  # A running run is stopped after this long even if its heartbeat is fresh (e.g. stuck in a loop over rows).
  MAX_RUNTIME = 12.hours
  # A queued run whose job has not started within this time is assumed lost.
  QUEUED_STALE_AFTER = 24.hours

  included do
    enum :status, { queued: "queued", running: "running", succeeded: "succeeded",
                    rejected: "rejected", failed: "failed" }, validate: true

    has_one_attached :error_report
    validates :configuration_digest, presence: true

    scope :reusable, -> { where.not(status: "failed") }
  end

  class_methods do
    # Mark stale runs as failed so they stop blocking new requests. Returns the number recovered.
    # Each UPDATE re-checks the status, so a run a job claims or finishes concurrently is left alone.
    def recover_stale!(now: Time.current)
      overdue = where(status: "running").where(started_at: ...(now - MAX_RUNTIME))
        .update_all(status: "failed", failure_reason: "run exceeded 12 hours", finished_at: now, updated_at: now)
      running = where(status: "running").where(heartbeat_at: ...(now - STALE_AFTER))
        .update_all(status: "failed", failure_reason: "worker stopped responding", finished_at: now, updated_at: now)
      queued = where(status: "queued").where(created_at: ...(now - QUEUED_STALE_AFTER))
        .update_all(status: "failed", failure_reason: "job did not start within 24 hours", finished_at: now, updated_at: now)
      overdue + running + queued
    end

    private

    # Return the reusable run matching key, or create one with the extra attributes and enqueue it.
    # Returns [run, created]. A run created already finished (e.g. rejected) is not enqueued.
    def find_or_start!(key, attempts: 2, **attributes)
      existing = reusable.find_by(key)
      return [existing, false] if existing

      # Savepoint: a unique violation must not abort a surrounding transaction before the lookup below.
      run = transaction(requires_new: true) { create!(**key, **attributes) }
      run.enqueue_job if run.queued?
      [run, true]
    rescue ActiveRecord::RecordNotUnique
      # A concurrent request created the same run first. If that run has already failed (e.g. its
      # enqueue failed), it is no longer reusable, so try once more to create a fresh run.
      winner = reusable.find_by(key)
      return [winner, false] if winner
      raise if attempts <= 1

      find_or_start!(key, attempts: attempts - 1, **attributes)
    end
  end

  def enqueue_job
    self.class.job_class.perform_later(self)
  rescue StandardError => error
    # Without a job the run would stay queued and block new requests until recovery.
    Rails.logger.error("#{self.class.name} #{id} could not be enqueued: #{error.class}: #{error.message}")
    update_columns(status: "failed", failure_reason: "could not enqueue job (#{error.class})",
                   finished_at: Time.current, updated_at: Time.current)
  end

  def finished?
    FINISHED_STATUSES.include?(status)
  end
end
