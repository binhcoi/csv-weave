require "rails_helper"
require "csv"
require "json"
require "stringio"
require "tempfile"

RSpec.describe "Stored CSV validation", type: :model do
  after { DataFile.find_each { |record| record.file.purge } }

  it "validates a stored DataFile against its file type with no map or per-row database access" do
    Rails.application.load_seed
    type = FileType.create!(name: "Customer validation")
    amount = type.columns.create!(name: "amount", position: 2)
    name = type.columns.create!(name: "name", position: 0)
    type.columns.create!(name: "limit", position: 5)
    name.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "RequiredValidator"))
    amount.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "NumericRangeValidator"),
                               input_json: { "min" => 0, "max" => 100 })
    amount.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: "NumericComparisonValidator"),
                               input_json: { "other_column" => "limit", "operator" => "<=" })
    csv = CSV.generate do |writer|
      writer << ["limit", "name", "amount", "extra"]
      writer << ["20", "李, \"Alex\"\nMorgan", "12.50", "ignored"]
      writer << ["100", "", "150", "ignored"]
      writer << ["short"]
      writer << ["10", "Jordan", "3.25", "ignored"]
    end
    data_file = DataFile.create!(file_type: type, file: {
      io: StringIO.new(csv), filename: "customers.csv", content_type: "text/csv", identify: false,
    })
    configuration = FileTypeConfigurationLoader.load(data_file.file_type_id)
    runner = CsvValidationRunner.new(columns: configuration.columns, validators: configuration.validators)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload.fetch(:sql) }
    result = nil

    Tempfile.create("validation-report") do |report|
      data_file.file.open do |input|
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          result = runner.run(input: input, error_output: report)
        end
      end

      expect([result.accepted_rows, result.rejected_rows, result.error_count]).to eq([2, 2, 4])
      expect(queries).to be_empty
      entries = File.foreach(report.path).map { |line| JSON.parse(line) }
      expect(entries.map { |entry| entry.values_at("record_number", "stage", "column", "operation") }).to eq([
        [3, "input_validation", "name", "RequiredValidator"],
        [3, "input_validation", "amount", "NumericRangeValidator"],
        [3, "input_validation", "amount", "NumericComparisonValidator"],
        [4, "row_shape", nil, "CSV"],
      ])
    end

    expect(TransformMap.count).to eq(0)
    expect(data_file.file.download.b).to eq(csv.b)
  end
end
