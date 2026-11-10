require "tempfile"

# Base job for ValidationRun and ConversionRun. Runs are never retried: a run that cannot finish is
# marked failed, and a later request starts a new run. If the worker dies mid-run, the heartbeat
# stops and RecoverStaleRunsJob marks the run failed.
#
# The heartbeat is written from the job thread itself (between CSV records), not a timer thread,
# so a job that hangs also stops its heartbeat and is recovered as stale.
#
# Subclasses implement #execute(run), which returns the final status, runner result, files to
# attach, and failure reason by calling #finish.
class ProcessingRunJob < ApplicationJob
  queue_as :default

  # The run was deleted before the job started; there is nothing to report on.
  discard_on ActiveJob::DeserializationError

  def perform(run)
    return unless claim(run)

    @tempfiles = []
    @run = run
    @last_heartbeat = run.heartbeat_at
    begin
      execute(run)
    rescue ConfigurationValidation::InvalidConfiguration => error
      finish(run, :failed, failure_reason: configuration_reason(error))
    rescue StandardError => error
      # Do not re-raise: this project does not retry runs.
      Rails.logger.error("#{run.class.name} #{run.id} failed: #{error.class}: #{error.message}")
      finish(run, :failed, failure_reason: "unexpected error (#{error.class})")
    ensure
      @tempfiles.each do |file|
        file.close
        File.unlink(file.path) if File.exist?(file.path)
      end
    end
  end

  private

  def tempfile(prefix, extension)
    Tempfile.create([prefix, extension]).tap { |file| @tempfiles << file }
  end

  # Move queued -> running in one UPDATE so a duplicate job delivery cannot process the run twice.
  def claim(run)
    now = Time.current
    claimed = run.class.where(id: run.id, status: "queued")
                 .update_all(status: "running", started_at: now, heartbeat_at: now, updated_at: now)
    run.reload if claimed == 1
    claimed == 1
  end

  # Callable passed to the runners as on_row. Writes at most once per HEARTBEAT_INTERVAL.
  def heartbeat
    @heartbeat ||= lambda do
      now = Time.current
      next if now - @last_heartbeat < ProcessingRun::HEARTBEAT_INTERVAL

      @last_heartbeat = now
      @run.class.where(id: @run.id, status: "running").update_all(heartbeat_at: now)
    end
  end

  # Attach files and write the outcome only while the run is still ours. If recovery already
  # marked it failed, keep that outcome and remove the attachments.
  # attachments: { attachment_name => [file, filename, content_type] }
  def finish(run, status, result: nil, attachments: {}, failure_reason: nil)
    attachments.each do |name, (file, filename, content_type)|
      file.flush
      file.rewind
      run.public_send(name).attach(io: file, filename: filename, content_type: content_type, identify: false)
    end
    now = Time.current
    updated = run.class.where(id: run.id, status: "running").update_all(
      status: status.to_s, failure_reason: failure_reason, finished_at: now, updated_at: now,
      accepted_rows: result&.accepted_rows, rejected_rows: result&.rejected_rows, error_count: result&.error_count,
    )
    purge_attachments(run, attachments.keys) if updated.zero?
    run.reload
  rescue StandardError => error
    # Attaching or saving failed; record the failure without partial files.
    Rails.logger.error("#{run.class.name} #{run.id} could not be finalized: #{error.class}: #{error.message}")
    purge_attachments(run, attachments.keys)
    run.class.where(id: run.id, status: "running").update_all(
      status: "failed", failure_reason: "could not store results (#{error.class})",
      finished_at: Time.current, updated_at: Time.current,
    )
  end

  def purge_attachments(run, names)
    names.each { |name| run.public_send(name).purge if run.public_send(name).attached? }
  end

  def configuration_reason(error)
    details = error.errors.map { |item| "#{item[:resource]} #{item[:id]} #{item[:field]} #{item[:message]}" }
    "invalid configuration: #{details.join('; ')}"
  end
end
