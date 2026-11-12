require "rails_helper"
require "csv"

RSpec.describe Transformers::SubstringTransformer do
  subject(:processor) { described_class.new(transformation) }

  let(:input_type) do
    FileType.new(name: "Input").tap do |file_type|
      file_type.columns.build(name: "product_code", position: 0)
    end
  end
  let(:output_type) { FileType.new(name: "Output") }
  let(:output_column) { output_type.columns.build(name: "code", position: 0) }
  let(:mapping) { TransformMap.new(input_file_type: input_type, output_file_type: output_type) }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column,
                       input_json: { "source_column" => "product_code", "start" => start, "length" => length })
  end
  let(:source) { CSV::Row.new(["other", "product_code"], ["unrelated", value]) }
  let(:destination) { CSV::Row.new(["code", "existing"], ["previous", "retain"]) }

  {
    "a middle substring" => ["AB1234XY", 2, 4, "1234"],
    "the first character" => ["AB1234XY", 0, 1, "A"],
    "the last character" => ["AB1234XY", 7, 1, "Y"],
    "a length past the end" => ["AB1234XY", 6, 100, "XY"],
    "a start at the end" => ["AB1234XY", 8, 1, ""],
    "a start past the end" => ["AB1234XY", 9, 1, ""],
    "a zero length" => ["AB1234XY", 2, 0, ""],
    "an empty field" => ["", 0, 4, ""],
    "a NULL field" => [nil, 2, 4, nil],
    "whitespace" => [" \t\n ", 1, 2, "\t\n"],
    "Unicode characters" => ["Aé猫🙂Z", 1, 3, "é猫🙂"],
    "a combining character" => ["Ae\u0301Z", 1, 2, "e\u0301"],
    "quotes, commas, and newlines" => ["x\",\ny", 1, 3, "\",\n"],
    "an arbitrarily large start" => ["AB1234XY", 10**100, 4, ""],
    "an arbitrarily large length" => ["AB1234XY", 2, 10**100, "1234XY"],
  }.each do |description, (field, offset, count, expected)|
    context "with #{description}" do
      let(:value) { field }
      let(:start) { offset }
      let(:length) { count }

      it "writes the substring and preserves the source and other destination fields" do
        original = source.to_h

        expect(processor.transform(source, destination)).to be_nil
        expect(destination.to_h).to eq("code" => expected, "existing" => "retain")
        expect(source.to_h).to eq(original)
      end
    end
  end

  context "with a missing CSV header" do
    let(:source) { CSV::Row.new(["other"], ["unrelated"]) }
    let(:start) { 2 }
    let(:length) { 4 }

    it "writes NULL and leaves acceptance to output validation" do
      expect(processor.transform(source, destination)).to be_nil
      expect(destination.to_h).to eq("code" => nil, "existing" => "retain")
    end
  end
end
