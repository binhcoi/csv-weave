require "rails_helper"
require E2E_ROOT.join("support/configuration_seeder")

RSpec.describe E2e::ConfigurationSeeder do
  SCENARIO_FIXTURES = {
    basic: { prefix: "orders", names: %w[valid mixed bad_header latin1] },
    comprehensive: { prefix: "registrations", names: %w[valid mixed] },
  }.freeze

  before { Rails.application.load_seed }

  it "creates the basic scenario's E2E-TEST file types, validations, and map" do
    configuration = described_class.seed!(:basic)

    expect([configuration.input_file_type, configuration.output_file_type, configuration.transform_map].map(&:name))
      .to eq(["E2E-TEST Supplier orders", "E2E-TEST Warehouse orders", "E2E-TEST Supplier to warehouse"])
    expect(configuration.input_file_type.columns.order(:position).pluck(:name))
      .to eq(described_class::SCENARIOS.dig(:basic, :input_columns).keys)
    expect(Validation.count).to eq(5)
    expect(configuration.transform_map.transformations.count).to eq(6)
  end

  it "creates the comprehensive scenario using every cataloged validator and transformer" do
    configuration = described_class.seed!(:comprehensive)

    expect(configuration.transform_map.name).to eq("E2E-TEST Registrations to badges")
    expect(Validation.joins(:column_validator).distinct.pluck(:processor_class))
      .to match_array(ColumnValidator.pluck(:processor_class))
    expect(Transformation.joins(:column_transformer).distinct.pluck(:processor_class))
      .to match_array(ColumnTransformer.pluck(:processor_class))
    mapped = configuration.transform_map.transformations.includes(:output_column).map { |t| t.output_column.name }
    expect(configuration.output_file_type.columns.pluck(:name) - mapped).to eq(["internal_ref"])
  end

  it "is idempotent per scenario" do
    first = described_class.seed_all!

    expect { described_class.seed_all! }
      .not_to change { [FileType.count, Column.count, Validation.count, Transformation.count] }
    expect(described_class.seed!(:basic).transform_map).to eq(first.fetch(:basic).transform_map)
  end

  it "creates nothing when a catalog entry is missing" do
    ColumnTransformer.find_by!(processor_class: "ArithmeticTransformer").destroy!

    expect { described_class.seed!(:basic) }.to raise_error(/ArithmeticTransformer is missing/)
    expect(FileType.count).to eq(0)
  end

  # Keeps the seeded configurations and the fixture CSVs from drifting apart.
  SCENARIO_FIXTURES.each do |scenario, fixtures|
    fixtures.fetch(:names).each do |name|
      prefix = fixtures.fetch(:prefix)
      it "produces the expected #{scenario} results for e2e_test_#{prefix}_#{name}.csv" do
        configuration = described_class.seed!(scenario)
        conversion = ConversionConfigurationLoader.load(configuration.transform_map.id)
        validation = FileTypeConfigurationLoader.load(configuration.input_file_type.id)
        dir = E2E_ROOT.join("fixtures/#{scenario}")
        source = dir.join("e2e_test_#{prefix}_#{name}.csv")
        expected = dir.join("expected")

        output = StringIO.new
        errors = StringIO.new
        rejected = run_allowing_rejection do
          File.open(source) { CsvConversionRunner.new(conversion).run(input: it, output: output, error_output: errors) }
        end
        expect(errors.string).to eq(File.read(expected.join("#{prefix}_#{name}_conversion_errors.jsonl")))
        converted = expected.join("#{prefix}_#{name}_converted.csv")
        expect(rejected).to eq(!converted.exist?)
        expect(output.string).to eq(File.read(converted)) unless rejected

        errors = StringIO.new
        run_allowing_rejection do
          runner = CsvValidationRunner.new(columns: validation.columns, validators: validation.validators)
          File.open(source) { runner.run(input: it, error_output: errors) }
        end
        expect(errors.string).to eq(File.read(expected.join("#{prefix}_#{name}_validation_errors.jsonl")))
      end
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
