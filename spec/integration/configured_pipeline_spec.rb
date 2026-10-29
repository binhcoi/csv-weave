require "rails_helper"
require "csv"
require "json"
require "stringio"

RSpec.describe "Configured CSV conversion", type: :model do
  let(:mapping) do
    Rails.application.load_seed
    input = FileType.create!(name: "Customer import")
    output = FileType.create!(name: "Customer export")
    input_columns = ["amount", "given_name", "family_name", "joined_on"].each_with_index.to_h do |name, position|
      [name, input.columns.create!(name: name, position: position)]
    end
    output_columns = ["label", "amount", "joined_date", "optional_note"].each_with_index.to_h do |name, position|
      [name, output.columns.create!(name: name, position: position * 2)]
    end
    ["amount", "given_name"].each { |name| add_validation(input_columns.fetch(name), "RequiredValidator") }
    add_validation(input_columns.fetch("joined_on"), "DateValidator", "format" => "%d/%m/%Y")
    add_validation(output_columns.fetch("label"), "LengthValidator", "max" => 30)
    add_validation(output_columns.fetch("amount"), "RequiredValidator")
    add_validation(output_columns.fetch("amount"), "NumericRangeValidator", "min" => 0, "max" => 100)
    add_validation(output_columns.fetch("joined_date"), "DateValidator", "format" => "%m/%d/%Y")
    map = TransformMap.create!(name: "Customer conversion", input_file_type: input, output_file_type: output)
    [
      ["joined_date", "DateParseTransformer", { "source_column" => "joined_on", "format" => "%d/%m/%Y", "output_format" => "%m/%d/%Y" }],
      ["label", "FormatStringTransformer", { "source_columns" => ["given_name", "family_name"], "format" => "%{family_name}, %{given_name}" }],
      ["amount", "DecimalParseTransformer", { "source_column" => "amount" }],
    ].each do |target, processor_class, settings|
      map.transformations.create!(output_column: output_columns.fetch(target), input_json: settings,
                                  column_transformer: ColumnTransformer.find_by!(processor_class: processor_class))
    end
    map
  end
  let(:configuration) { ConversionConfigurationLoader.load(mapping.id) }
  let(:output) { StringIO.new }
  let(:error_output) { StringIO.new }

  it "converts quoted Unicode CSV through saved rules in output order without database queries" do
    configuration
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload.fetch(:sql) }
    result = nil

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      result = convert([["Morgan", "29/02/2024", "12.50", "Alex, \"A\"\n李"]])
    end

    expect([result.accepted_rows, result.rejected_rows, result.error_count]).to eq([1, 0, 0])
    expect(report_entries).to be_empty
    expect(queries).to be_empty
    row = CSV.parse(output.string, headers: true).first
    expect(row.headers).to eq(["label", "amount", "joined_date", "optional_note"])
    expect(row.to_h).to eq(
      "label" => "Morgan, Alex, \"A\"\n李", "amount" => "12.5", "joined_date" => "02/29/2024", "optional_note" => nil,
    )
  end

  it "rejects rows at each stage and continues writing subsequent valid rows" do
    result = convert([
      ["Morgan", "29/02/2024", "12.50", "Alex\nA"],
      ["Rivera", "01/03/2024", "1", ""],
      ["Kim", "02/03/2024", "invalid", "Taylor"],
      ["Park", "03/03/2024", "100.01", "Sam"],
      ["Lee", "04/03/2024", "3.25", "Jordan"],
    ])

    expect([result.accepted_rows, result.rejected_rows, result.error_count]).to eq([2, 3, 3])
    expect(CSV.parse(output.string, headers: true).map { |row| row["label"] }).to eq(["Morgan, Alex\nA", "Lee, Jordan"])
    expect(report_entries).to eq([
      { record_number: 3, stage: "input_validation", column: "given_name", operation: "RequiredValidator", reason: "must be present" },
      { record_number: 4, stage: "transformation", column: "amount", operation: "DecimalParseTransformer",
        reason: 'source column "amount" contains an invalid decimal' },
      { record_number: 5, stage: "output_validation", column: "amount", operation: "NumericRangeValidator",
        reason: "must be a finite number >= 0.0 and <= 100.0" },
    ])
  end

  it "reports every input validation failure and skips later stages for that record" do
    configuration.transformers.each { |processor| expect(processor).not_to receive(:transform) }
    configuration.output_validators.each { |processor| expect(processor).not_to receive(:validate) }

    result = convert([["Morgan", "31/02/2024", "", ""]])

    expect([result.accepted_rows, result.rejected_rows, result.error_count]).to eq([0, 1, 3])
    expect(report_entries.map { |error| [error[:stage], error[:column], error[:operation], error[:reason]] }).to eq([
      ["input_validation", "amount", "RequiredValidator", "must be present"],
      ["input_validation", "given_name", "RequiredValidator", "must be present"],
      ["input_validation", "joined_on", "DateValidator", 'must be a valid date matching "%d/%m/%Y"'],
    ])
    expect(CSV.parse(output.string)).to eq([["label", "amount", "joined_date", "optional_note"]])
  end

  it "reports every transformation failure and skips output validation for that record" do
    optional = mapping.output_file_type.columns.find_by!(name: "optional_note")
    mapping.transformations.create!(output_column: optional, input_json: { "source_column" => "given_name" },
                                    column_transformer: ColumnTransformer.find_by!(processor_class: "DecimalParseTransformer"))
    configuration.output_validators.each { |processor| expect(processor).not_to receive(:validate) }

    result = convert([["Morgan", "29/02/2024", "invalid", "Alex"]])

    expect([result.accepted_rows, result.rejected_rows, result.error_count]).to eq([0, 1, 2])
    expect(report_entries.map { |error| [error[:stage], error[:column]] }).to eq([
      ["transformation", "amount"], ["transformation", "optional_note"],
    ])
  end

  it "validates unmapped output columns and reports all output failures in column order" do
    optional = mapping.output_file_type.columns.find_by!(name: "optional_note")
    add_validation(optional, "RequiredValidator")

    result = convert([["Morgan", "29/02/2024", "100.01", "Alex"]])

    expect([result.accepted_rows, result.rejected_rows, result.error_count]).to eq([0, 1, 2])
    expect(report_entries.map { |error| [error[:stage], error[:column], error[:operation]] }).to eq([
      ["output_validation", "amount", "NumericRangeValidator"],
      ["output_validation", "optional_note", "RequiredValidator"],
    ])
  end

  def report_entries
    error_output.string.each_line.map { |line| JSON.parse(line, symbolize_names: true) }
  end

  def convert(rows)
    csv = CSV.generate do |writer|
      writer << ["family_name", "joined_on", "amount", "given_name"]
      rows.each { |row| writer << row }
    end
    CsvConversionRunner.new(configuration).run(input: StringIO.new(csv), output: output, error_output: error_output)
  end

  def add_validation(column, processor_class, settings = {})
    column.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: processor_class), input_json: settings)
  end
end
