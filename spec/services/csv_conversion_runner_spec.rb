require "rails_helper"
require "csv"
require "stringio"
require "tempfile"

RSpec.describe CsvConversionRunner do
  let(:input_type) do
    FileType.new(name: "Input").tap do |type|
      ["name", "amount"].each_with_index { |name, position| type.columns.build(name: name, position: position) }
    end
  end
  let(:mapping) { TransformMap.new(input_file_type: input_type) }
  let(:output_column) { Column.new(name: "copied", position: 0) }
  let(:transformation) do
    Transformation.new(transform_map: mapping, output_column: output_column, input_json: { "source_column" => "name" })
  end
  let(:configuration) do
    ConversionConfigurationLoader::Configuration.new(
      map: mapping, input_columns: input_type.columns.to_a, output_columns: [output_column],
      input_validators: [], transformers: [Transformers::CopyTransformer.new(transformation)], output_validators: [],
    )
  end
  let(:runner) { described_class.new(configuration) }
  let(:output) { StringIO.new }

  it "handles reordered and extra headers, CRLF, and quoted Unicode fields with embedded newlines" do
    name = "李, \"Alex\"\nMorgan"
    csv = CSV.generate(row_sep: "\r\n") do |writer|
      writer << ["amount", "extra", "name"]
      writer << ["12.50", "ignored", name]
      writer << ["1", "ignored", "=1+1"]
    end

    result = convert(csv)

    expect(result.accepted_rows).to eq(2)
    expect(result.rejected_rows).to eq(0)
    expect(result.errors).to be_empty
    expect(output.string).to eq(CSV.generate { |writer| writer << ["copied"]; writer << [name]; writer << ["=1+1"] })
  end

  it "preserves unquoted null fields, quoted empty strings, and whitespace" do
    result = convert("name,amount\n,1\n\"\",2\n  ,3\n")

    expect(result.accepted_rows).to eq(3)
    expect(CSV.parse(output.string, headers: true).map { |row| row["copied"] }).to eq([nil, "", "  "])
  end

  it "writes only the output header for a header-only input" do
    result = convert("name,amount\n")

    expect(output.string).to eq("copied\n")
    expect([result.accepted_rows, result.rejected_rows, result.errors]).to eq([0, 0, []])
  end

  {
    "empty input" => ["", "input must contain a header record"],
    "empty header record" => ["\n", "headers must be nonblank"],
    "unnamed header" => ["name,,amount\n", "headers must be nonblank"],
    "whitespace header" => ["name, ,amount\n", "headers must be nonblank"],
    "duplicate extra headers" => ["name,amount,extra,extra\n", 'duplicate headers: "extra"'],
    "missing exact header" => ["Name,amount\n", 'missing headers: "name"'],
  }.each do |description, (csv, reason)|
    it "rejects #{description} before writing output" do
      expect { convert(csv) }.to raise_error(described_class::InvalidFile) do |error|
        expect(error.error).to eq(record_number: 1, stage: "headers", column: nil, operation: "CSV", reason: reason)
        expect([error.result.accepted_rows, error.result.rejected_rows]).to eq([0, 0])
      end
      expect(output.string).to be_empty
    end
  end

  it "rejects short, long, and blank records, continues, and counts logical records across quoted newlines" do
    result = convert("name,amount\n\"before\nnext line\",1\nshort\nlong,2,extra\n\nafter,3\n")

    expect([result.accepted_rows, result.rejected_rows]).to eq([2, 3])
    expect(result.errors).to eq([
      { record_number: 3, stage: "row_shape", column: nil, operation: "CSV", reason: "expected 2 fields, got 1" },
      { record_number: 4, stage: "row_shape", column: nil, operation: "CSV", reason: "expected 2 fields, got 3" },
      { record_number: 5, stage: "row_shape", column: nil, operation: "CSV", reason: "expected 2 fields, got 0" },
    ])
    expect(CSV.parse(output.string, headers: true).map { |row| row["copied"] }).to eq(["before\nnext line", "after"])
  end

  it "accepts a UTF-8 BOM before a quoted header in binary input and leaves caller IOs open" do
    input = StringIO.new("\xEF\xBB\xBF\"name\",amount\n李,1\n".b)

    result = runner.run(input: input, output: output)

    expect(result.accepted_rows).to eq(1)
    expect(output.string).to eq("copied\n李\n")
    expect(input).not_to be_closed
    expect(output).not_to be_closed
  end

  it "reports invalid UTF-8 as a file error without assigning a misleading record number" do
    expect { convert("name,amount\nAlex,\xFF\n".b) }.to raise_error(described_class::InvalidFile) do |error|
      expect(error.error).to eq(record_number: nil, stage: "encoding", column: nil, operation: "CSV",
                                reason: "input contains invalid UTF-8")
    end
  end

  it "rejects a UTF-16 BOM instead of silently transcoding the file" do
    csv = "\xFF\xFE".b + "name,amount\nAlex,1\n".encode("UTF-16LE").b

    expect { convert(csv) }.to raise_error(described_class::InvalidFile) do |error|
      expect(error.error).to include(stage: "encoding", record_number: nil, reason: "input must be UTF-8")
    end
    expect(output.string).to be_empty
  end

  it "stops on malformed CSV and preserves counts and earlier row errors alongside partial output" do
    expect { convert("name,amount\nfirst,1\nshort\n\"unterminated,2\n") }.to raise_error(described_class::InvalidFile) do |error|
      expect(error.error).to include(record_number: 4, stage: "parsing", operation: "CSV", reason: /Unclosed quoted field/)
      expect([error.result.accepted_rows, error.result.rejected_rows]).to eq([1, 1])
      expect(error.result.errors.map { |entry| entry.fetch(:record_number) }).to eq([3])
    end
    expect(output.string).to eq("copied\nfirst\n")
  end

  it "writes output before reaching the end of a file input" do
    Tempfile.create("csv-weave-input") do |input|
      input.write("name,amount\n")
      1_000.times { |index| input.write("#{'x' * 40}#{index},1\n") }
      input.rewind
      positions = []
      allow(output).to receive(:<<).and_wrap_original do |original, line|
        positions << input.pos
        original.call(line)
      end

      result = runner.run(input: input, output: output)

      expect(result.accepted_rows).to eq(1_000)
      expect(positions.first).to be < input.size
      expect(positions.size).to eq(1_001)
    end
  end

  it "resets counts and errors when the runner is reused" do
    rejected = convert("name,amount\nshort\n")
    output.truncate(0)
    output.rewind

    accepted = convert("name,amount\nAlex,1\n")

    expect([accepted.accepted_rows, accepted.rejected_rows, accepted.errors]).to eq([1, 0, []])
    expect([rejected.accepted_rows, rejected.rejected_rows, rejected.errors.size]).to eq([0, 1, 1])
  end

  it "propagates output IO failures" do
    allow(output).to receive(:<<).and_raise(IOError, "disk full")

    expect { convert("name,amount\nAlex,1\n") }.to raise_error(IOError, "disk full")
  end

  it "propagates unexpected processor exceptions" do
    allow(configuration.transformers.first).to receive(:transform).and_raise(RuntimeError, "processor bug")

    expect { convert("name,amount\nAlex,1\n") }.to raise_error(RuntimeError, "processor bug")
  end

  def convert(csv)
    runner.run(input: StringIO.new(csv), output: output)
  end
end
