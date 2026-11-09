require "rails_helper"
require "json"
require_relative "../support/conversion_run_context"

RSpec.describe ConversionRunJob, type: :job do
  include_context "conversion run records"

  after { purge_conversion_files }

  def create_run(content)
    ConversionRun.create!(data_file: upload(content), transform_map: transform_map,
                          configuration_digest: ConversionConfigurationDigest.for(transform_map.id))
  end

  def report_entries(run)
    run.error_report.download.each_line.map { |line| JSON.parse(line) }
  end

  it "attaches converted output and the error report and records counts" do
    run = create_run("name,amount\nAda,3\n,4\nBo,x\nCy,5\n")

    described_class.perform_now(run)
    run.reload

    expect(run).to be_succeeded
    expect([run.accepted_rows, run.rejected_rows, run.error_count]).to eq([2, 2, 2])
    expect([run.started_at, run.heartbeat_at, run.finished_at]).to all(be_present)
    expect(run.output.download).to eq("name,total\nAda,3\nCy,5\n")
    expect(run.output.filename.to_s).to eq("conversion_run_#{run.id}.csv")
    expect(run.output.content_type).to eq("text/csv")
    expect(report_entries(run).map { it.values_at("record_number", "stage", "column") })
      .to eq([[3, "input_validation", "name"], [4, "transformation", "total"]])
  end

  it "writes only the output header when every row is rejected" do
    run = create_run("name,amount\n,1\n")

    described_class.perform_now(run)
    run.reload

    expect(run).to be_succeeded
    expect(run.output.download).to eq("name,total\n")
    expect(run.rejected_rows).to eq(1)
  end

  it "rejects an invalid file, keeps the report, and discards partial output" do
    run = create_run("name,amount\nAda,3\n\"open,x\n")

    described_class.perform_now(run)
    run.reload

    expect(run).to be_rejected
    expect(run.accepted_rows).to eq(1)
    expect(run.failure_reason).to be_present
    expect(report_entries(run).last).to include("stage" => "parsing")
    expect(run.output).not_to be_attached
  end

  it "rejects a file missing input headers" do
    run = create_run("name\nAda\n")

    described_class.perform_now(run)
    run.reload

    expect(run).to be_rejected
    expect(run.failure_reason).to eq('missing headers: "amount"')
    expect(run.output).not_to be_attached
  end

  it "fails without files when the saved configuration is invalid" do
    run = create_run("name,amount\nAda,3\n")
    copy.update_column(:processor_class, "MissingTransformer")

    described_class.perform_now(run)
    run.reload

    expect(run).to be_failed
    expect(run.failure_reason).to start_with("invalid configuration: column_transformer #{copy.id} processor_class")
    expect([run.output, run.error_report]).to all(satisfy { !it.attached? })
  end

  it "fails when the configuration changed between request and start" do
    run = create_run("name,amount\nAda,3\n")
    output_type.columns.create!(name: "note", position: 2)

    described_class.perform_now(run)

    expect(run.reload).to be_failed
    expect(run.failure_reason).to eq("configuration changed after the run was requested")
  end

  it "fails on an unexpected exception without re-raising or keeping files" do
    run = create_run("name,amount\nAda,3\n")
    allow_any_instance_of(CsvConversionRunner).to receive(:run).and_raise(IOError, "disk gone")

    expect { described_class.perform_now(run) }.not_to raise_error
    run.reload

    expect(run).to be_failed
    expect(run.failure_reason).to eq("unexpected error (IOError)")
    expect([run.output, run.error_report]).to all(satisfy { !it.attached? })
  end

  it "fails and removes already attached files when storing the second file fails" do
    run = create_run("name,amount\nAda,3\n")
    calls = 0
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_wrap_original do |original, **kw|
      calls += 1
      raise ActiveRecord::ActiveRecordError, "boom" if calls == 2

      original.call(**kw)
    end

    described_class.perform_now(run)
    run.reload

    expect(run).to be_failed
    expect(run.failure_reason).to eq("could not store results (ActiveRecord::ActiveRecordError)")
    expect([run.output, run.error_report]).to all(satisfy { !it.attached? })
  end

  it "processes a run only once when the job is delivered twice" do
    run = create_run("name,amount\nAda,3\n")

    described_class.perform_now(run)
    finished_at = run.reload.finished_at
    described_class.perform_now(ConversionRun.find(run.id))

    expect(run.reload.finished_at).to eq(finished_at)
    expect(ActiveStorage::Attachment.where(record: run).count).to eq(2)
  end

  it "keeps the recovered outcome and drops files when the run was marked stale before it finished" do
    run = create_run("name,amount\nAda,3\n")
    allow_any_instance_of(CsvConversionRunner).to receive(:run).and_wrap_original do |original, **kw|
      original.call(**kw).tap { ConversionRun.recover_stale!(now: 1.hour.from_now) }
    end

    described_class.perform_now(run)
    run.reload

    expect(run).to be_failed
    expect(run.failure_reason).to eq("worker stopped responding")
    expect([run.output, run.error_report]).to all(satisfy { !it.attached? })
  end
end
