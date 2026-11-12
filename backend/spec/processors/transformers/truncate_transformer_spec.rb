require "rails_helper"
require "csv"

RSpec.describe Transformers::TruncateTransformer do
  subject(:processor) { described_class.new(transformation) }

  let(:input_type) do
    FileType.new(name: "Input").tap do |file_type|
      file_type.columns.build(name: "description", position: 0)
    end
  end
  let(:output_type) { FileType.new(name: "Output") }
  let(:output_column) { output_type.columns.build(name: "short_description", position: 0) }
  let(:mapping) { TransformMap.new(input_file_type: input_type, output_file_type: output_type) }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column,
                       input_json: { "source_column" => "description", "length" => length })
  end
  let(:source) { CSV::Row.new(["other", "description"], ["unrelated", value]) }
  let(:destination) { CSV::Row.new(["short_description", "existing"], ["previous", "retain"]) }

  {
    "long text" => ["abcdef", 3, "abc"],
    "text at the limit" => ["abc", 3, "abc"],
    "short text" => ["ab", 3, "ab"],
    "zero length" => ["abcdef", 0, ""],
    "an empty field" => ["", 3, ""],
    "a NULL field" => [nil, 3, nil],
    "a NULL field and zero length" => [nil, 0, nil],
    "whitespace" => [" \t\n ", 3, " \t\n"],
    "Unicode characters" => ["é猫🙂Z", 3, "é猫🙂"],
    "a combining character" => ["e\u0301Z", 1, "e"],
    "quotes, commas, and newlines" => ["\",\ntext", 3, "\",\n"],
    "an arbitrarily large length" => ["abcdef", 10**100, "abcdef"],
  }.each do |description, (field, count, expected)|
    context "with #{description}" do
      let(:value) { field }
      let(:length) { count }

      it "writes the prefix and preserves the source and other destination fields" do
        original = source.to_h

        expect(processor.transform(source, destination)).to be_nil
        expect(destination.to_h).to eq("short_description" => expected, "existing" => "retain")
        expect(source.to_h).to eq(original)
      end
    end
  end

  context "with a missing CSV header" do
    let(:source) { CSV::Row.new(["other"], ["unrelated"]) }
    let(:length) { 3 }

    it "writes NULL and leaves acceptance to output validation" do
      expect(processor.transform(source, destination)).to be_nil
      expect(destination.to_h).to eq("short_description" => nil, "existing" => "retain")
    end
  end
end
