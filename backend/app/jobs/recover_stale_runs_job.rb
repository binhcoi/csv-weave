# Scheduled every 10 minutes in config/recurring.yml.
class RecoverStaleRunsJob < ApplicationJob
  queue_as :default

  def perform
    # The recovery queries run on every schedule tick and almost always change nothing, so their SQL
    # is kept out of the log. The silence applies only to this thread and lets warnings through.
    Rails.logger.silence(Logger::INFO) do
      [ValidationRun, ConversionRun].each do |model|
        recovered = model.recover_stale!
        Rails.logger.warn("Recovered #{recovered} stale #{model.name} record(s)") if recovered.positive?
      end
    end
  end
end
