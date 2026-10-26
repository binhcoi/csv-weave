require "rails_helper"
require "csv"

RSpec.describe Validators::DateValidator do
  subject(:processor) { described_class.new(validation) }

  let(:column) { Column.new(name: "joined_on", position: 0) }
  let(:parameters) { { "format" => "%Y-%m-%d" } }
  let(:validation) { Validation.new(column: column, input_json: parameters) }
  let(:row) { CSV::Row.new(["other", "joined_on"], ["2024-02-29", value]) }

  {
    "valid leap day" => ["2024-02-29", true],
    "ordinary date" => ["2026-10-26", true],
    "invalid leap day" => ["2025-02-29", false],
    "impossible day" => ["2026-04-31", false],
    "invalid month" => ["2026-13-01", false],
    "wrong separator" => ["2026/10/26", false],
    "unpadded date" => ["2026-2-3", false],
    "leading whitespace" => [" 2026-10-26", false],
    "trailing whitespace" => ["2026-10-26 ", false],
    "trailing text" => ["2026-10-26 extra", false],
    "trailing time" => ["2026-10-26T12:00:00Z", false],
    "nonnumeric date" => ["invalid", false],
    "numeric output" => [20261026, false],
    "NULL" => [nil, true],
    "empty" => ["", true],
    "whitespace-only" => [" \t\n", true],
  }.each do |description, (field, accepted)|
    context "with a #{description} field" do
      let(:value) { field }

      it "#{accepted ? 'accepts' : 'rejects'} the field without changing the row" do
        original = row.to_h

        expect(processor.validate(row)).to be accepted
        expect(row.to_h).to eq(original)
      end
    end
  end

  it "skips an absent CSV field" do
    expect(processor.validate(CSV::Row.new(["other"], ["invalid"]))).to be true
  end

  {
    "day first" => ["%d/%m/%Y", "29/02/2024"],
    "month name" => ["%d %b %Y", "29 Feb 2024"],
    "ordinal date" => ["%Y-%j", "2024-060"],
    "ISO week date" => ["%G-W%V-%u", "2024-W09-4"],
  }.each do |description, (format, field)|
    context "with a #{description} format" do
      let(:parameters) { { "format" => format } }
      let(:value) { field }

      it "uses the configured strptime format" do
        expect(processor.validate(row)).to be true
      end
    end
  end

  context "with a date before the Gregorian reform" do
    let(:value) { "1500-02-29" }

    it "applies Gregorian calendar rules consistently" do
      expect(processor.validate(row)).to be false
    end
  end

  context "with both bounds" do
    let(:parameters) { { "format" => "%d/%m/%Y", "min" => "2024-02-28", "max" => "2024-03-01" } }

    {
      "27/02/2024" => false,
      "28/02/2024" => true,
      "29/02/2024" => true,
      "01/03/2024" => true,
      "02/03/2024" => false,
    }.each do |field, accepted|
      it "#{accepted ? 'accepts' : 'rejects'} #{field} using inclusive ISO bounds" do
        row = CSV::Row.new(["joined_on"], [field])

        expect(processor.validate(row)).to be accepted
      end
    end
  end

  context "with a minimum only" do
    let(:parameters) { { "format" => "%Y-%m-%d", "min" => "2024-02-29" } }
    let(:value) { "2030-12-31" }

    it "allows later dates without an upper limit" do
      expect(processor.validate(row)).to be true
    end
  end

  context "with a maximum only" do
    let(:parameters) { { "format" => "%Y-%m-%d", "max" => "2024-02-29" } }
    let(:value) { "2020-01-01" }

    it "allows earlier dates without a lower limit" do
      expect(processor.validate(row)).to be true
    end
  end

  context "with equal bounds" do
    let(:parameters) { { "format" => "%Y-%m-%d", "min" => "2024-02-29", "max" => "2024-02-29" } }

    { "2024-02-28" => false, "2024-02-29" => true, "2024-03-01" => false }.each do |field, accepted|
      it "#{accepted ? 'accepts' : 'rejects'} #{field}" do
        row = CSV::Row.new(["joined_on"], [field])

        expect(processor.validate(row)).to be accepted
      end
    end
  end
end
