require "tempfile"

# Runs are never retried. A run that cannot finish is marked failed, and a later request starts a new run.
# If the worker dies mid-run, the heartbeat stops and RecoverStaleValidationRunsJob marks the run failed.
class ValidationRunJob < ApplicationJob
  queue_as :default

  # The run was deleted before the job started; there is nothing to report on.
  discard_on ActiveJob::DeserializationError

  def perform(run)
    return unless claim(run)

    report = Tempfile.create(["validation-run-#{run.id}-", ".jsonl"])
    heartbeat = start_heartbeat(run)
    begin
      configuration = FileTypeConfigurationLoader.load(run.file_type_id)
      if FileTypeConfigurationDigest.for(run.file_type_id) != run.configuration_digest
        finish(run, :failed, nil, nil, failure_reason: "configuration changed after the run was requested")
        return
      end

      runner = CsvValidationRunner.new(columns: configuration.columns, validators: configuration.validators)
      result = run.data_file.file.open { |input| runner.run(input: input, error_output: report) }
      finish(run, :succeeded, result, report)
    rescue CsvValidationRunner::InvalidFile => error
      finish(run, :rejected, error.result, report, failure_reason: error.message)
    rescue ConfigurationValidation::InvalidConfiguration => error
      finish(run, :failed, nil, nil, failure_reason: configuration_reason(error))
    rescue StandardError => error
      # Do not re-raise: this project does not retry runs.
      Rails.logger.error("ValidationRun #{run.id} failed: #{error.class}: #{error.message}")
      finish(run, :failed, nil, nil, failure_reason: "unexpected error (#{error.class})")
    ensure
      heartbeat&.shutdown
      report.close
      File.unlink(report.path) if File.exist?(report.path)
    end
  end

  private

  # Move queued -> running in one UPDATE so a duplicate job delivery cannot process the run twice.
  def claim(run)
    now = Time.current
    claimed = ValidationRun.where(id: run.id, status: "queued")
                           .update_all(status: "running", started_at: now, heartbeat_at: now, updated_at: now)
    run.reload if claimed == 1
    claimed == 1
  end

  def start_heartbeat(run)
    task = Concurrent::TimerTask.new(execution_interval: ValidationRun::HEARTBEAT_INTERVAL.to_i) do
      Rails.application.executor.wrap do
        ValidationRun.where(id: run.id, status: "running").update_all(heartbeat_at: Time.current)
      end
    end
    task.execute
    task
  end

  # Write results only while the run is still ours. If recovery already marked it failed, keep that outcome.
  def finish(run, status, result, report, failure_reason: nil)
    attach_report(run, report) if report
    now = Time.current
    updated = ValidationRun.where(id: run.id, status: "running").update_all(
      status: status.to_s, failure_reason: failure_reason, finished_at: now, updated_at: now,
      accepted_rows: result&.accepted_rows, rejected_rows: result&.rejected_rows, error_count: result&.error_count,
    )
    run.error_report.purge if updated.zero? && run.error_report.attached?
    run.reload
  rescue StandardError => error
    # Attaching or saving failed; record the failure without the partial report.
    Rails.logger.error("ValidationRun #{run.id} could not be finalized: #{error.class}: #{error.message}")
    run.error_report.purge if run.error_report.attached?
    ValidationRun.where(id: run.id, status: "running").update_all(
      status: "failed", failure_reason: "could not store results (#{error.class})",
      finished_at: Time.current, updated_at: Time.current,
    )
  end

  def attach_report(run, report)
    report.flush
    report.rewind
    run.error_report.attach(io: report, filename: "validation_run_#{run.id}_errors.jsonl",
                            content_type: "application/x-ndjson", identify: false)
  end

  def configuration_reason(error)
    details = error.errors.map { |item| "#{item[:resource]} #{item[:id]} #{item[:field]} #{item[:message]}" }
    "invalid configuration: #{details.join('; ')}"
  end
end
