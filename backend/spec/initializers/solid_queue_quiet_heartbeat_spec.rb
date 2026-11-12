require "rails_helper"

RSpec.describe SolidQueueQuietHeartbeat do
  # The development-only initializer prepends this module to SolidQueue::Process. If a Solid Queue
  # upgrade renames the method, the prepend would silently stop having any effect.
  it "targets a heartbeat method that SolidQueue::Process still defines" do
    expect(SolidQueue::Process.instance_method(:heartbeat).owner).to eq(SolidQueue::Process)
  end

  describe "#heartbeat" do
    let(:output) { StringIO.new }
    let(:logger) { ActiveSupport::Logger.new(output).tap { |log| log.level = Logger::DEBUG } }
    let(:process_class) do
      Class.new do
        def heartbeat
          ActiveRecord::Base.logger.debug("heartbeat SQL")
          :touched
        end
      end.prepend(described_class)
    end

    around do |example|
      original = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = logger
      example.run
    ensure
      ActiveRecord::Base.logger = original
    end

    it "runs the heartbeat without logging its SQL" do
      expect(process_class.new.heartbeat).to eq(:touched)
      expect(output.string).to be_empty
    end

    it "leaves logging on after the heartbeat" do
      process_class.new.heartbeat
      ActiveRecord::Base.logger.debug("later query")

      expect(output.string).to include("later query")
    end

    it "lets a failed heartbeat raise" do
      failing = Class.new { def heartbeat = raise(ActiveRecord::ConnectionNotEstablished) }.prepend(described_class)

      expect { failing.new.heartbeat }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    end
  end
end
