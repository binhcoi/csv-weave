require "rails_helper"

RSpec.describe RecoverStaleRunsJob, type: :job do
  it "recovers stale validation and conversion runs" do
    expect(ValidationRun).to receive(:recover_stale!).and_return(1)
    expect(ConversionRun).to receive(:recover_stale!).and_return(0)

    described_class.perform_now
  end

  it "is scheduled every minute in development and production" do
    schedule = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml"))

    %w[development production].each do |env|
      expect(schedule.fetch(env).fetch("recover_stale_runs")).to include("class" => "RecoverStaleRunsJob",
                                                                       "schedule" => "every minute")
    end
  end
end
