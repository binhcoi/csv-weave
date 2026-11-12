require "rails_helper"
require "csv"

RSpec.describe Transformers::IntegerParseTransformer do
  subject(:processor) { described_class.new(transformation) }

  let(:input_type) do
    FileType.new(name: "Input").tap do |file_type|
      file_type.columns.build(name: "amount", position: 0)
    end
  end
  let(:output_type) { FileType.new(name: "Output") }
  let(:output_column) { output_type.columns.build(name: "parsed_amount", position: 0) }
  let(:mapping) { TransformMap.new(input_file_type: input_type, output_file_type: output_type) }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column,
                       input_json: { "source_column" => "amount" })
  end
  let(:source) { CSV::Row.new(["other", "amount"], ["unrelated", value]) }
  let(:destination) { CSV::Row.new(["parsed_amount", "existing"], ["previous", "retain"]) }

  { "zero" => ["0", 0], "signed" => ["-42", -42], "padded" => [" 42 ", 42] }.each do |description, (field, parsed)|
    context "with a #{description} integer" do
      let(:value) { field }

      it "writes the parsed value and returns no error" do
        original = source.to_h

        expect(processor.transform(source, destination)).to be_nil
        expect(destination.to_h).to eq("parsed_amount" => parsed, "existing" => "retain")
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

  { "nonnumeric" => "invalid", "partially numeric" => "12abc", "decimal" => "12.50" }.each do |description, field|
    context "with a #{description} value" do
      let(:value) { field }

      it "returns a parsing error and clears the target without changing other fields" do
        original = source.to_h

        expect(processor.transform(source, destination)).to eq('source column "amount" contains an invalid integer')
        expect(destination.to_h).to eq("parsed_amount" => nil, "existing" => "retain")
        expect(source.to_h).to eq(original)
      end
    end
  end
end
