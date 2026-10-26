require "rails_helper"
require "csv"

RSpec.describe Validators::NumericRangeValidator do
  subject(:processor) { described_class.new(validation) }

  let(:column) { Column.new(name: "amount", position: 0) }
  let(:parameters) { { "min" => -2.5, "max" => 10.5 } }
  let(:validation) { Validation.new(column: column, input_json: parameters) }
  let(:row) { CSV::Row.new(["other", "amount"], ["unrelated", value]) }

  {
    "below the minimum" => ["-2.51", false],
    "at the minimum" => ["-2.5", true],
    "zero" => ["0", true],
    "at the maximum" => ["10.5", true],
    "above the maximum" => ["10.51", false],
    "signed and padded" => [" +2.50 ", true],
    "exponent notation" => ["1.05e1", true],
    "nonnumeric" => ["invalid", false],
    "partially numeric" => ["2abc", false],
    "malformed" => ["1.2.3", false],
    "NaN" => ["NaN", false],
    "positive infinity" => ["Infinity", false],
    "negative infinity" => ["-Infinity", false],
    "NULL" => [nil, true],
    "empty" => ["", true],
    "whitespace-only" => [" \t\n", true],
    "parsed integer" => [2, true],
    "parsed decimal" => [BigDecimal("2.5"), true],
  }.each do |description, (field, accepted)|
    context "with a #{description} value" do
      let(:value) { field }

      it "#{accepted ? 'accepts' : 'rejects'} the value without changing the row" do
        original = row.to_h

        expect(processor.validate(row)).to be accepted
        expect(row.to_h).to eq(original)
      end
    end
  end

  it "skips an absent CSV field" do
    expect(processor.validate(CSV::Row.new(["other"], ["unrelated"]))).to be true
  end

  context "with a minimum only" do
    let(:parameters) { { "min" => 0 } }

    { "-0.01" => false, "0" => true, "1e20" => true }.each do |field, accepted|
      it "#{accepted ? 'accepts' : 'rejects'} #{field}" do
        row = CSV::Row.new(["amount"], [field])

        expect(processor.validate(row)).to be accepted
      end
    end
  end

  context "with a maximum only" do
    let(:parameters) { { "max" => 0.1 } }

    { "-1e20" => true, "0.1" => true, "0.10000000000000000001" => false }.each do |field, accepted|
      it "#{accepted ? 'accepts' : 'rejects'} #{field} without rounding through Float" do
        row = CSV::Row.new(["amount"], [field])

        expect(processor.validate(row)).to be accepted
      end
    end
  end

  context "with equal large integer bounds" do
    let(:parameters) { { "min" => 9007199254740993, "max" => 9007199254740993 } }

    { "9007199254740992" => false, "9007199254740993" => true, "9007199254740994" => false }.each do |field, accepted|
      it "#{accepted ? 'accepts' : 'rejects'} #{field} without losing precision" do
        row = CSV::Row.new(["amount"], [field])

        expect(processor.validate(row)).to be accepted
      end
    end
  end
end
