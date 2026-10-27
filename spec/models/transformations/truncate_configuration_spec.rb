require "rails_helper"
require_relative "../../support/transformation_context"

RSpec.describe Transformation, "TruncateTransformer configuration", type: :model do
  include_context "transformation records"

  let(:column_transformer) do
    Rails.application.load_seed
    ColumnTransformer.find_by!(processor_class: "TruncateTransformer")
  end
  let(:parameters) { { "source_column" => "email", "length" => 4 } }

  before { transformation.input_json = parameters }

  it "persists its settings and protects the source from deletion" do
    transformation.save!

    expect(transformation.reload.input_json).to eq(parameters)
    expect(column_transformer.get_transformer(transformation).source_column_names).to eq(["email"])
    source_column = input_file_type.columns.find_by!(name: "email")
    expect(source_column.destroy).to be false
    expect(source_column.errors[:base]).to include("cannot delete a column used by a transformation")
  end

  it "accepts zero and arbitrarily large lengths" do
    transformation.save!

    expect(transformation.update(input_json: parameters.merge("length" => 0))).to be true
    expect(transformation.update(input_json: parameters.merge("length" => 10**100))).to be true
  end

  it "requires a length" do
    transformation.input_json = parameters.except("length")

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("length")
  end

  { "negative" => -1, "fractional" => 1.5, "string" => "1", "NULL" => nil, "boolean" => true }.each do |description, value|
    it "rejects #{description} length without changing the saved parameters" do
      transformation.save!

      expect(transformation.update(input_json: parameters.merge("length" => value))).to be false
      expect(transformation.errors[:input_json].join).to include("/length")
      expect(transformation.reload.input_json).to eq(parameters)
    end
  end

  it "still rejects invalid length when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = parameters.merge("length" => -1)

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json]).to include("length must be a nonnegative integer")
  end

  it "rejects additional settings" do
    transformation.input_json = parameters.merge("unexpected" => true)

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("unexpected")
  end

  it "rejects a source outside the map's input file type" do
    other_type = FileType.create!(name: "Other input")
    other_type.columns.create!(name: "foreign_email", position: 0)
    transformation.input_json = parameters.merge("source_column" => "foreign_email")

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include('source column "foreign_email"')
  end

  it "reports invalid configuration without raising when the schema and parameters are NULL" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = nil

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("source column", "length")
  end
end
