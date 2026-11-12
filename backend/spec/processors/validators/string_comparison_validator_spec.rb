require "rails_helper"
require "csv"

RSpec.describe Validators::StringComparisonValidator do
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
    ["==", "apple", "apple", true],
    ["==", "apple", "pear", false],
    ["!=", "apple", "pear", true],
    ["!=", "apple", "apple", false],
    ["<", "apple", "pear", true],
    ["<", "apple", "apple", false],
    ["<=", "apple", "apple", true],
    ["<=", "pear", "apple", false],
    [">", "pear", "apple", true],
    [">", "apple", "apple", false],
    [">=", "apple", "apple", true],
    [">=", "apple", "pear", false],
    ["<", "10", "2", true],
    ["<", "Apple", "apple", true],
    ["==", " apple ", "apple", false],
    ["==", nil, "", true],
    ["==", "", " \t\n", true],
    ["==", nil, "0", false],
    ["!=", nil, "apple", true],
    ["<", nil, "apple", true],
    [">", "apple", nil, true],
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

  it "compares absent CSV fields as empty strings" do
    expect(processor.validate(CSV::Row.new(["other"], ["unrelated"]))).to be true
  end
end
