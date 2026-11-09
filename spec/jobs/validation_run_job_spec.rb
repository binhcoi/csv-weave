require "rails_helper"
require "json"
require "stringio"

RSpec.describe ValidationRunJob, type: :job do
  let(:file_type) { FileType.create!(name: "Customers") }
  let(:required) { ColumnValidator.create!(processor_class: "RequiredValidator", description: "Column requires a value") }

  before do
    name = file_type.columns.create!(name: "name", position: 0)
    file_type.columns.create!(name: "email", position: 1)
    name.validations.create!(column_validator: required)
  end

  after do
    DataFile.find_each { |record| record.file.purge }
    ValidationRun.find_each { |record| record.error_report.purge }
  end

  def upload(content)
    DataFile.create!(file_type: file_type, file: {
      io: StringIO.new(content), filename: "customers.csv", content_type: "text/csv", identify: false,
    })
  end

  def create_run(data_file)
    ValidationRun.create!(data_file: data_file, configuration_digest: FileTypeConfigurationDigest.for(file_type.id))
  end

  def report_entries(run)
    run.error_report.download.each_line.map { |line| JSON.parse(line) }
  end

  it "records counts and the error report for a file with rejected rows" do
    run = create_run(upload("name,email\nAda,a@example.com\n,b@example.com\nshort\n"))

    described_class.perform_now(run)
    run.reload

    expect(run).to be_succeeded
    expect([run.accepted_rows, run.rejected_rows, run.error_count]).to eq([1, 2, 2])
    expect([run.started_at, run.finished_at]).to all(be_present)
    expect(run.failure_reason).to be_nil
    expect(run.error_report.filename.to_s).to eq("validation_run_#{run.id}_errors.jsonl")
    expect(report_entries(run).map { |entry| entry.values_at("record_number", "stage", "column") })
      .to eq([[3, "input_validation", "name"], [4, "row_shape", nil]])
  end

  it "attaches an empty error report when every row passes" do
    run = create_run(upload("name,email\nAda,a@example.com\n"))

    described_class.perform_now(run)
    run.reload

    expect(run).to be_succeeded
    expect([run.accepted_rows, run.rejected_rows, run.error_count]).to eq([1, 0, 0])
    expect(run.error_report.download).to eq("")
  end

  it "marks the run rejected and keeps the report when the file itself is invalid" do
    run = create_run(upload("name\nAda\n"))

    described_class.perform_now(run)
    run.reload

    expect(run).to be_rejected
    expect(run.failure_reason).to eq('missing headers: "email"')
    expect([run.accepted_rows, run.rejected_rows, run.error_count]).to eq([0, 0, 1])
    expect(report_entries(run).sole).to include("stage" => "headers", "reason" => 'missing headers: "email"')
  end

  it "marks the run rejected for malformed CSV after partial progress" do
    run = create_run(upload("name,email\nAda,a@example.com\n\"open,x\n"))

    described_class.perform_now(run)
    run.reload

    expect(run).to be_rejected
    expect(run.accepted_rows).to eq(1)
    expect(report_entries(run).last).to include("stage" => "parsing")
  end

  it "marks the run failed without a report when the saved configuration is invalid" do
    run = create_run(upload("name,email\nAda,a@example.com\n"))
    required.update_column(:processor_class, "MissingValidator")

    described_class.perform_now(run)
    run.reload

    expect(run).to be_failed
    expect(run.failure_reason).to start_with("invalid configuration: column_validator #{required.id} processor_class")
    expect(run.error_report).not_to be_attached
    expect([run.accepted_rows, run.rejected_rows, run.error_count]).to all(be_nil)
  end

  it "marks the run failed on an unexpected exception and does not re-raise" do
    run = create_run(upload("name,email\nAda,a@example.com\n"))
    allow_any_instance_of(CsvValidationRunner).to receive(:run).and_raise(IOError, "disk gone")

    expect { described_class.perform_now(run) }.not_to raise_error
    run.reload

    expect(run).to be_failed
    expect(run.failure_reason).to eq("unexpected error (IOError)")
    expect(run.error_report).not_to be_attached
  end

  it "marks the run failed and drops the report when results cannot be saved" do
    run = create_run(upload("name,email\nAda,a@example.com\n"))
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_raise(ActiveRecord::ActiveRecordError, "boom")

    described_class.perform_now(run)
    run.reload

    expect(run).to be_failed
    expect(run.failure_reason).to eq("could not store results (ActiveRecord::ActiveRecordError)")
    expect(run.error_report).not_to be_attached
  end

  it "skips a run that is no longer queued" do
    run = create_run(upload("name,email\nAda,a@example.com\n"))
    run.update!(status: "running")

    expect(FileTypeConfigurationLoader).not_to receive(:load)
    described_class.perform_now(run)

    expect(run.reload).to be_running
  end

  it "processes a run only once when the job is delivered twice" do
    run = create_run(upload("name,email\nAda,a@example.com\n"))

    described_class.perform_now(run)
    finished_at = run.reload.finished_at
    described_class.perform_now(ValidationRun.find(run.id))

    expect(run.reload.finished_at).to eq(finished_at)
    expect(ActiveStorage::Attachment.where(record: run).count).to eq(1)
  end

  it "marks the run failed when the configuration changed between request and start" do
    run = create_run(upload("name,email\nAda,a@example.com\n"))
    file_type.columns.create!(name: "phone", position: 2)

    described_class.perform_now(run)
    run.reload

    expect(run).to be_failed
    expect(run.failure_reason).to eq("configuration changed after the run was requested")
    expect(run.error_report).not_to be_attached
  end

  it "records a heartbeat when it claims the run and stops the heartbeat afterwards" do
    run = create_run(upload("name,email\nAda,a@example.com\n"))
    task = nil
    allow(Concurrent::TimerTask).to receive(:new).and_wrap_original { |original, *args, **kw, &block| task = original.call(*args, **kw, &block) }

    described_class.perform_now(run)

    expect(run.reload.heartbeat_at).to be_within(1.second).of(run.started_at)
    expect(task).not_to be_running
  end

  it "keeps the recovered outcome when the run was marked stale before it finished" do
    run = create_run(upload("name,email\nAda,a@example.com\n"))
    allow_any_instance_of(CsvValidationRunner).to receive(:run).and_wrap_original do |original, **kw|
      result = original.call(**kw)
      ValidationRun.recover_stale!(now: 1.hour.from_now)
      result
    end

    described_class.perform_now(run)
    run.reload

    expect(run).to be_failed
    expect(run.failure_reason).to eq("worker stopped responding")
    expect(run.accepted_rows).to be_nil
    expect(run.error_report).not_to be_attached
  end
end
