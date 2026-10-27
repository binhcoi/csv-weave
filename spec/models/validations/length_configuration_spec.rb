require "rails_helper"
require_relative "../../support/validation_context"

RSpec.describe Validation, "length configuration", type: :model do
  include_context "validation records"

  let(:column_validator) do
    Rails.application.load_seed
    ColumnValidator.find_by!(processor_class: "LengthValidator")
  end

  [
    { "min" => 0 },
    { "max" => 0 },
    { "min" => 2, "max" => 5 },
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
    expect(validation.errors[:input_json].join).to include("at least")
  end

  it "rejects reversed bounds without changing a saved rule" do
    validation.input_json = { "min" => 2, "max" => 5 }
    validation.save!

    expect(validation.update(input_json: { "min" => 6, "max" => 5 })).to be false
    expect(validation.errors[:input_json].join).to include("min <= max")
    expect(validation.reload.input_json).to eq("min" => 2, "max" => 5)
  end

  ["min", "max"].each do |bound|
    { "negative" => -1, "string" => "2", "fractional" => 1.5, "NULL" => nil }.each do |description, value|
      it "rejects a #{description} #{bound} through the seeded schema" do
        validation.input_json = { bound => value }

        expect(validation.save).to be false
        expect(validation.errors[:input_json].join).to include("/#{bound}")
      end
    end
  end

  it "rejects NULL parameters before attempting processor configuration checks" do
    validation.input_json = nil

    expect(validation.save).to be false
    expect(validation.errors[:input_json]).not_to be_empty
  end
end
