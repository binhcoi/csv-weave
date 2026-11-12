require "rails_helper"
require_relative "../support/conversion_run_context"

RSpec.describe ConversionRun, type: :model do
  include ActiveJob::TestHelper
  include_context "conversion run records"

  let(:data_file) { upload("name,amount\nAda,3\n") }

  after { purge_conversion_files }

  def create_run(**attributes)
    described_class.create!(data_file: data_file, transform_map: transform_map, configuration_digest: "digest", **attributes)
  end

  it "requires a data file, a transform map, and a configuration digest" do
    run = described_class.new

    expect(run).not_to be_valid
    expect(run.errors.attribute_names).to include(:data_file, :transform_map, :configuration_digest)
  end

  it "rejects unknown statuses in the database" do
    run = create_run

    expect do
      described_class.transaction(requires_new: true) { run.update_columns(status: "paused") }
    end.to raise_error(ActiveRecord::StatementInvalid, /status_check/)
  end

  it "allows only one non-failed run per data file, map, and digest in the database" do
    create_run(status: "failed")
    create_run(status: "succeeded")

    expect { described_class.transaction(requires_new: true) { create_run } }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(create_run(configuration_digest: "other")).to be_persisted
  end

  describe ".start!" do
    it "creates and enqueues a run with the current configuration digest" do
      run, created = nil
      expect { run, created = described_class.start!(data_file, transform_map) }.to have_enqueued_job(ConversionRunJob)

      expect(created).to be(true)
      expect(run).to be_queued
      expect(run.configuration_digest).to eq(ConversionConfigurationDigest.for(transform_map.id))
    end

    it "rejects a data file whose file type is not the map's input type without enqueuing" do
      other_file = upload("name,amount\nAda,3\n", file_type: output_type)

      run, created = nil
      expect { run, created = described_class.start!(other_file, transform_map) }.not_to have_enqueued_job

      expect(created).to be(true)
      expect(run).to be_rejected
      expect(run).to be_file_type_mismatch
      expect(run.finished_at).to be_present
      expect(described_class.start!(other_file, transform_map)).to eq([run, false])
    end

    it "reuses a queued, running, succeeded, or rejected run without enqueuing" do
      first, = described_class.start!(data_file, transform_map)

      %w[queued running succeeded rejected].each do |status|
        first.update_columns(status: status)
        result = nil
        expect { result = described_class.start!(data_file, transform_map) }.not_to have_enqueued_job
        expect(result).to eq([first, false]), "expected reuse for #{status}"
      end
    end

    it "starts a new run after a failure" do
      first, = described_class.start!(data_file, transform_map)
      first.update_columns(status: "failed")

      run, created = described_class.start!(data_file, transform_map)

      expect(created).to be(true)
      expect(run).not_to eq(first)
    end

    {
      "a transformation changes" => -> { transform_map.transformations.first.update!(input_json: { "source_column" => "amount" }) },
      "an input file type validation changes" => -> { input_type.columns.first.validations.first.destroy! },
      "an output file type column is added" => -> { output_type.columns.create!(name: "note", position: 2) },
    }.each do |description, change|
      it "starts a new run after #{description}" do
        first, = described_class.start!(data_file, transform_map)
        first.update_columns(status: "succeeded")
        instance_exec(&change)

        run, created = described_class.start!(data_file, transform_map)

        expect(created).to be(true)
        expect(run.configuration_digest).not_to eq(first.configuration_digest)
      end
    end

    it "keeps reusing the run after only the map's name changes" do
      first, = described_class.start!(data_file, transform_map)
      transform_map.update!(name: "Renamed")

      expect(described_class.start!(data_file, transform_map)).to eq([first, false])
    end

    it "keeps separate runs for different maps on the same file" do
      other_map = TransformMap.create!(name: "Other", input_file_type: input_type, output_file_type: output_type)

      first, = described_class.start!(data_file, transform_map)
      second, created = described_class.start!(data_file, other_map)

      expect(created).to be(true)
      expect(second).not_to eq(first)
    end

    it "marks the run failed when the job cannot be enqueued" do
      allow(ConversionRunJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")

      run, = described_class.start!(data_file, transform_map)

      expect(run.reload).to be_failed
      expect(run.failure_reason).to eq("could not enqueue job (ActiveJob::EnqueueError)")
    end
  end

  describe ".recover_stale!" do
    it "fails stale running and queued runs and leaves fresh ones alone" do
      now = Time.current
      stale_running = create_run(configuration_digest: "a", status: "running", heartbeat_at: now - 16.minutes)
      fresh_running = create_run(configuration_digest: "b", status: "running", heartbeat_at: now - 14.minutes)
      lost_queued = create_run(configuration_digest: "c", created_at: now - 25.hours)
      waiting = create_run(configuration_digest: "d", created_at: now - 23.hours)

      expect(described_class.recover_stale!(now: now)).to eq(2)

      expect([stale_running, fresh_running, lost_queued, waiting].map { it.reload.status })
        .to eq(%w[failed running failed queued])
    end
  end

  it "blocks deleting a transform map that has conversion runs" do
    create_run

    expect(transform_map.destroy).to be(false)
    expect(transform_map.errors[:base]).to include("cannot delete a transform map used by a conversion run")
  end
end
