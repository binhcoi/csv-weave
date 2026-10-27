require "rails_helper"
require "csv"

RSpec.describe "Configured validation and transformation pipeline", type: :model do
  let(:mapping) do
    Rails.application.load_seed
    input = FileType.create!(name: "Customer import")
    output = FileType.create!(name: "Customer export")
    input_columns = ["amount", "given_name", "family_name", "joined_on"].each_with_index.to_h do |name, position|
      [name, input.columns.create!(name: name, position: position)]
    end
    output_columns = ["label", "amount", "joined_date", "optional_note"].each_with_index.to_h do |name, position|
      [name, output.columns.create!(name: name, position: position * 2)]
    end
    ["amount", "given_name"].each { |name| add_validation(input_columns.fetch(name), "RequiredValidator") }
    add_validation(input_columns.fetch("joined_on"), "DateValidator", "format" => "%d/%m/%Y")
    add_validation(output_columns.fetch("label"), "LengthValidator", "max" => 30)
    add_validation(output_columns.fetch("amount"), "RequiredValidator")
    add_validation(output_columns.fetch("amount"), "NumericRangeValidator", "min" => 0, "max" => 100)
    add_validation(output_columns.fetch("joined_date"), "DateValidator", "format" => "%m/%d/%Y")
    map = TransformMap.create!(name: "Customer conversion", input_file_type: input, output_file_type: output)
    [
      ["joined_date", "DateParseTransformer", { "source_column" => "joined_on", "format" => "%d/%m/%Y", "output_format" => "%m/%d/%Y" }],
      ["label", "FormatStringTransformer", { "source_columns" => ["given_name", "family_name"], "format" => "%{family_name}, %{given_name}" }],
      ["amount", "DecimalParseTransformer", { "source_column" => "amount" }],
    ].each do |target, processor_class, settings|
      map.transformations.create!(output_column: output_columns.fetch(target), input_json: settings,
                                  column_transformer: ColumnTransformer.find_by!(processor_class: processor_class))
    end
    map
  end
  let(:loaded_map) do
    TransformMap.includes(
      input_file_type: { columns: { validations: :column_validator } },
      output_file_type: { columns: { validations: :column_validator } },
      transformations: [:column_transformer, :output_column],
    ).find(mapping.id)
  end
  let(:input_validators) { validators_for(loaded_map.input_file_type) }
  let(:output_validators) { validators_for(loaded_map.output_file_type) }
  let(:transformers) { loaded_map.transformations.map { |rule| rule.column_transformer.get_transformer(rule) } }
  let(:source) do
    csv = CSV.generate do |writer|
      writer << ["family_name", "joined_on", "amount", "given_name"]
      writer << ["Morgan", "29/02/2024", "12.50", "Alex, \"A\"\n李"]
    end
    CSV.parse(csv, headers: true).first
  end
  let(:destination) { CSV::Row.new(loaded_map.output_file_type.columns.map(&:name), [nil] * 4) }

  it "composes persisted rules into valid output and serializes the ordered CSV fields" do
    original = source.to_h

    expect(input_validators.map { |validator| validator.validate(source) }).to all(be true)
    expect(transformers.map { |transformer| transformer.transform(source, destination) }).to all(be_nil)
    expect(output_validators.map { |validator| validator.validate(destination) }).to all(be true)
    expect(destination.to_h).to eq(
      "label" => "Morgan, Alex, \"A\"\n李", "amount" => BigDecimal("12.50"),
      "joined_date" => "02/29/2024", "optional_note" => nil,
    )
    expect(source.to_h).to eq(original)

    csv = CSV.generate do |writer|
      writer << destination.headers
      writer << destination.fields
    end
    row = CSV.parse(csv, headers: true).first
    expect(row.headers).to eq(["label", "amount", "joined_date", "optional_note"])
    expect(row.values_at("label", "joined_date", "optional_note"))
      .to eq(["Morgan, Alex, \"A\"\n李", "02/29/2024", nil])
    expect(BigDecimal(row["amount"])).to eq(BigDecimal("12.50"))
  end

  it "identifies an input validation failure on the original CSV row" do
    source["given_name"] = ""
    original = source.to_h
    failures = input_validators.reject { |validator| validator.validate(source) }

    expect(failures.map { |validator| [validator.column.name, validator.class] })
      .to eq([["given_name", Validators::RequiredValidator]])
    expect(source.to_h).to eq(original)
  end

  it "returns a transformation failure for input that passes its configured validations" do
    source["amount"] = "invalid"
    original = source.to_h

    expect(input_validators.map { |validator| validator.validate(source) }).to all(be true)
    expect(transformers.map { |transformer| transformer.transform(source, destination) })
      .to eq([nil, nil, 'source column "amount" contains an invalid decimal'])
    expect(destination["amount"]).to be_nil
    expect(destination["label"]).to eq("Morgan, Alex, \"A\"\n李")
    expect(source.to_h).to eq(original)
  end

  it "rejects a successfully transformed value that violates the output format's rules" do
    source["amount"] = "100.01"
    original = source.to_h

    expect(input_validators.map { |validator| validator.validate(source) }).to all(be true)
    expect(transformers.map { |transformer| transformer.transform(source, destination) }).to all(be_nil)
    expect(destination["amount"]).to eq(BigDecimal("100.01"))
    failures = output_validators.reject { |validator| validator.validate(destination) }

    expect(failures.map { |validator| [validator.column.name, validator.class] })
      .to eq([["amount", Validators::NumericRangeValidator]])
    expect(source.to_h).to eq(original)
  end

  def add_validation(column, processor_class, settings = {})
    column.validations.create!(column_validator: ColumnValidator.find_by!(processor_class: processor_class), input_json: settings)
  end

  def validators_for(file_type)
    file_type.columns.flat_map(&:validations).map { |rule| rule.column_validator.get_validator(rule) }
  end
end
