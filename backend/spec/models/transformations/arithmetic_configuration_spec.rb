require "rails_helper"
require_relative "../../support/transformation_context"

RSpec.describe Transformation, "ArithmeticTransformer configuration", type: :model do
  include_context "transformation records"

  let(:column_transformer) do
    Rails.application.load_seed
    ColumnTransformer.find_by!(processor_class: "ArithmeticTransformer")
  end
  let(:parameters) { { "source_columns" => ["email", "contact_email"], "operator" => "+" } }

  before { transformation.input_json = parameters }

  it "persists its settings and protects both source columns" do
    transformation.save!

    expect(transformation.reload.input_json).to eq(parameters)
    expect(column_transformer.get_transformer(transformation).source_column_names).to eq(parameters["source_columns"])
    ["email", "contact_email"].each do |name|
      column = input_file_type.columns.find_by!(name: name)
      expect(column.destroy).to be false
      expect(column.errors[:base]).to include("cannot delete a column used by a transformation")
      expect(Column.exists?(column.id)).to be true
    end
  end

  ["+", "-", "*"].each do |operator|
    it "accepts #{operator} with repeated sources" do
      transformation.input_json = { "source_columns" => ["email", "email"], "operator" => operator }

      expect(transformation.save).to be true
    end

    it "rejects a scale for #{operator}" do
      transformation.input_json = parameters.merge("operator" => operator, "scale" => 2)

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json]).not_to be_empty
    end
  end

  [0, 2, 100].each do |scale|
    it "persists division with scale #{scale}" do
      transformation.input_json = parameters.merge("operator" => "/", "scale" => scale)
      transformation.save!

      expect(transformation.reload.input_json).to eq(parameters.merge("operator" => "/", "scale" => scale))
    end
  end

  { "NULL" => nil, "negative" => -1, "excessive" => 101, "fractional" => 1.5, "string" => "2", "boolean" => true }.each do |description, value|
    it "rejects a #{description} division scale without changing the saved rule" do
      transformation.save!

      expect(transformation.update(input_json: parameters.merge("operator" => "/", "scale" => value))).to be false
      expect(transformation.errors[:input_json].join).to include("/scale")
      expect(transformation.reload.input_json).to eq(parameters)
    end
  end

  it "requires a scale for division" do
    transformation.input_json = parameters.merge("operator" => "/")

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("scale")
  end

  {
    "omitted sources" => { "operator" => "+" },
    "empty sources" => { "source_columns" => [], "operator" => "+" },
    "one source" => { "source_columns" => ["email"], "operator" => "+" },
    "three sources" => { "source_columns" => ["email", "contact_email", "customer_id"], "operator" => "+" },
    "scalar sources" => { "source_columns" => "email", "operator" => "+" },
    "empty source name" => { "source_columns" => ["email", ""], "operator" => "+" },
    "non-string source name" => { "source_columns" => ["email", 123], "operator" => "+" },
    "omitted operator" => { "source_columns" => ["email", "contact_email"] },
    "unsupported operator" => { "source_columns" => ["email", "contact_email"], "operator" => "**" },
    "additional setting" => { "source_columns" => ["email", "contact_email"], "operator" => "+", "unexpected" => true },
  }.each do |description, settings|
    it "rejects #{description} through the seeded schema" do
      transformation.input_json = settings

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json]).not_to be_empty
    end
  end

  it "rejects a source outside the map's input file type" do
    other_type = FileType.create!(name: "Other input")
    other_type.columns.create!(name: "foreign_amount", position: 0)
    transformation.input_json["source_columns"] = ["email", "foreign_amount"]

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include('source column "foreign_amount" does not exist')
  end

  {
    "invalid operator" => [{ "operator" => "send" }, "operator must be one of"],
    "invalid source count" => [{ "source_columns" => ["email"] }, "exactly two"],
    "missing division scale" => [{ "operator" => "/" }, "division scale must be an integer"],
    "non-division scale" => [{ "scale" => 2 }, "scale is only supported for division"],
  }.each do |description, (settings, message)|
    it "still rejects #{description} when the catalog has no schema" do
      column_transformer.update!(input_schema: nil)
      transformation.input_json = parameters.merge(settings)

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include(message)
    end
  end

  it "reports invalid configuration without raising when the schema and parameters are NULL" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = nil

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("operator must be one of")
  end
end
