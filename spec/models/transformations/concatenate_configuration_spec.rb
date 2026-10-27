require "rails_helper"
require_relative "../../support/transformation_context"

RSpec.describe Transformation, "ConcatenateTransformer configuration", type: :model do
  include_context "transformation records"

  let(:column_transformer) do
    Rails.application.load_seed
    ColumnTransformer.find_by!(processor_class: "ConcatenateTransformer")
  end

  it "persists ordered sources, including repetitions, and an optional separator" do
    parameters = { "source_columns" => ["contact_email", "email", "contact_email"] }
    transformation.input_json = parameters
    transformation.save!

    expect(transformation.reload.input_json).to eq(parameters)
    expect(transformation.update(input_json: parameters.merge("separator" => ""))).to be true
    expect(transformation.reload.input_json).to eq(parameters.merge("separator" => ""))
  end

  {
    "omitted sources" => {},
    "empty sources" => { "source_columns" => [] },
    "NULL sources" => { "source_columns" => nil },
    "scalar sources" => { "source_columns" => "email" },
    "empty source name" => { "source_columns" => [""] },
    "non-string source name" => { "source_columns" => [123] },
    "NULL separator" => { "source_columns" => ["email"], "separator" => nil },
    "numeric separator" => { "source_columns" => ["email"], "separator" => 123 },
    "additional setting" => { "source_columns" => ["email"], "unexpected" => true },
  }.each do |description, parameters|
    it "rejects #{description} through the seeded schema" do
      transformation.input_json = parameters

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json]).not_to be_empty
    end
  end

  it "rejects a source in another input type without changing the saved parameters" do
    parameters = { "source_columns" => ["email", "contact_email"], "separator" => ", " }
    transformation.input_json = parameters
    transformation.save!
    other_type = FileType.create!(name: "Other input")
    other_type.columns.create!(name: "foreign_email", position: 0)

    expect(transformation.update(input_json: parameters.merge("source_columns" => ["email", "foreign_email"]))).to be false
    expect(transformation.errors[:input_json].join).to include('source column "foreign_email"')
    expect(transformation.reload.input_json).to eq(parameters)
  end

  it "reports every missing source once" do
    transformation.input_json = { "source_columns" => ["missing_a", "missing_b", "missing_a"] }

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].size).to eq(2)
    expect(transformation.errors[:input_json].join).to include('source column "missing_a"', 'source column "missing_b"')
  end

  it "still requires at least one source when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = {}

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("at least one source column")
  end
end
