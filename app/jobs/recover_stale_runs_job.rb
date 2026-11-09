# Scheduled every minute in config/recurring.yml.
class RecoverStaleRunsJob < ApplicationJob
  queue_as :default

  def perform
    [ValidationRun, ConversionRun].each do |model|
      recovered = model.recover_stale!
      Rails.logger.warn("Recovered #{recovered} stale #{model.name} record(s)") if recovered.positive?
    end
  end
end
