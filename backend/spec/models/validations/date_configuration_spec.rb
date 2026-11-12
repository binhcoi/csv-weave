require "rails_helper"
require_relative "../../support/validation_context"

RSpec.describe Validation, "date configuration", type: :model do
  include_context "validation records"

  let(:column_validator) do
    Rails.application.load_seed
    ColumnValidator.find_by!(processor_class: "DateValidator")
  end

  [
    { "format" => "%Y-%m-%d" },
    { "format" => "%d/%m/%Y", "min" => "2024-02-29" },
    { "format" => "%d %b %Y", "max" => "2030-12-31" },
    { "format" => "%Y-%j", "min" => "2024-02-29", "max" => "2024-02-29" },
    { "format" => "%G-W%V-%u" },
  ].each do |parameters|
    it "persists valid settings #{parameters.inspect}" do
      validation.input_json = parameters
      validation.save!

      expect(validation.reload.input_json).to eq(parameters)
    end
  end

  it "requires a format through the seeded schema" do
    expect(validation.save).to be false
    expect(validation.errors[:input_json].join).to include("format")
  end

  ["format", "min", "max"].each do |parameter|
    { "empty" => "", "numeric" => 20240101, "NULL" => nil }.each do |description, value|
      it "rejects a #{description} #{parameter} through the seeded schema" do
        validation.input_json = { "format" => "%Y-%m-%d", parameter => value }

        expect(validation.save).to be false
        expect(validation.errors[:input_json].join).to include("/#{parameter}")
      end
    end
  end

  ["literal", "%q", "%m/%d", "%Y-%m", "%H:%M"].each do |format|
    it "rejects the format #{format.inspect} that cannot specify a complete date" do
      validation.input_json = { "format" => format }

      expect(validation.save).to be false
      expect(validation.errors[:input_json].join).to include("format must describe a complete date")
    end
  end

  ["min", "max"].each do |bound|
    ["2025-02-29", "2024-2-9", "29/02/2024", "2024-02-29 extra"].each do |value|
      it "rejects the invalid ISO #{bound} #{value.inspect}" do
        validation.input_json = { "format" => "%d/%m/%Y", bound => value }

        expect(validation.save).to be false
        expect(validation.errors[:input_json].join).to include("#{bound} must be a valid date in YYYY-MM-DD format")
      end
    end
  end

  it "rejects reversed bounds without changing a saved rule" do
    validation.input_json = { "format" => "%Y-%m-%d", "min" => "2024-01-01", "max" => "2024-12-31" }
    validation.save!

    expect(validation.update(input_json: validation.input_json.merge("min" => "2025-01-01"))).to be false
    expect(validation.errors[:input_json].join).to include("min <= max")
    expect(validation.reload.input_json).to eq("format" => "%Y-%m-%d", "min" => "2024-01-01", "max" => "2024-12-31")
  end

  it "rejects unsupported settings" do
    validation.input_json = { "format" => "%Y-%m-%d", "timezone" => "UTC" }

    expect(validation.save).to be false
    expect(validation.errors[:input_json].join).to include("timezone")
  end
end
