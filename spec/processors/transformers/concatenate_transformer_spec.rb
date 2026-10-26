require "rails_helper"
require "csv"

RSpec.describe Transformers::ConcatenateTransformer do
  subject(:processor) { described_class.new(transformation) }

  let(:input_type) do
    FileType.new(name: "Input").tap do |file_type|
      ["given", "middle", "family"].each_with_index do |name, position|
        file_type.columns.build(name: name, position: position)
      end
    end
  end
  let(:output_column) { Column.new(name: "full_name", position: 0) }
  let(:mapping) { TransformMap.new(input_file_type: input_type) }
  let(:parameters) { { "source_columns" => ["family", "given"], "separator" => " " } }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column, input_json: parameters)
  end
  let(:source) { CSV::Row.new(["other", "family", "given", "middle"], ["unrelated", "Morgan", "Alex", nil]) }
  let(:destination) { CSV::Row.new(["full_name", "existing"], ["previous", "retain"]) }

  it "joins by configured source order and header, preserving the source and other destination fields" do
    original = source.to_h

    expect(processor.transform(source, destination)).to be_nil
    expect(destination.to_h).to eq("full_name" => "Morgan Alex", "existing" => "retain")
    expect(source.to_h).to eq(original)
  end

  context "with no separator setting" do
    let(:parameters) { { "source_columns" => ["given", "family"] } }

    it "joins without a separator" do
      expect(processor.transform(source, destination)).to be_nil
      expect(destination["full_name"]).to eq("AlexMorgan")
    end
  end

  context "with repeated source columns" do
    let(:parameters) { { "source_columns" => ["given", "family", "given"], "separator" => ", " } }

    it "keeps every occurrence in the configured order" do
      expect(processor.transform(source, destination)).to be_nil
      expect(destination["full_name"]).to eq("Alex, Morgan, Alex")
    end
  end

  context "with one source column" do
    let(:parameters) { { "source_columns" => ["given"], "separator" => "::" } }

    it "writes the value without adding a separator" do
      expect(processor.transform(source, destination)).to be_nil
      expect(destination["full_name"]).to eq("Alex")
    end
  end

  { "NULL" => nil, "empty" => "", "whitespace-only" => " \t\n" }.each do |description, value|
    context "with a #{description} middle field" do
      let(:parameters) { { "source_columns" => ["given", "middle", "family"], "separator" => " " } }

      it "skips the blank value without an extra separator" do
        source["middle"] = value

        expect(processor.transform(source, destination)).to be_nil
        expect(destination["full_name"]).to eq("Alex Morgan")
      end
    end
  end

  it "skips a configured column whose CSV header is missing" do
    transformation.input_json = { "source_columns" => ["given", "middle", "family"], "separator" => " " }
    source = CSV::Row.new(["family", "given"], ["Morgan", "Alex"])

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["full_name"]).to eq("Alex Morgan")
  end

  it "writes an empty string without an error when all selected values are blank" do
    source["given"] = nil
    source["family"] = " \t"

    expect(processor.transform(source, destination)).to be_nil
    expect(destination.to_h).to eq("full_name" => "", "existing" => "retain")
  end

  it "preserves spaces and CSV-sensitive characters in nonblank values" do
    source["given"] = " Alex, \"A\"\n"
    source["family"] = " \u674e "

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["full_name"]).to eq(" \u674e   Alex, \"A\"\n")
  end

  it "keeps zero as a nonblank value" do
    source["given"] = 0

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["full_name"]).to eq("Morgan 0")
  end

  it "returns an error and clears only the target when a later configured source no longer exists" do
    transformation.input_json = { "source_columns" => ["given", "missing"], "separator" => " " }
    original = source.to_h

    expect(processor.transform(source, destination))
      .to eq('source column "missing" does not exist in the map\'s input file type')
    expect(destination.to_h).to eq("full_name" => nil, "existing" => "retain")
    expect(source.to_h).to eq(original)
  end

  it "returns an error and clears the target for an empty source configuration" do
    transformation.input_json = {}

    expect(processor.transform(source, destination)).to eq("must include at least one source column")
    expect(destination.to_h).to eq("full_name" => nil, "existing" => "retain")
  end
end
