require "rails_helper"
require "csv"

RSpec.describe Transformers::DecimalParseTransformer do
  subject(:processor) { described_class.new(transformation) }

  let(:input_type) do
    FileType.new(name: "Input").tap do |file_type|
      file_type.columns.build(name: "amount", position: 0)
    end
  end
  let(:output_column) { Column.new(name: "parsed_amount", position: 0) }
  let(:mapping) { TransformMap.new(input_file_type: input_type) }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column,
                       input_json: { "source_column" => "amount" })
  end
  let(:source) { CSV::Row.new(["other", "amount"], ["unrelated", value]) }
  let(:destination) { CSV::Row.new(["parsed_amount", "existing"], ["previous", "retain"]) }

  {
    "zero" => ["0", "0.0"],
    "fractional" => ["12.50", "12.5"],
    "signed" => ["-0.125", "-0.125"],
    "padded" => [" 12.50 ", "12.5"],
    "exponent" => ["1.25e3", "1250.0"],
    "high-precision" => ["9007199254740993.123456789", "9007199254740993.123456789"],
  }.each do |description, (field, expected)|
    context "with a #{description} decimal" do
      let(:value) { field }

      it "writes an exact BigDecimal and returns no error" do
        original = source.to_h

        expect(processor.transform(source, destination)).to be_nil
        expect(destination["parsed_amount"]).to be_a(BigDecimal)
        expect(destination["parsed_amount"].to_s("F")).to eq(expected)
        expect(destination["existing"]).to eq("retain")
        expect(source.to_h).to eq(original)
      end
    end
  end

  { "NULL" => nil, "empty" => "", "whitespace-only" => " \t\n" }.each do |description, field|
    context "with a #{description} field" do
      let(:value) { field }

      it "writes NULL and returns no error so output validation determines acceptance" do
        expect(processor.transform(source, destination)).to be_nil
        expect(destination.to_h).to eq("parsed_amount" => nil, "existing" => "retain")
      end
    end
  end

  {
    "nonnumeric" => "invalid",
    "partially numeric" => "12abc",
    "malformed" => "1.2.3",
    "NaN" => "NaN",
    "positive infinity" => "Infinity",
    "negative infinity" => "-Infinity",
  }.each do |description, field|
    context "with a #{description} value" do
      let(:value) { field }

      it "returns a decimal error and clears only the target" do
        original = source.to_h

        expect(processor.transform(source, destination)).to eq('source column "amount" contains an invalid decimal')
        expect(destination.to_h).to eq("parsed_amount" => nil, "existing" => "retain")
        expect(source.to_h).to eq(original)
      end
    end
  end
end
