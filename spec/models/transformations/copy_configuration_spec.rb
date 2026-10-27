require "rails_helper"
require_relative "../../support/transformation_context"

RSpec.describe Transformation, "copy configuration", type: :model do
  include_context "transformation records"

  describe "input schema validation" do
    {
      "NULL" => nil,
      "array" => [],
      "string" => "email",
      "number" => 1,
      "boolean" => true,
      "NULL source column" => { "source_column" => nil },
      "empty source column" => { "source_column" => "" },
      "unexpected parameter" => { "source_column" => "email", "unexpected" => true },
    }.each do |description, parameters|
      it "rejects #{description} parameters for CopyTransformer" do
        transformation.input_json = parameters

        expect(transformation).not_to be_valid
        expect(transformation.errors[:input_json]).not_to be_empty
      end
    end

    it "rejects a numeric source column and identifies the invalid field" do
      transformation.input_json = { "source_column" => 123 }

      expect(transformation).not_to be_valid
      expect(transformation.errors[:input_json].join).to include("/source_column", "string")
    end

    it "rejects invalid updates without changing the saved parameters" do
      transformation.save!

      expect(transformation.update(input_json: {})).to be false
      expect(transformation.errors[:input_json].join).to include("source_column")
      expect(transformation.reload.input_json).to eq("source_column" => "email")
    end

    it "uses constraints from the selected catalog schema" do
      schema = column_transformer.input_schema.deep_dup
      schema["properties"]["source_column"]["minLength"] = 10
      column_transformer.update!(input_schema: schema)

      expect(transformation).not_to be_valid
      expect(transformation.errors[:input_json].join).to include("/source_column")

      transformation.input_json = { "source_column" => "contact_email" }

      expect(transformation).to be_valid
    end

    it "reports an invalid catalog schema as an error instead of raising" do
      column_transformer.input_schema = { "type" => "unknown" }

      expect(transformation).not_to be_valid
      expect(transformation.errors[:input_json].join).to include("catalog input schema is invalid")
    end
  end

  it "still requires a copy source when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    transformation.input_json = nil

    expect(transformation.save).to be false
    expect(transformation.errors[:input_json].join).to include("source column")
  end

  it "rejects an omitted copy source when the catalog has no schema" do
    column_transformer.update!(input_schema: nil)
    rule = described_class.new(transform_map: transform_map, output_column: output_column,
                               column_transformer: column_transformer)

    expect(rule.save).to be false
    expect(rule.errors[:input_json].join).to include("source column")
  end

  it "rechecks the source against a changed map before saving an update" do
    transformation.save!
    other_input = FileType.create!(name: "Other input")
    other_map = TransformMap.create!(name: "Other map", input_file_type: other_input,
                                    output_file_type: output_file_type)

    expect(transformation.update(transform_map: other_map)).to be false
    expect(transformation.errors[:input_json].join).to include('source column "email"')
    expect(transformation.reload.transform_map).to eq(transform_map)
  end
end
