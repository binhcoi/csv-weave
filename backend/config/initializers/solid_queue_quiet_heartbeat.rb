# Keeps Solid Queue's process heartbeats out of the development log.
#
# Each Solid Queue process (supervisor, dispatcher, worker, scheduler) records a heartbeat every
# SolidQueue.process_heartbeat_interval, and each one logs four SQL lines at debug level. Solid
# Queue already silences its polling queries this way (SolidQueue.silence_polling) but has no
# setting for heartbeats. The silence is per thread, so it covers only the heartbeat timer thread,
# and an exception raised by a failed heartbeat still propagates to Solid Queue's error handling.
module SolidQueueQuietHeartbeat
  def heartbeat
    logger = ActiveRecord::Base.logger
    logger ? logger.silence { super } : super
  end
end

if Rails.env.development?
  # SolidQueue::Process is reloadable, so the patch is reapplied after every code reload.
  Rails.application.config.to_prepare do
    SolidQueue::Process.prepend(SolidQueueQuietHeartbeat)
  end
end
