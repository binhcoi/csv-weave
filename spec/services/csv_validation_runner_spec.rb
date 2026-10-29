require "rails_helper"
require "stringio"
require "json"

RSpec.describe CsvValidationRunner do
  let(:columns) { [Column.new(name: "name", position: 0), Column.new(name: "amount", position: 1)] }
  let(:validator) { Validators::RequiredValidator.new(Validation.new(column: columns.first)) }
  let(:runner) { described_class.new(columns: columns, validators: [validator]) }
  let(:report) { StringIO.new }

  it "counts valid and invalid rows, streams failures, and continues without changing input bytes" do
    csv = "amount,name\n1,Alex\n2,\n3,Jordan\n"
    input = StringIO.new(csv.dup)

    result = runner.run(input: input, error_output: report)

    expect([result.accepted_rows, result.rejected_rows, result.error_count]).to eq([2, 1, 1])
    expect(input.string).to eq(csv)
    expect(JSON.parse(report.string)).to eq(
      "record_number" => 3, "stage" => "input_validation", "column" => "name",
      "operation" => "RequiredValidator", "reason" => "must be present",
    )
    expect(input).not_to be_closed
    expect(report).not_to be_closed
  end

  it "still checks record shape when no validators are configured" do
    runner = described_class.new(columns: columns, validators: [])

    result = runner.run(input: StringIO.new("name,amount\nAlex,1\nshort\n"), error_output: report)

    expect([result.accepted_rows, result.rejected_rows, result.error_count]).to eq([1, 1, 1])
    expect(JSON.parse(report.string)).to include("record_number" => 3, "stage" => "row_shape")
  end

  it "accepts a header-only file without requiring any CSV output IO" do
    result = runner.run(input: StringIO.new("name,amount\n"), error_output: report)

    expect([result.accepted_rows, result.rejected_rows, result.error_count]).to eq([0, 0, 0])
    expect(report.string).to be_empty
  end

  it "reports file failures with the same error contract as conversion" do
    expect do
      runner.run(input: StringIO.new("other,amount\nAlex,1\n"), error_output: report)
    end.to raise_error(described_class::InvalidFile) do |error|
      expect([error.result.accepted_rows, error.result.rejected_rows, error.result.error_count]).to eq([0, 0, 1])
      expect(JSON.parse(report.string, symbolize_names: true)).to eq(error.error)
      expect(error.error).to include(stage: "headers", reason: 'missing headers: "name"')
    end
  end

  it "propagates unexpected validator exceptions" do
    allow(validator).to receive(:validate).and_raise(RuntimeError, "validator bug")

    expect do
      runner.run(input: StringIO.new("name,amount\nAlex,1\n"), error_output: report)
    end.to raise_error(RuntimeError, "validator bug")
  end
end
