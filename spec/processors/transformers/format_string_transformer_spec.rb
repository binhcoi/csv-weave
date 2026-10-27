require "rails_helper"
require "csv"

RSpec.describe Transformers::FormatStringTransformer do
  subject(:processor) { described_class.new(transformation) }

  let(:input_type) do
    FileType.new(name: "Input").tap do |file_type|
      ["given", "family", "unused", "full name", "名前"].each_with_index do |name, position|
        file_type.columns.build(name: name, position: position)
      end
    end
  end
  let(:output_column) { Column.new(name: "result", position: 0) }
  let(:mapping) { TransformMap.new(input_file_type: input_type) }
  let(:parameters) { { "source_columns" => ["given", "family"], "format" => template } }
  let(:template) { "%{family}, %{given}" }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column, input_json: parameters)
  end
  let(:source) { CSV::Row.new(["other", "family", "given"], ["unrelated", "Morgan", "Alex"]) }
  let(:destination) { CSV::Row.new(["result", "existing"], ["previous", "retain"]) }

  {
    "named placeholders in template order" => ["%{family}, %{given}", "Morgan, Alex"],
    "repeated placeholders" => ["%{given}/%{given}/%{family}", "Alex/Alex/Morgan"],
    "adjacent placeholders" => ["%{family}%{given}", "MorganAlex"],
    "a literal percent" => ["%{given}: 100%%", "Alex: 100%"],
    "an escaped placeholder" => ["%%{given}", "%{given}"],
    "a percent before a placeholder" => ["%%%{given}", "%Alex"],
    "consecutive percent escapes" => ["%%%%", "%%"],
    "an empty template" => ["", ""],
    "a literal-only template" => ["Customer", "Customer"],
    "Unicode, quotes, commas, and newlines" => ["名: \"%{given}\",\n%{family}", "名: \"Alex\",\nMorgan"],
    "Ruby-like text" => ['#{raise "must remain text"}', '#{raise "must remain text"}'],
  }.each do |description, (format, expected)|
    context "with #{description}" do
      let(:template) { format }

      it "writes the formatted text and preserves the source and other destination fields" do
        original = source.to_h

        expect(processor.transform(source, destination)).to be_nil
        expect(destination.to_h).to eq("result" => expected, "existing" => "retain")
        expect(source.to_h).to eq(original)
      end
    end
  end

  { "NULL" => [nil, ", Alex"], "empty" => ["", ", Alex"], "whitespace-only" => [" \t", " \t, Alex"] }.each do |description, (value, expected)|
    it "preserves template punctuation with a #{description} field" do
      source["family"] = value

      expect(processor.transform(source, destination)).to be_nil
      expect(destination["result"]).to eq(expected)
    end
  end

  it "uses an empty string for a missing CSV header" do
    source = CSV::Row.new(["given"], ["Alex"])

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["result"]).to eq(", Alex")
  end

  it "keeps punctuation when every source value is blank" do
    source["family"] = nil
    source["given"] = ""

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["result"]).to eq(", ")
  end

  it "supports repeated declarations and unused sources" do
    transformation.input_json["source_columns"] = ["family", "given", "given", "unused"]

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["result"]).to eq("Morgan, Alex")
  end

  it "matches column names with spaces and Unicode exactly" do
    transformation.input_json = { "source_columns" => ["full name", "名前"], "format" => "%{名前}: %{full name}" }
    source = CSV::Row.new(["名前", "full name"], ["李", "Alex Morgan"])

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["result"]).to eq("李: Alex Morgan")
  end

  it "inserts values verbatim without treating placeholder syntax or backreferences as formatting" do
    source["given"] = '%{family} %% \1 \\ #{raise "must remain text"}'

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["result"]).to eq("Morgan, #{source['given']}")
  end

  it "converts non-string values to text, including zero" do
    source["given"] = 0

    expect(processor.transform(source, destination)).to be_nil
    expect(destination["result"]).to eq("Morgan, 0")
  end

  ["%", "%s", "%d", "%<given>s", "%{", "%{}", "%{given", "%{{given}}", "text % tail"].each do |format|
    it "returns an error and clears only the target for invalid template #{format.inspect}" do
      transformation.input_json["format"] = format
      original = source.to_h

      expect(processor.transform(source, destination)).to include("format supports only")
      expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
      expect(source.to_h).to eq(original)
    end
  end

  it "returns an error for an unlisted placeholder even if the input column exists" do
    transformation.input_json["format"] = "%{unused}"

    expect(processor.transform(source, destination)).to include('placeholder "unused" must name a listed source column')
    expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
  end

  it "returns an error when an unused declared source no longer exists" do
    transformation.input_json["source_columns"] << "missing"

    expect(processor.transform(source, destination)).to include('source column "missing" does not exist')
    expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
  end

  it "returns an error for missing source configuration" do
    transformation.input_json = nil

    expect(processor.transform(source, destination)).to include("source_columns must be a nonempty array")
    expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
  end

  it "returns an error for a non-string template" do
    transformation.input_json["format"] = nil

    expect(processor.transform(source, destination)).to eq("format must be a string")
    expect(destination.to_h).to eq("result" => nil, "existing" => "retain")
  end
end
