require "rails_helper"
require "csv"

RSpec.describe Transformers::ArithmeticTransformer do
  subject(:processor) { described_class.new(transformation) }

  let(:input_type) do
    FileType.new(name: "Input").tap do |file_type|
      ["left", "right"].each_with_index { |name, position| file_type.columns.build(name: name, position: position) }
    end
  end
  let(:output_column) { Column.new(name: "result", position: 0) }
  let(:mapping) { TransformMap.new(input_file_type: input_type) }
  let(:parameters) { { "source_columns" => ["left", "right"], "operator" => "+" } }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column, input_json: parameters)
  end
  let(:source) { CSV::Row.new(["other", "right", "left"], ["unrelated", "8.25", "100"]) }
  let(:destination) { CSV::Row.new(["result", "existing"], ["previous", "retain"]) }

  {
    "addition" => ["+", "100", "8.25", "108.25"],
    "subtraction" => ["-", "8.25", "100", "-91.75"],
    "multiplication" => ["*", "1.25", "3", "3.75"],
    "decimal addition" => ["+", "0.1", "0.2", "0.3"],
    "high-precision addition" => ["+", "9007199254740993.123456789", "0.000000001", "9007199254740993.12345679"],
    "high-precision multiplication" => ["*", "9007199254740993.123456789", "0.1", "900719925474099.3123456789"],
    "signs, whitespace, and exponent notation" => ["+", " -1.25e2 ", " +2.5e1 ", "-100.0"],
    "parsed numeric values" => ["+", BigDecimal("1.25"), 2, "3.25"],
  }.each do |description, (operator, left, right, expected)|
    it "calculates #{description} exactly and preserves the source and other destination fields" do
      transformation.input_json["operator"] = operator
      source["left"] = left
      source["right"] = right
      original = source.to_h

      expect(processor.transform(source, destination)).to be_nil
      expect(destination["result"]).to be_a(BigDecimal)
      expect(destination["result"].to_s("F")).to eq(expected)
      expect(destination["existing"]).to eq("retain")
      expect(source.to_h).to eq(original)
    end
  end

  it "uses the configured operand order" do
    transformation.input_json = { "source_columns" => ["right", "left"], "operator" => "-" }

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["result"].to_s("F")).to eq("-91.75")
  end

  it "permits repeated source columns" do
    transformation.input_json = { "source_columns" => ["right", "right"], "operator" => "*" }

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["result"].to_s("F")).to eq("68.0625")
  end

  { "NULL" => nil, "empty" => "", "whitespace-only" => " \t\n" }.each do |description, value|
    it "treats a #{description} operand as zero" do
      source["left"] = value

      expect(processor.transform(source, destination)).to be_nil
      expect(destination["result"].to_s("F")).to eq("8.25")
    end
  end

  it "treats missing CSV headers as zero" do
    source = CSV::Row.new(["other"], ["unrelated"])

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["result"]).to eq(BigDecimal("0"))
  end

  {
    "recurring division" => ["1", "3", 2, "0.33"],
    "positive halfway rounding" => ["1", "8", 2, "0.13"],
    "negative halfway rounding" => ["-1", "8", 2, "-0.13"],
    "a negative divisor" => ["1", "-8", 2, "-0.13"],
    "two negative operands" => ["-1", "-8", 2, "0.13"],
    "whole-number rounding" => ["5", "2", 0, "3.0"],
    "negative whole-number rounding" => ["-5", "2", 0, "-3.0"],
    "an exact quotient" => ["10", "4", 4, "2.5"],
    "below a halfway value" => ["1.0049999999999999999999999999999999999999", "1", 2, "1.0"],
    "above a halfway value" => ["1.0050000000000000000000000000000000000001", "1", 2, "1.01"],
    "a blank numerator" => [nil, "2", 2, "0.0"],
    "the maximum scale" => ["1", "3", 100, "0." + "3" * 100],
  }.each do |description, (left, right, scale, expected)|
    it "handles #{description} without intermediate decimal rounding" do
      transformation.input_json = parameters.merge("operator" => "/", "scale" => scale)
      source["left"] = left
      source["right"] = right
      original = source.to_h

      expect(processor.transform(source, destination)).to be_nil
      expect(destination["result"]).to be_a(BigDecimal)
      expect(destination["result"].to_s("F")).to eq(expected)
      expect(destination["existing"]).to eq("retain")
      expect(source.to_h).to eq(original)
    end
  end

  ["+", "-", "*"].each do |operator|
    it "preserves exact #{operator} results and restores an existing BigDecimal precision limit" do
      transformation.input_json["operator"] = operator
      source["left"] = "123456789.123456789"
      source["right"] = "0.000000001"
      expected = { "+" => "123456789.12345679", "-" => "123456789.123456788", "*" => "0.123456789123456789" }.fetch(operator)

      BigDecimal.save_limit do
        BigDecimal.limit(4)

        expect(processor.transform(source, destination)).to be_nil
        expect(destination["result"].to_s("F")).to eq(expected)
        expect(BigDecimal.limit).to eq(4)
      end
    end
  end

  ["left", "right"].each do |name|
    ["invalid", "12abc", "NaN", "Infinity", "-Infinity"].each do |value|
      it "rejects #{value.inspect} in the #{name} operand and clears only the target" do
        source[name] = value
        original = source.to_h

        expect(processor.transform(source, destination)).to eq("source column #{name.inspect} contains an invalid finite number")
        expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
        expect(source.to_h).to eq(original)
      end
    end
  end

  ["0", "-0.0", nil, "", " \t"].each do |value|
    it "rejects a zero or blank divisor #{value.inspect}" do
      transformation.input_json = parameters.merge("operator" => "/", "scale" => 2)
      source["right"] = value

      expect(processor.transform(source, destination)).to eq("cannot divide by zero")
      expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
    end
  end

  it "rejects a non-finite result" do
    transformation.input_json["operator"] = "*"
    source["left"] = "1e5000000000000000000"
    source["right"] = "1e5000000000000000000"

    expect(processor.transform(source, destination)).to eq("arithmetic result must be finite")
    expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
  end

  it "returns an error if a configured source no longer exists" do
    transformation.input_json["source_columns"] = ["left", "missing"]

    expect(processor.transform(source, destination)).to include('source column "missing" does not exist')
    expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
  end

  it "rejects runtime configuration with an unsupported operator" do
    transformation.input_json["operator"] = "send"

    expect(processor.transform(source, destination)).to include("operator must be one of")
    expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
  end
end
