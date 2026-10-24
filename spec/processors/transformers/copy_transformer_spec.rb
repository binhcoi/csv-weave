require "rails_helper"
require "csv"

RSpec.describe Transformers::CopyTransformer do
  subject(:processor) { described_class.new(transformation) }

  let(:input_type) do
    FileType.new(name: "Input").tap do |file_type|
      file_type.columns.build(name: "source_email", position: 0)
      file_type.columns.build(name: "other", position: 1)
    end
  end
  let(:output_type) { FileType.new(name: "Output") }
  let(:output_column) { output_type.columns.build(name: "contact_email", position: 0) }
  let(:mapping) { TransformMap.new(input_file_type: input_type, output_file_type: output_type) }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column,
                       input_json: { "name" => "source_email" })
  end
  let(:source) { CSV::Row.new(["other", "source_email"], ["unrelated", value]) }
  let(:destination) { CSV::Row.new(["contact_email", "optional", "existing"], [nil, nil, "retain"]) }

  {
    "a populated field" => "user@example.com",
    "a NULL field" => nil,
    "an empty field" => "",
    "quotes, commas, and an embedded newline" => "A \"quoted\", value\nnext line",
  }.each do |description, field|
    context "with #{description}" do
      let(:value) { field }

      it "copies by header to the renamed output and preserves the other fields" do
        original = source.to_h

        processor.transform(source, destination)

        expect(destination.to_h).to eq("contact_email" => value, "optional" => nil, "existing" => "retain")
        expect(destination.headers).to eq(["contact_email", "optional", "existing"])
        expect(source.to_h).to eq(original)
      end
    end
  end

  it "writes NULL when the configured source header is absent from the row" do
    source = CSV::Row.new(["other"], ["unrelated"])
    destination["contact_email"] = "previous"

    processor.transform(source, destination)

    expect(destination.to_h).to eq("contact_email" => nil, "optional" => nil, "existing" => "retain")
  end
end
