require "rails_helper"
require "stringio"

RSpec.describe ValidationRun, type: :model do
  include ActiveJob::TestHelper

  let(:file_type) { FileType.create!(name: "Orders") }
  let(:data_file) do
    DataFile.create!(file_type: file_type, file: {
      io: StringIO.new("id\n1\n"), filename: "orders.csv", content_type: "text/csv", identify: false,
    })
  end

  after { DataFile.find_each { |record| record.file.purge } }

  def create_run(**attributes)
    described_class.create!(data_file: data_file, configuration_digest: "digest", **attributes)
  end

  it "takes its file type from the data file and starts queued with no counts" do
    run = create_run

    expect(run.file_type).to eq(file_type)
    expect(run).to be_queued
    expect([run.accepted_rows, run.rejected_rows, run.error_count, run.started_at]).to all(be_nil)
    expect(run).not_to be_finished
  end

  it "rejects a file type that differs from the data file's" do
    run = described_class.new(data_file: data_file, configuration_digest: "digest",
                              file_type: FileType.create!(name: "Other"))

    expect(run).not_to be_valid
    expect(run.errors[:file_type]).to include("must match the data file's file type")
  end

  it "requires a data file and a configuration digest" do
    run = described_class.new

    expect(run).not_to be_valid
    expect(run.errors[:data_file]).to include("must exist")
    expect(run.errors[:configuration_digest]).to include("can't be blank")
  end

  it "rejects unknown statuses in the model and the database" do
    run = create_run

    run.status = "paused"
    expect(run).not_to be_valid
    expect do
      described_class.transaction(requires_new: true) { run.update_columns(status: "paused") }
    end.to raise_error(ActiveRecord::StatementInvalid, /status_check/)
  end

  it "counts succeeded, rejected, and failed as finished" do
    run = described_class.new
    expect(%w[queued running succeeded rejected failed].map { |status| run.tap { it.status = status }.finished? })
      .to eq([false, false, true, true, true])
  end

  it "allows only one non-failed run per data file and digest in the database" do
    create_run(status: "failed")
    create_run(status: "succeeded")

    expect { described_class.transaction(requires_new: true) { create_run } }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(create_run(configuration_digest: "other")).to be_persisted
  end

  describe ".start!" do
    it "creates and enqueues a run with the current configuration digest" do
      run, created = nil
      expect { run, created = described_class.start!(data_file) }.to have_enqueued_job(ValidationRunJob).with(anything)

      expect(created).to be(true)
      expect(run.configuration_digest).to eq(FileTypeConfigurationDigest.for(file_type.id))
    end

    it "reuses a queued, running, succeeded, or rejected run without enqueuing" do
      first, = described_class.start!(data_file)

      %w[queued running succeeded rejected].each do |status|
        first.update_columns(status: status)
        run, created = nil
        expect { run, created = described_class.start!(data_file) }.not_to have_enqueued_job
        expect([run, created]).to eq([first, false]), "expected reuse for #{status}"
      end
    end

    it "starts a new run after the previous one failed" do
      first, = described_class.start!(data_file)
      first.update_columns(status: "failed")

      run, created = described_class.start!(data_file)

      expect(created).to be(true)
      expect(run).not_to eq(first)
    end

    it "starts a new run after the file type's configuration changes" do
      first, = described_class.start!(data_file)
      first.update_columns(status: "succeeded")
      file_type.columns.create!(name: "amount", position: 1)

      run, created = described_class.start!(data_file)

      expect(created).to be(true)
      expect(run.configuration_digest).not_to eq(first.configuration_digest)
    end

    it "returns the concurrent winner when the unique index rejects a duplicate" do
      winner = create_run(configuration_digest: FileTypeConfigurationDigest.for(file_type.id))
      allow(described_class).to receive(:reusable).and_wrap_original do |original|
        # Simulate the race: the first lookup misses, then the insert collides.
        @lookups = (@lookups || 0) + 1
        @lookups == 1 ? described_class.none : original.call
      end

      run, created = described_class.start!(data_file)

      expect([run, created]).to eq([winner, false])
    end

    it "marks the run failed when the job cannot be enqueued, so a later request can start again" do
      allow(ValidationRunJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")

      run, created = described_class.start!(data_file)

      expect(created).to be(true)
      expect(run.reload).to be_failed
      expect(run.failure_reason).to eq("could not enqueue job (ActiveJob::EnqueueError)")
    end
  end

  describe ".recover_stale!" do
    it "fails running runs without a recent heartbeat and leaves others alone" do
      now = Time.current
      stale = create_run(configuration_digest: "a", status: "running", heartbeat_at: now - 16.minutes)
      fresh = create_run(configuration_digest: "b", status: "running", heartbeat_at: now - 14.minutes)
      done = create_run(configuration_digest: "c", status: "succeeded", heartbeat_at: now - 1.hour)

      expect(described_class.recover_stale!(now: now)).to eq(1)

      expect(stale.reload).to be_failed
      expect(stale.failure_reason).to eq("worker stopped responding")
      expect(stale.finished_at).to be_within(1.second).of(now)
      expect(fresh.reload).to be_running
      expect(done.reload).to be_succeeded
    end

    it "fails queued runs older than 24 hours and leaves newer queued runs alone" do
      now = Time.current
      lost = create_run(configuration_digest: "a", created_at: now - 25.hours)
      waiting = create_run(configuration_digest: "b", created_at: now - 23.hours)

      expect(described_class.recover_stale!(now: now)).to eq(1)

      expect(lost.reload).to be_failed
      expect(lost.failure_reason).to eq("job did not start within 24 hours")
      expect(waiting.reload).to be_queued
    end

    it "lets a new request start after a lost queued run is recovered" do
      lost, = described_class.start!(data_file)
      lost.update_columns(created_at: 25.hours.ago)

      described_class.recover_stale!
      run, created = described_class.start!(data_file)

      expect(created).to be(true)
      expect(run).not_to eq(lost)
    end
  end
end
