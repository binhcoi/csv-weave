require "rails_helper"
require_relative "../../support/transformation_context"

RSpec.describe Transformation, "FormatStringTransformer configuration", type: :model do
  include_context "transformation records"

  let(:column_transformer) do
    Rails.application.load_seed
    ColumnTransformer.find_by!(processor_class: "FormatStringTransformer")
  end
  let(:parameters) do
    { "source_columns" => ["email", "contact_email"], "format" => "%{contact_email}: %{email}" }
  end

  before { transformation.input_json = parameters }

  it "persists its template and sources and protects every listed source, including unused sources" do
    parameters["source_columns"] << "customer_id"
    transformation.save!

    expect(transformation.reload.input_json).to eq(parameters)
    expect(column_transformer.get_transformer(transformation).source_column_names).to eq(parameters["source_columns"])
    input_file_type.columns.each do |source_column|
      expect(source_column.destroy).to be false
      expect(source_column.errors[:base]).to include("cannot delete a column used by a transformation")
      expect(Column.exists?(source_column.id)).to be true
    end
  end

  ["", "literal", "%{email}/%{email}", "%%{not_a_column}", "%%%{email}"].each do |format|
    it "accepts template #{format.inspect} with repeated and unused source declarations" do
      transformation.input_json = parameters.merge("source_columns" => ["email", "email", "customer_id"], "format" => format)

      expect(transformation.save).to be true
    end
  end

  {
    "omitted sources" => { "format" => "literal" },
    "empty sources" => { "source_columns" => [], "format" => "literal" },
    "NULL sources" => { "source_columns" => nil, "format" => "literal" },
    "scalar sources" => { "source_columns" => "email", "format" => "literal" },
    "empty source name" => { "source_columns" => [""], "format" => "literal" },
    "non-string source name" => { "source_columns" => [123], "format" => "literal" },
    "omitted format" => { "source_columns" => ["email"] },
    "NULL format" => { "source_columns" => ["email"], "format" => nil },
    "numeric format" => { "source_columns" => ["email"], "format" => 123 },
    "additional setting" => { "source_columns" => ["email"], "format" => "literal", "unexpected" => true },
  }.each do |description, settings|
    it "rejects #{description} through the seeded schema" do
      transformation.input_json = settings

      expect(transformation.save).to be false
      expect(transformation.errors[:input_json]).not_to be_empty
    end
  end

  ["%", "%s", "%d", "%<email>s", "%{", "%{}", "%{email", "%{{email}}"].each do |format|
    it "rejects malformed or unsupported template #{format.inspect} without changing the saved rule" do
      transformation.save!

      expect(transformation.update(input_json: parameters.merge("format" => format))).to be false
      expect(transformation.errors[:input_json].join).to include("format supports only")
      expect(transformation.reload.input_json).to eq(parameters)
    end
  end

  it "rejects an existing column omitted from the source list" do
    transformation.input_json["format"] = "%{customer_id}"

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include('placeholder "customer_id" must name a listed source column')
  end

  it "rejects an unused source outside the map's input file type" do
    other_type = FileType.create!(name: "Other input")
    other_type.columns.create!(name: "foreign_name", position: 0)
    transformation.input_json["source_columns"] << "foreign_name"

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include('source column "foreign_name" does not exist')
  end

  it "validates template syntax even when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json["format"] = "%d"

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("format supports only")
  end

  it "requires a string template even when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json["format"] = nil

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json]).to include("format must be a string")
  end

  it "reports invalid sources without raising when the schema and parameters are NULL" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = nil

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("source_columns must be a nonempty array")
  end
end
