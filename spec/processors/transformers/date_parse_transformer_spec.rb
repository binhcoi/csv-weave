require "rails_helper"
require "csv"

RSpec.describe Transformers::DateParseTransformer do
  subject(:processor) { described_class.new(transformation) }

  let(:input_type) do
    FileType.new(name: "Input").tap do |file_type|
      file_type.columns.build(name: "joined_on", position: 0)
    end
  end
  let(:output_column) { Column.new(name: "joined_date", position: 0) }
  let(:mapping) { TransformMap.new(input_file_type: input_type) }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column,
                       input_json: { "source_column" => "joined_on", "format" => format })
  end
  let(:format) { "%d/%m/%Y" }
  let(:source) { CSV::Row.new(["other", "joined_on"], ["unrelated", value]) }
  let(:destination) { CSV::Row.new(["joined_date", "existing"], ["previous", "retain"]) }

  {
    "a leap day" => ["%d/%m/%Y", "29/02/2024", "2024-02-29"],
    "an ordinary date" => ["%d/%m/%Y", "26/10/2026", "2026-10-26"],
    "an ISO date" => ["%Y-%m-%d", "2024-02-29", "2024-02-29"],
    "a month name" => ["%d %b %Y", "29 Feb 2024", "2024-02-29"],
    "an ordinal date" => ["%Y-%j", "2024-060", "2024-02-29"],
    "an ISO week date" => ["%G-W%V-%u", "2024-W09-4", "2024-02-29"],
    "an ISO week in a different calendar year" => ["%G-W%V-%u", "2020-W01-1", "2019-12-30"],
    "a Gregorian date before the reform" => ["%Y-%m-%d", "1500-03-01", "1500-03-01"],
    "format literals containing commas and newlines" => ["%Y,\n%m,%d", "2024,\n02,29", "2024-02-29"],
  }.each do |description, (date_format, field, expected)|
    context "with #{description}" do
      let(:format) { date_format }
      let(:value) { field }

      it "writes an ISO date string and preserves the source and other destination fields" do
        original = source.to_h

        expect(processor.transform(source, destination)).to be_nil
        expect(destination.to_h).to eq("joined_date" => expected, "existing" => "retain")
        expect(source.to_h).to eq(original)
      end
    end
  end

  {
    "an invalid leap day" => "29/02/2025",
    "an impossible day" => "31/04/2024",
    "an invalid month" => "01/13/2024",
    "the wrong separator" => "29-02-2024",
    "an unpadded date" => "9/2/2024",
    "leading whitespace" => " 29/02/2024",
    "trailing whitespace" => "29/02/2024 ",
    "trailing text" => "29/02/2024 extra",
    "a trailing time" => "29/02/2024T12:00:00Z",
    "a non-Gregorian leap day" => "29/02/1500",
    "non-date text" => "invalid",
    "a numeric value" => 20240229,
  }.each do |description, field|
    context "with #{description}" do
      let(:value) { field }

      it "returns a date error and clears only the target" do
        original = source.to_h

        expect(processor.transform(source, destination)).to eq('source column "joined_on" contains an invalid date')
        expect(destination.to_h).to eq("joined_date" => nil, "existing" => "retain")
        expect(source.to_h).to eq(original)
      end
    end
  end

  {
    "month-name case mismatch" => ["%d %b %Y", "29 feb 2024"],
    "an invalid ordinal day" => ["%Y-%j", "2023-366"],
    "an invalid ISO week" => ["%G-W%V-%u", "2021-W53-1"],
  }.each do |description, (date_format, field)|
    context "with #{description}" do
      let(:format) { date_format }
      let(:value) { field }

      it "returns a date error and clears only the target" do
        expect(processor.transform(source, destination)).to eq('source column "joined_on" contains an invalid date')
        expect(destination.to_h).to eq("joined_date" => nil, "existing" => "retain")
      end
    end
  end

  { "NULL" => nil, "empty" => "", "whitespace-only" => " \t\n" }.each do |description, field|
    context "with a #{description} field" do
      let(:value) { field }

      it "writes NULL and leaves acceptance to output validation" do
        expect(processor.transform(source, destination)).to be_nil
        expect(destination.to_h).to eq("joined_date" => nil, "existing" => "retain")
      end
    end
  end

  it "writes NULL for a missing CSV header" do
    source = CSV::Row.new(["other"], ["unrelated"])

    expect(processor.transform(source, destination)).to be_nil
    expect(destination.to_h).to eq("joined_date" => nil, "existing" => "retain")
  end

  it "produces text accepted by an ISO output date validator" do
    source = CSV::Row.new(["joined_on"], ["29/02/2024"])
    validation = Validation.new(column: output_column, input_json: { "format" => "%Y-%m-%d" })

    expect(processor.transform(source, destination)).to be_nil
    expect(Validators::DateValidator.new(validation).validate(destination)).to be true
  end

  {
    "a month-first date" => ["%m/%d/%Y", "02/29/2024"],
    "a compact date" => ["%Y%m%d", "20240229"],
    "an ordinal date" => ["%Y-%j", "2024-060"],
    "an ISO week date" => ["%G-W%V-%u", "2024-W09-4"],
    "a partial date" => ["%Y-%m", "2024-02"],
    "Unicode, quotes, commas, newlines, and a literal percent" => ["日付 \"%d\",\n%b %Y %%", "日付 \"29\",\nFeb 2024 %"],
  }.each do |description, (output_format, expected)|
    it "writes #{description} using the configured output format" do
      transformation.input_json["output_format"] = output_format
      source = CSV::Row.new(["joined_on"], ["29/02/2024"])
      original = source.to_h

      expect(processor.transform(source, destination)).to be_nil
      expect(destination.to_h).to eq("joined_date" => expected, "existing" => "retain")
      expect(source.to_h).to eq(original)
    end
  end

  it "produces text accepted by an output date validator with the selected format" do
    transformation.input_json["output_format"] = "%m/%d/%Y"
    source = CSV::Row.new(["joined_on"], ["29/02/2024"])
    validation = Validation.new(column: output_column, input_json: { "format" => "%m/%d/%Y" })

    expect(processor.transform(source, destination)).to be_nil
    expect(Validators::DateValidator.new(validation).validate(destination)).to be true
  end
end
