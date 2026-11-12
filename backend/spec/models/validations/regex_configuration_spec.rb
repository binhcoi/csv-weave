require "rails_helper"
require_relative "../../support/validation_context"

RSpec.describe Validation, "regex configuration", type: :model do
  include_context "validation records"

  let(:column_validator) do
    Rails.application.load_seed
    ColumnValidator.find_by!(processor_class: "RegexValidator")
  end

  ['\A[A-Z]{2}-[0-9]{4}\z', ""].each do |pattern|
    it "persists the valid pattern #{pattern.inspect}" do
      validation.input_json = { "pattern" => pattern }
      validation.save!

      expect(validation.reload.input_json).to eq("pattern" => pattern)
    end
  end

  it "requires a pattern when parameters are omitted" do
    expect(validation.save).to be false
    expect(validation.errors[:input_json].join).to include("pattern")
  end

  { "NULL" => nil, "numeric" => 123 }.each do |description, pattern|
    it "rejects a #{description} pattern through the seeded schema" do
      validation.input_json = { "pattern" => pattern }

      expect(validation.save).to be false
      expect(validation.errors[:input_json].join).to include("/pattern", "string")
    end
  end

  it "rejects client-supplied timeout overrides" do
    validation.input_json = { "pattern" => "code", "timeout" => 100 }

    expect(validation.save).to be false
    expect(validation.errors[:input_json].join).to include("timeout")
  end

  it "rejects invalid syntax without changing a saved rule" do
    validation.input_json = { "pattern" => "original" }
    validation.save!

    expect(validation.update(input_json: { "pattern" => "[" })).to be false
    expect(validation.errors[:input_json].join).to include("invalid regex pattern")
    expect(validation.reload.input_json).to eq("pattern" => "original")
  end

  it "rejects NULL parameters before attempting pattern compilation" do
    validation.input_json = nil

    expect(validation.save).to be false
    expect(validation.errors[:input_json]).not_to be_empty
  end
end
