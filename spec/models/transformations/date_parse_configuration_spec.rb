require "rails_helper"
require_relative "../../support/transformation_context"

RSpec.describe Transformation, "DateParseTransformer configuration", type: :model do
  include_context "transformation records"

  let(:column_transformer) do
    Rails.application.load_seed
    ColumnTransformer.find_by!(processor_class: "DateParseTransformer")
  end
  let(:parameters) { { "source_column" => "email", "format" => "%d/%m/%Y" } }

  before { transformation.input_json = parameters }

  it "persists a custom output format, including partial date formats" do
    transformation.input_json = parameters.merge("output_format" => "%m/%d/%Y")
    transformation.save!

    expect(transformation.reload.input_json).to eq(parameters.merge("output_format" => "%m/%d/%Y"))
    expect(transformation.update(input_json: parameters.merge("output_format" => "%Y-%m"))).to be true
  end

  { "empty" => "", "numeric" => 123, "NULL" => nil, "boolean" => true }.each do |description, value|
    it "rejects #{description} output format without changing the saved parameters" do
      transformation.save!

      expect(transformation.update(input_json: parameters.merge("output_format" => value))).to be false
      expect(transformation.errors[:input_json].join).to include("/output_format")
      expect(transformation.reload.input_json).to eq(parameters)
    end
  end

  it "validates an explicit output format even when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = parameters.merge("output_format" => nil)

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json]).to include("output_format must be a nonempty string")
  end

  it "persists its settings and protects the source from deletion" do
    transformation.save!

    expect(transformation.reload.input_json).to eq(parameters)
    expect(column_transformer.get_transformer(transformation).source_column_names).to eq(["email"])
    source_column = input_file_type.columns.find_by!(name: "email")
    expect(source_column.destroy).to be false
    expect(source_column.errors[:base]).to include("cannot delete a column used by a transformation")
  end

  ["%Y-%m-%d", "%d %b %Y", "%Y-%j", "%G-W%V-%u"].each do |format|
    it "accepts the complete format #{format.inspect}" do
      transformation.input_json = parameters.merge("format" => format)

      expect(transformation.save).to be true
    end
  end

  ["source_column", "format"].each do |setting|
    it "requires #{setting}" do
      transformation.input_json = parameters.except(setting)

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json].join).to include(setting)
    end

    { "empty" => "", "numeric" => 123, "NULL" => nil, "boolean" => true }.each do |description, value|
      it "rejects #{description} #{setting} through the seeded schema" do
        transformation.input_json = parameters.merge(setting => value)

        expect(transformation.save).to be false
        expect(transformation.errors[:input_json].join).to include("/#{setting}")
      end
    end
  end

  ["literal", "%q", "%m/%d", "%Y-%m", "%H:%M"].each do |format|
    it "rejects incomplete format #{format.inspect} without changing the saved parameters" do
      transformation.save!

      expect(transformation.update(input_json: parameters.merge("format" => format))).to be false
      expect(transformation.errors[:input_json]).to include("format must describe a complete date")
      expect(transformation.reload.input_json).to eq(parameters)
    end
  end

  it "validates the format even when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = parameters.merge("format" => "%m/%d")

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json]).to include("format must describe a complete date")
  end

  it "reports invalid configuration without raising when the schema and parameters are NULL" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = nil

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("source column", "format")
  end

  it "rejects additional settings" do
    transformation.input_json = parameters.merge("unexpected" => true)

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("unexpected")
  end

  it "rejects a source outside the map's input file type" do
    other_type = FileType.create!(name: "Other input")
    other_type.columns.create!(name: "foreign_date", position: 0)
    transformation.input_json = parameters.merge("source_column" => "foreign_date")

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include('source column "foreign_date"')
  end
end
