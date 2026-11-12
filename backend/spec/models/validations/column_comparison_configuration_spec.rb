require "rails_helper"
require_relative "../../support/validation_context"

RSpec.describe Validation, "column comparison configuration", type: :model do
  include_context "validation records"

  let(:column_validator) do
    Rails.application.load_seed
    ColumnValidator.find_by!(processor_class: "StringComparisonValidator")
  end
  let(:parameters) { { "other_column" => "confirmation_email", "operator" => "==" } }

  before do
    file_type.columns.create!(name: "confirmation_email", position: 1)
    validation.input_json = parameters
  end

  ["StringComparisonValidator", "NumericComparisonValidator"].each do |processor_class|
    it "persists a valid rule using the seeded #{processor_class} catalog" do
      validation.column_validator = ColumnValidator.find_by!(processor_class: processor_class)
      validation.save!

      expect(validation.reload.input_json).to eq(parameters)
    end
  end

  ["other_column", "operator"].each do |parameter|
    it "requires #{parameter} through the shared seeded schema" do
      validation.input_json = parameters.except(parameter)

      expect(validation.save).to be false
      expect(validation.errors[:input_json].join).to include(parameter)
    end
  end

  { "empty" => "", "numeric" => 123, "NULL" => nil }.each do |description, value|
    it "rejects a #{description} other_column through the shared seeded schema" do
      validation.input_json = parameters.merge("other_column" => value)

      expect(validation.save).to be false
      expect(validation.errors[:input_json].join).to include("/other_column")
    end
  end

  ["clear", 123, nil].each do |operator|
    it "rejects the unsupported operator #{operator.inspect} through the shared seeded schema" do
      validation.input_json = parameters.merge("operator" => operator)

      expect(validation.save).to be false
      expect(validation.errors[:input_json].join).to include("/operator")
    end
  end

  it "rejects a reference to a column in another file type without changing a saved rule" do
    validation.save!
    other_type = FileType.create!(name: "Other format")
    other_type.columns.create!(name: "foreign_email", position: 0)

    expect(validation.update(input_json: parameters.merge("other_column" => "foreign_email"))).to be false
    expect(validation.errors[:input_json].join).to include("does not exist in the column's file type")
    expect(validation.reload.input_json).to eq(parameters)
  end

  it "rejects additional settings" do
    validation.input_json = parameters.merge("unexpected" => true)

    expect(validation.save).to be false
    expect(validation.errors[:input_json].join).to include("unexpected")
  end
end
