require "rails_helper"

RSpec.describe RecoverStaleRunsJob, type: :job do
  it "recovers stale validation and conversion runs" do
    expect(ValidationRun).to receive(:recover_stale!).and_return(1)
    expect(ConversionRun).to receive(:recover_stale!).and_return(0)

    described_class.perform_now
  end

  it "is scheduled every 10 minutes in development and production" do
    schedule = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml"))

    %w[development production].each do |env|
      expect(schedule.fetch(env).fetch("recover_stale_runs")).to include("class" => "RecoverStaleRunsJob",
                                                                       "schedule" => "every 10 minutes")
    end
  end

  describe "logging" do
    let(:output) { StringIO.new }

    around do |example|
      original_level = Rails.logger.level
      Rails.logger.broadcast_to(ActiveSupport::Logger.new(output))
      Rails.logger.level = Logger::DEBUG
      example.run
    ensure
      Rails.logger.stop_broadcasting_to(Rails.logger.broadcasts.last)
      Rails.logger.level = original_level
    end

    it "keeps the recovery SQL out of the log" do
      described_class.perform_now

      expect(output.string).not_to include("UPDATE")
    end

    it "still logs recovered runs" do
      allow(ValidationRun).to receive(:recover_stale!).and_return(2)
      allow(ConversionRun).to receive(:recover_stale!).and_return(0)

      described_class.perform_now

      expect(output.string).to include("Recovered 2 stale ValidationRun record(s)")
    end

    it "does not silence logging outside the job" do
      described_class.perform_now
      ValidationRun.where(id: 0).update_all(updated_at: Time.current)

      expect(output.string).to include("UPDATE")
    end
  end
end
