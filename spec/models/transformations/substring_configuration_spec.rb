require "rails_helper"
require_relative "../../support/transformation_context"

RSpec.describe Transformation, "SubstringTransformer configuration", type: :model do
  include_context "transformation records"

  let(:column_transformer) do
    Rails.application.load_seed
    ColumnTransformer.find_by!(processor_class: "SubstringTransformer")
  end
  let(:parameters) { { "source_column" => "email", "start" => 0, "length" => 4 } }

  before { transformation.input_json = parameters }

  it "persists its source, start, and length and protects the source from deletion" do
    transformation.save!

    expect(transformation.reload.input_json).to eq(parameters)
    processor = column_transformer.get_transformer(transformation)
    expect(processor.source_column_names).to eq(["email"])
    source_column = input_file_type.columns.find_by!(name: "email")
    expect(source_column.destroy).to be false
    expect(source_column.errors[:base]).to include("cannot delete a column used by a transformation")
  end

  it "allows zero length and arbitrarily large nonnegative bounds" do
    transformation.save!

    expect(transformation.update(input_json: parameters.merge("length" => 0))).to be true
    expect(transformation.update(input_json: parameters.merge("start" => 10**100, "length" => 10**100))).to be true
  end

  ["start", "length"].each do |setting|
    it "rejects omitted #{setting}" do
      transformation.input_json = parameters.except(setting)

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include(setting)
    end

    { "negative" => -1, "fractional" => 1.5, "string" => "1", "NULL" => nil, "boolean" => true }.each do |description, value|
      it "rejects #{description} #{setting} without changing the saved parameters" do
        transformation.save!

        expect(transformation.update(input_json: parameters.merge(setting => value))).to be false
        expect(transformation.errors[:input_json].join).to include("/#{setting}")
        expect(transformation.reload.input_json).to eq(parameters)
      end
    end

    it "still rejects invalid #{setting} when the catalog has no schema" do
      column_transformer.update!(input_schema: nil)
      transformation.input_json = parameters.merge(setting => -1)

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json]).to include("#{setting} must be a nonnegative integer")
    end
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
    expect(transformation.errors[:input_json].join).to include("source column", "start", "length")
  end
end
