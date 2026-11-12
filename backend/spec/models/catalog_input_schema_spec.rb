require "rails_helper"

RSpec.describe "Catalog input schemas", type: :model do
  [:column_validator, :column_transformer].each do |factory|
    context "for #{factory}" do
      subject(:catalog) { FactoryBot.build(factory) }

      it "persists the complete schema" do
        catalog.input_schema = { "type" => "object", "properties" => {}, "additionalProperties" => false }
        expected_schema = catalog.input_schema.deep_dup
        catalog.save!

        expect(catalog.reload.input_schema).to eq(expected_schema)
      end

      {
        "array" => [],
        "string" => "object",
        "boolean" => true,
        "unknown type" => { "type" => "unknown" },
        "invalid properties" => { "properties" => [] },
        "invalid required list" => { "required" => "name" },
        "negative length" => { "type" => "string", "minLength" => -1 },
      }.each do |description, schema|
        it "rejects a #{description} schema" do
          catalog.input_schema = schema

          expect(catalog).not_to be_valid
          expect(catalog.errors[:input_schema]).not_to be_empty
        end
      end

      it "allows an omitted schema" do
        catalog.input_schema = nil
        catalog.save!

        expect(catalog.reload.input_schema).to be_nil
      end

      it "allows a NULL schema without model validation" do
        result = catalog.class.insert_all!([{ processor_class: catalog.processor_class, input_schema: nil }])

        expect(catalog.class.find(result.rows.first.first).input_schema).to be_nil
      end
    end
  end
end
