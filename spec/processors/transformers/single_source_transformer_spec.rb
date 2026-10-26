require "rails_helper"
require "csv"

RSpec.describe Transformers::SingleSourceTransformer do
  it "returns an error and clears only the target when the configured source no longer exists" do
    input_type = FileType.new(name: "Input")
    output_column = Column.new(name: "result", position: 0)
    mapping = TransformMap.new(input_file_type: input_type)
    transformation = Transformation.new(transform_map: mapping, output_column: output_column,
                                        input_json: { "source_column" => "missing" })
    processor = described_class.new(transformation)
    source = CSV::Row.new(["other"], ["unrelated"])
    destination = CSV::Row.new(["result", "existing"], ["previous", "retain"])

    expect(processor.transform(source, destination))
      .to eq('source column "missing" does not exist in the map\'s input file type')
    expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
    expect(source.to_h).to eq("other" => "unrelated")
  end
end
