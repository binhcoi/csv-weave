class RecoverStaleValidationRunsJob < ApplicationJob
  queue_as :default

  def perform
    recovered = ValidationRun.recover_stale!
    Rails.logger.warn("Recovered #{recovered} stale validation run(s)") if recovered.positive?
  end
end
