require "rails_helper"
require_relative "../../support/validation_context"

RSpec.describe Validation, "numeric range configuration", type: :model do
  include_context "validation records"

  let(:column_validator) do
    Rails.application.load_seed
    ColumnValidator.find_by!(processor_class: "NumericRangeValidator")
  end

  [
    { "min" => -2.5 },
    { "max" => 0 },
    { "min" => -2.5, "max" => 10.5 },
    { "min" => 2, "max" => 2 },
  ].each do |parameters|
    it "persists valid bounds #{parameters.inspect}" do
      validation.input_json = parameters
      validation.save!

      expect(validation.reload.input_json).to eq(parameters)
    end
  end

  it "requires at least one bound when parameters are omitted" do
    expect(validation.save).to be false
    expect(validation.errors[:input_json].join).to include("at least one numeric bound")
  end

  it "rejects reversed bounds without changing a saved rule" do
    validation.input_json = { "min" => -2.5, "max" => 10.5 }
    validation.save!

    expect(validation.update(input_json: { "min" => 10.6, "max" => 10.5 })).to be false
    expect(validation.errors[:input_json].join).to include("min <= max")
    expect(validation.reload.input_json).to eq("min" => -2.5, "max" => 10.5)
  end

  ["min", "max"].each do |bound|
    { "string" => "2.5", "boolean" => true, "NULL" => nil }.each do |description, value|
      it "rejects a #{description} #{bound} through the seeded schema" do
        validation.input_json = { bound => value }

        expect(validation.save).to be false
        expect(validation.errors[:input_json].join).to include("/#{bound}")
      end
    end
  end

  it "rejects unsupported settings" do
    validation.input_json = { "min" => 0, "exclusive" => true }

    expect(validation.save).to be false
    expect(validation.errors[:input_json].join).to include("exclusive")
  end
end
