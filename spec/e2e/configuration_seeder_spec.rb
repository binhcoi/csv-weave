require "rails_helper"
require Rails.root.join("e2e/support/configuration_seeder")

RSpec.describe E2e::ConfigurationSeeder do
  let(:fixtures) { Rails.root.join("e2e/fixtures") }

  before { Rails.application.load_seed }

  it "creates the E2E-TEST file types, validations, and map" do
    configuration = described_class.seed!

    expect([configuration.input_file_type, configuration.output_file_type, configuration.transform_map].map(&:name))
      .to eq(["E2E-TEST Supplier orders", "E2E-TEST Warehouse orders", "E2E-TEST Supplier to warehouse"])
    expect(configuration.input_file_type.columns.order(:position).pluck(:name)).to eq(described_class::INPUT_COLUMNS)
    expect(configuration.output_file_type.columns.order(:position).pluck(:name)).to eq(described_class::OUTPUT_COLUMNS)
    expect(Validation.count).to eq(5)
    expect(configuration.transform_map.transformations.count).to eq(6)
  end

  it "is idempotent" do
    first = described_class.seed!

    expect { described_class.seed! }.not_to change { [FileType.count, Column.count, Validation.count, Transformation.count] }
    expect(described_class.seed!.transform_map).to eq(first.transform_map)
  end

  it "creates nothing when a catalog entry is missing" do
    ColumnTransformer.find_by!(processor_class: "ArithmeticTransformer").destroy!

    expect { described_class.seed! }.to raise_error(/ArithmeticTransformer is missing/)
    expect(FileType.count).to eq(0)
  end

  # Keeps the seeded configuration and the fixture CSVs from drifting apart.
  %w[valid mixed bad_header latin1].each do |name|
    it "produces the expected results for e2e_test_orders_#{name}.csv" do
      configuration = described_class.seed!
      conversion = ConversionConfigurationLoader.load(configuration.transform_map.id)
      validation = FileTypeConfigurationLoader.load(configuration.input_file_type.id)
      source = fixtures.join("e2e_test_orders_#{name}.csv")
      expected = fixtures.join("expected")

      output = StringIO.new
      errors = StringIO.new
      rejected = run_allowing_rejection do
        File.open(source) { CsvConversionRunner.new(conversion).run(input: it, output: output, error_output: errors) }
      end
      expect(errors.string).to eq(File.read(expected.join("orders_#{name}_conversion_errors.jsonl")))
      converted = expected.join("orders_#{name}_converted.csv")
      expect(rejected).to eq(!converted.exist?)
      expect(output.string).to eq(File.read(converted)) unless rejected

      errors = StringIO.new
      run_allowing_rejection do
        runner = CsvValidationRunner.new(columns: validation.columns, validators: validation.validators)
        File.open(source) { runner.run(input: it, error_output: errors) }
      end
      expect(errors.string).to eq(File.read(expected.join("orders_#{name}_validation_errors.jsonl")))
    end
  end

  # Returns true when the runner rejected the whole file.
  def run_allowing_rejection
    yield
    false
  rescue CsvValidationRunner::InvalidFile
    true
  end
end
