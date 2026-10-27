require "rails_helper"
require_relative "../../support/transformation_context"

RSpec.describe Transformation, "numeric_parse configuration", type: :model do
  include_context "transformation records"

  ["IntegerParseTransformer", "DecimalParseTransformer"].each do |processor_class|
    context "with the seeded #{processor_class}" do
      let(:column_transformer) do
        Rails.application.load_seed
        ColumnTransformer.find_by!(processor_class: processor_class)
      end

      it "persists a configuration using the shared source setting" do
        transformation.save!

        expect(transformation.reload.input_json).to eq("source_column" => "email")
        expect(transformation.column_transformer).to eq(column_transformer)
      end

      it "rejects a non-string source through its seeded schema without changing the saved rule" do
        transformation.save!

        expect(transformation.update(input_json: { "source_column" => 123 })).to be false
        expect(transformation.errors[:input_json].join).to include("/source_column", "string")
        expect(transformation.reload.input_json).to eq("source_column" => "email")
      end
    end
  end
end
