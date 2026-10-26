require "rails_helper"
require "csv"

RSpec.describe Validators::NumericComparisonValidator do
  subject(:processor) { described_class.new(validation) }

  let(:file_type) do
    FileType.new(name: "Input").tap do |type|
      type.columns.build(name: "value", position: 0)
      type.columns.build(name: "other_value", position: 1)
    end
  end
  let(:operator) { "==" }
  let(:validation) do
    Validation.new(column: file_type.columns.first,
                   input_json: { "other_column" => "other_value", "operator" => operator })
  end
  let(:row) { CSV::Row.new(["other", "value", "other_value"], ["unrelated", left, right]) }

  [
    ["==", "02.00", "2", true],
    ["==", "2", "10", false],
    ["!=", "2", "10", true],
    ["!=", "2.0", "2", false],
    ["<", "2", "10", true],
    ["<", "2.0", "2", false],
    ["<=", "2.0", "2", true],
    ["<=", "10", "2", false],
    [">", "10", "2", true],
    [">", "2.0", "2", false],
    [">=", "2.0", "2", true],
    [">=", "2", "10", false],
    ["==", " +1.25e2 ", "125", true],
    ["<", "-2.5", "-2.4", true],
    ["<", "9007199254740993.000000001", "9007199254740993.000000002", true],
    ["==", BigDecimal("2.5"), "2.50", true],
    ["==", 2, "2.00", true],
    ["==", nil, "0", true],
    ["==", "", " \t\n", true],
    ["!=", nil, "1", true],
    ["<", nil, "1", true],
    [">", "1", nil, true],
  ].each do |operation, first, second, accepted|
    context "with #{first.inspect} #{operation} #{second.inspect}" do
      let(:operator) { operation }
      let(:left) { first }
      let(:right) { second }

      it "returns #{accepted} without changing the row" do
        original = row.to_h

        expect(processor.validate(row)).to be accepted
        expect(row.to_h).to eq(original)
      end
    end
  end

  ["invalid", "2abc", "NaN", "Infinity", "-Infinity"].each do |invalid|
    [:left, :right].each do |side|
      context "with an invalid #{side} value #{invalid.inspect}" do
        let(:operator) { "!=" }
        let(:left) { side == :left ? invalid : "1" }
        let(:right) { side == :right ? invalid : "1" }

        it "rejects the comparison even for inequality" do
          expect(processor.validate(row)).to be false
        end
      end
    end
  end

  it "compares absent CSV fields as zero" do
    expect(processor.validate(CSV::Row.new(["other"], ["unrelated"]))).to be true
  end
end
